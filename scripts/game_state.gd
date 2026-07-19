extends Node

const UnitScript = preload("res://scripts/unit.gd")

# Autoload (Project Settings -> Autoload) — uma instância só, viva o jogo
# inteiro, sobrevive a troca de cena (change_scene_to_file descarta a cena
# de origem inteira, incluindo o Player e sua posição; sem guardar isso em
# algum lugar fora da árvore da cena, essa informação se perderia toda vez
# que fôssemos pra batalha).
#
# Guarda onde o personagem estava no overworld antes de entrar em combate,
# pra devolver ele no mesmo lugar quando a batalha terminar em VITÓRIA (ver
# test.gd::_restore_player_state / battle.gd::end_battle).

var has_saved_position: bool = false
var player_grid_pos: Vector2i = Vector2i.ZERO
var player_facing: String = "down"
var overworld_scene_path: String = "res://scenes/overworld/test.tscn"

func save_player_state(cell: Vector2i, facing: String, scene_path: String = "res://scenes/overworld/test.tscn") -> void:
	has_saved_position = true
	player_grid_pos = cell
	player_facing = facing
	overworld_scene_path = scene_path

# Posição "ao vivo" do jogador no overworld — test.gd mantém isso atualizado
# a CADA passo (ver test.gd::_sync_live_position), diferente de
# player_grid_pos/player_facing acima, que só mudam no instante em que uma
# batalha começa. Existe só pra heal_active_roster() (ver abaixo) saber ONDE
# o jogador está no exato momento em que aperta "Heal" no Computador — nem
# pause_menu.gd nem computer_screen.gd têm uma referência direta ao Player
# pra perguntar isso na hora.
var live_grid_pos: Vector2i = Vector2i.ZERO
var live_facing: String = "down"

# Último lugar onde o jogador usou Computador -> Heal — é pra ONDE ele volta
# se o time inteiro for derrotado em batalha (ver battle.gd::end_battle).
# Começa no mesmo spawn padrão do Player (grid_pos ZERO, ver Player._ready())
# pra sempre ter um destino válido mesmo que o jogador nunca tenha curado
# nem uma vez ainda.
var last_heal_grid_pos: Vector2i = Vector2i.ZERO
var last_heal_facing: String = "down"

# --- Perfil do jogador / progresso (ver title_screen.gd, save_slot_screen.gd,
# name_entry_screen.gd, game_menu.gd) ---

# Escolhido na tela de "New Game" (ver name_entry_screen.gd) — o antigo Label
# fixo "PlayerName" do menu (ver game_menu.gd, era pause_menu.gd) agora
# mostra isto de verdade, junto com money/badges logo abaixo.
var player_name: String = ""

# Sempre inteiro (pedido do usuário). Antes só existia pra já aparecer no
# menu/save — agora merchant_buy_screen.gd/merchant_sell_screen.gd de fato
# gastam/ganham (ver spend_money/add_money logo abaixo).
var money: int = 0

func add_money(amount: int) -> void:
	money += amount

# false (sem mexer em money) se `amount` for maior que o que o jogador tem —
# é ISSO que impede completar uma compra sem dinheiro suficiente
# (merchant_buy_screen.gd já limita a quantidade escolhida ao que dá pra
# pagar, mas checar de novo aqui é a mesma segunda trava que use_item/
# give_item já fazem antes de agir).
func spend_money(amount: int) -> bool:
	if amount > money:
		return false
	money -= amount
	return true

# Nomes de badge conquistada — Array[String] simples porque ainda não existe
# nenhum sistema de ginásio/líder que CONCEDA uma badge de verdade; fica
# vazio até esse sistema existir. Existe já pra aparecer no menu/slot de save.
var badges: Array[String] = []

# Qual dos 3 slots (0, 1 ou 2 — ver SAVE_SLOT_COUNT abaixo) esta sessão está
# usando. -1 antes de New Game/Load Game escolher um; game_menu.gd só mostra
# a opção "Save" depois que já existe uma partida carregada, então
# save_game() nunca deveria ser chamado com isto ainda -1.
var current_save_slot: int = -1

# True enquanto o jogador está "montado" na Bicicleta (ver data/items/
# bicycle.tres, category Tool, toggles_bike = true) — ligado/desligado
# usando o item de novo (ver use_tool() abaixo). Mora em GameState (não em
# Player) porque troca de cena destrói e recria o Player inteiro (overworld
# -> batalha -> overworld); is_biking precisa sobreviver a isso. Player lê
# isso a CADA frame (ver Player._process) e sincroniza sprite/velocidade
# sozinho, então não importa quando/onde o toggle aconteceu.
var is_biking: bool = false

# 4 atalhos de item Tool (ver ItemData.can_register) — null = vazio. Usar um
# item registrado dispara o efeito direto (ver use_tool() abaixo), sem abrir
# a Bag — o atalho de teclado no overworld (1/2/3/4, ver test.gd::
# _trigger_tool_shortcut) já lê este array direto.
const TOOL_SHORTCUT_COUNT = 4
var tool_shortcuts: Array[ItemData] = [null, null, null, null]

# "boy" ou "girl" — qual conjunto de spritesheets do personagem principal usar
# (ver Player.SHEETS_BY_GENDER, que mapeia esse valor pros caminhos de
# walk/run/bike certos). Mora em GameState pelo mesmo motivo de is_biking:
# Player é destruído/recriado a cada troca de cena, então a escolha não pode
# morar nele. "boy" é o padrão só porque ainda não existe uma tela de "Novo
# Jogo" que pergunte isso ao jogador — quando essa tela existir, ela só
# precisa escrever aqui antes do World carregar pela primeira vez.
var player_gender: String = "boy"

# Time do jogador. Isso morava como @export var roster em battle.gd (só
# configurável no Inspector daquele scene específico) — mas assim que
# precisamos de uma tela de Party navegável a partir do overworld (fora de
# qualquer batalha), o roster tinha que virar algo acessível dos DOIS lados.
# GameState já é o autoload feito pra sobreviver a troca de cena, então é
# aqui que o time "de verdade" do jogador mora agora; battle.gd lê
# GameState.roster em vez de ter a própria cópia.
#
# Só até MAX_TEAM_SIZE membros, mas NÃO precisa estar cheio — slots vazios
# ficam como null dentro do array. Nada deve iterar `roster` direto pra
# spawnar unidade; use get_active_roster(), que já filtra os null.
const MAX_TEAM_SIZE = 6

# Limite de PESO total do time ativo — diferente de MAX_TEAM_SIZE (quantas
# unidades cabem), este é quanto elas "pesam" somadas (ver UnitData.weight,
# 0 a 4 por unidade). Com a maioria das espécies em weight=1, 6 unidades
# comuns já batem o limite exato; uma espécie mais pesada (ex: Mamoswine,
# weight=2) custa mais "espaço" e força abrir mão de outra unidade. Ver
# get_roster_weight() logo abaixo e pc_screen.gd, que é quem de fato barra o
# jogador de sair do PC enquanto o time estiver acima do limite.
const MAX_TEAM_WEIGHT = 6

# Nível DEFAULT de uma unidade do roster na primeira vez que ela é usada
# (ver UnitData.ensure_initialized, chamado em _ready() abaixo) — só pra já
# ter opções mais interessantes disponíveis de cara (ex: Ember, que o
# Charmander só aprende no nível 4) sem precisar batalhar antes.
#
# NÃO é mais usado pra inimigos selvagens — cada EncounterEntry já carrega
# seu próprio nível (ver encounter_entry.gd/encounter_area.gd), lido direto
# por battle.gd::spawn_enemies(); isso permite um grupo ter, por exemplo, um
# Mamoswine nível 54 ao lado de um Swinub nível 2 na mesma batalha.
const STARTING_LEVEL = 5

# .duplicate() em cada um — SEM isso, os 6 slots apontariam pro MESMO Resource
# que fica em cache (preload só carrega o arquivo uma vez por caminho); dois
# slots com a mesma espécie no futuro dividiriam nível/xp/HP um do outro.
# duplicate() sem argumento é raso: sub-resources (sprite_frames, portrait,
# ActionData dos slots) continuam compartilhados — só as propriedades da
# própria UnitData (nível, xp, hp, slots) viram cópias independentes, que é
# exatamente o que precisamos.
# Vazio de propósito — os 3 starters (Bulbasaur/Charmander/Squirtle) que
# moravam aqui foram removidos a pedido do usuário: agora eles vivem como
# LootBalls no laboratório do Oak (ver oak_lab_interior.tscn/loot_ball.gd,
# exclusive_flag = "STARTER1_CHOSEN"), escolhidos pelo jogador em vez de já
# começarem no time. _apply_fresh_state() abaixo (chamado em _ready(), ver
# comentário lá) é quem de fato monta os 6 slots (todos null até o jogador
# pegar uma unidade) — este literal aqui só existe como valor inicial do
# var antes do autoload sequer rodar.
var roster: Array[UnitData] = []

# ensure_initialized() só faz alguma coisa a primeira vez (current_hp ainda
# -1) — dá o nível/xp/HP inicial pra cada unidade do roster antes de
# qualquer tela (Party) ou batalha ler esses valores. O preenchimento de
# `storage` com null até STORAGE_CAPACITY é o que dá à reserva do PC seus
# slots vazios fixos (mesma ideia de `roster`, só que maior).
#
# _ready() de um autoload roda só UMA VEZ, na inicialização do jogo — por
# isso todo o corpo daquele "boot" virou _apply_fresh_state() abaixo, que
# pode ser chamada de novo (ver GameState.start_new_game(), usado por
# name_entry_screen.gd) sempre que o jogador escolher "New Game" DEPOIS que
# o jogo já está rodando há um tempo. Sem isso, escolher "New Game" numa
# sessão que já tinha progresso (dinheiro, roster evoluído, etc.) misturaria
# o estado antigo com o novo em vez de começar do zero de verdade.
func _ready() -> void:
	_apply_fresh_state()

# Estado de "jogo novo": roster/reserva/inventário padrão (mesmo dos 3
# starters de sempre), dinheiro/badges zerados, posição/área padrão. Refaz
# `roster` inteiro a partir dos .tres originais (.duplicate() de novo, mesmo
# motivo de sempre — sem isso, uma segunda chamada reaproveitaria as MESMAS
# instâncias já mutadas da partida anterior) em vez de só rodar
# ensure_initialized() em cima do que já estiver lá.
func _apply_fresh_state() -> void:
	# Time começa TOTALMENTE vazio (6 slots null) — os 3 starters fixos
	# (Bulbasaur/Charmander/Squirtle) que nasciam aqui foram removidos a
	# pedido do usuário, agora que eles existem como LootBalls escolhíveis
	# no laboratório do Oak (ver comentário grande no topo do arquivo, no
	# var roster). swap_roster_slots/swap_active_with_storage já lidam bem
	# com slot vazio (null) normalmente — preencher com null ATÉ
	# MAX_TEAM_SIZE (em vez de deixar o array com 0 elementos) continua
	# necessário pelo mesmo motivo de sempre: índice fora dos limites do
	# array rejeita qualquer troca de/pra aquele slot (bug antigo: não dava
	# pra arrastar uma unidade da reserva pro time se o roster não tivesse
	# TODOS os 6 slots já existindo, mesmo vazios).
	roster = []
	while roster.size() < MAX_TEAM_SIZE:
		roster.append(null)
	storage = []
	while storage.size() < STORAGE_CAPACITY:
		storage.append(null)
	giovanni_storage = []
	while giovanni_storage.size() < STORAGE_CAPACITY:
		giovanni_storage.append(null)
	_seed_testing_storage()
	inventory = {}
	_seed_starting_inventory()
	tool_shortcuts = [null, null, null, null]
	is_biking = false
	player_gender = "boy"
	money = 0
	badges = []
	defeated_trainer_badges = {}
	vanished_trainers = {}
	trainer_positions = {}
	trainer_facings = {}
	has_saved_position = false
	player_grid_pos = Vector2i.ZERO
	player_facing = "down"
	live_grid_pos = Vector2i.ZERO
	live_facing = "down"
	last_heal_grid_pos = Vector2i.ZERO
	last_heal_facing = "down"
	current_area = preload("res://data/areas/starting_area.tres")
	last_notified_area_name = ""
	overworld_scene_path = "res://scenes/overworld/test.tscn"

# Reserva "de teste": bota uma cópia de CADA espécie já implementada (ver
# ALL_SPECIES, mais abaixo) direto na reserva do PC, todas no nível 70 — pra
# testar ataque/interação/evolução nova (ex: Growl, ou a evolução Piloswine
# -> Mamoswine que exige Ancient Power equipado) sem precisar caçar/subir de
# nível cada espécie selvagem primeiro. Mesma ideia de
# _seed_starting_inventory() logo abaixo, só que pra unidades em vez de
# item; remover esta chamada (em _ready()) quando o jogo não precisar mais
# desse atalho de teste.
# .duplicate() em cada uma, mesmo motivo do roster lá em cima — sem isso,
# todas as cópias da mesma espécie (aqui e uma eventual capturada depois)
# dividiriam nível/xp/HP entre si.
func _seed_testing_storage() -> void:
	for species in ALL_SPECIES:
		var data: UnitData = species.duplicate()
		data.ensure_initialized(70)
		add_to_first_empty_storage_slot(data)

func get_active_roster() -> Array[UnitData]:
	var active: Array[UnitData] = []
	for data in roster:
		if data != null:
			active.append(data)
			if active.size() >= MAX_TEAM_SIZE:
				break
	return active

# Soma o weight (ver UnitData.weight) de toda unidade ativa no time — usado
# só pra checar contra MAX_TEAM_WEIGHT (ver pc_screen.gd, que mostra o aviso
# "Limite de peso excedido" e trava a saída do PC enquanto isto for maior que
# o limite). Slot vazio (null) não pesa nada, por isso o "if data != null".
func get_roster_weight() -> int:
	var total = 0
	for data in roster:
		if data != null:
			total += data.weight
	return total

# Lê o slot bruto (posição 0..5 no array, PODE ser null) — diferente de
# get_active_roster(), que compacta e ignora os vazios. A tela de Party
# precisa saber exatamente qual slot está vazio pra desenhar certo.
func get_roster_slot(index: int) -> UnitData:
	if index < 0 or index >= roster.size():
		return null
	return roster[index]

# Troca dois slots de posição (usado pela tela de Party pra reordenar o
# time) — a ordem no array é o que decide a ordem de deploy em batalha (ver
# get_staging_position em battle.gd), então isso já tem efeito real na
# próxima batalha, não é só cosmético.
func swap_roster_slots(a: int, b: int) -> void:
	if a < 0 or a >= roster.size() or b < 0 or b >= roster.size():
		return
	var tmp = roster[a]
	roster[a] = roster[b]
	roster[b] = tmp

# Sobrescreve UM slot do time com uma UnitData já pronta — diferente de
# swap_roster_slots (troca dois slots ENTRE si), aqui é uma substituição
# direta de um só. Usado hoje só por party_screen.gd::_perform_evolution():
# evoluir troca a espécie por baixo (nova UnitData, mesmo nível/xp/loadout
# preservados — ver comentário lá), então o slot precisa ser SUBSTITUÍDO,
# não trocado com outro.
func set_roster_slot(index: int, data: UnitData) -> void:
	if index < 0 or index >= roster.size():
		return
	roster[index] = data

# Usado por loot_ball.gd (recompensa "Unit" com add_to_active_team = true) —
# tenta colocar `data` no time ATIVO em vez da reserva do PC (ver
# add_to_first_empty_storage_slot acima). Devolve "" em sucesso, ou uma
# mensagem de erro pronta pra mostrar ao jogador se não coube — duas razões
# possíveis:
#   - TIME CHEIO: nenhum slot vazio nos MAX_TEAM_SIZE.
#   - LIMITE DE PESO: get_roster_weight() + data.weight passaria de
#     MAX_TEAM_WEIGHT.
# Diferente de pc_screen.gd (que deixa o jogador passar do limite de peso
# TEMPORARIAMENTE, só bloqueia a SAÍDA do PC até ele resolver — ver
# comentário de MAX_TEAM_WEIGHT), aqui não existe "arrumar depois": ou cabe
# na hora, ou a unidade não é adicionada — por isso a checagem acontece
# ANTES de mexer no array, nunca depois.
func add_to_first_empty_roster_slot(data: UnitData) -> String:
	var free_index := -1
	for i in roster.size():
		if roster[i] == null:
			free_index = i
			break
	if free_index == -1:
		return "Your team is full!"
	if get_roster_weight() + data.weight > MAX_TEAM_WEIGHT:
		return "%s is too heavy for your team right now!" % data.unit_name
	roster[free_index] = data
	return ""

# Chamada só por battle.gd::resolve_capture, quando um treinador Rocket
# rouba uma unidade do jogador — tira `data` de qualquer slot do time ATIVO
# em que ela esteja (fica null, igual um slot nunca preenchido), ANTES dela
# ir pra giovanni_storage (ver add_to_first_empty_giovanni_slot, chamado à
# parte por resolve_capture). Sem isso, a MESMA UnitData ficava referenciada
# no roster E na caixa do Giovanni ao mesmo tempo, e a unidade continuava
# aparecendo normalmente no time do jogador. .find() compara por
# IDENTIDADE (é a mesma instância de Resource, não uma cópia — ver
# Unit.apply_persisted_data), então isso nunca remove a unidade ERRADA,
# mesmo com duas unidades da mesma espécie/nível no time.
func remove_from_roster(data: UnitData) -> void:
	var index = roster.find(data)
	if index != -1:
		roster[index] = null

# "Caixa" do Computador — unidades que o jogador tem mas não estão no time
# ativo (ver pc_screen.gd). Tamanho FIXO (STORAGE_CAPACITY), igual `roster`
# — a maioria dos slots começa vazia (null), mostrada na tela como um
# quadradinho vazio esperando por uma unidade. Ter slots vazios de verdade
# (em vez de só uma lista que cresce/encolhe) é o que permite depositar uma
# unidade do time num slot vazio da reserva e o time ficar com um buraco —
# ver swap_active_with_storage abaixo, que vira um swap simples e direto
# assim que os dois lados (roster e storage) têm o mesmo conceito de "slot
# vazio = null".
#
# `storage` continua um array FLAT só — "Box" (ver pc_screen.gd) é só uma
# forma de pc_screen.gd mostrar uma FATIA de 48 por vez em vez da reserva
# inteira de uma vez (a mesma ideia de paginação, sem paginação de verdade
# nenhuma aqui). Índice absoluto de um slot = box * SLOTS_PER_BOX +
# posição dentro da box — GameState nem precisa saber em qual box um índice
# "está", só oferece o array inteiro; toda a lógica de qual fatia mostrar
# mora inteiramente em pc_screen.gd.
const SLOTS_PER_BOX = 48
const BOX_COUNT = 6
const STORAGE_CAPACITY = SLOTS_PER_BOX * BOX_COUNT

var storage: Array[UnitData] = []

func get_storage_slot(index: int) -> UnitData:
	if index < 0 or index >= storage.size():
		return null
	return storage[index]

# Troca dois slots DENTRO da reserva.
func swap_storage_slots(a: int, b: int) -> void:
	if a < 0 or a >= storage.size() or b < 0 or b >= storage.size():
		return
	var tmp = storage[a]
	storage[a] = storage[b]
	storage[b] = tmp

# Adiciona uma UnitData na primeira posição VAZIA da reserva — usado pela
# captura de unidades selvagens (ver battle.gd::resolve_capture), que
# sempre manda a unidade capturada direto pro PC, nunca pro time ativo (o
# jogador decide depois, na tela do Computador, se quer trocar alguém do
# time por ela). Mesmo padrão de busca de slot vazio que give_item() já usa
# pra loadout, só que em `storage` em vez de `target.slots`. Retorna false
# (sem adicionar nada) se a reserva estiver TOTALMENTE cheia — bem
# improvável (STORAGE_CAPACITY = 288), mas o caso fica registrado mesmo
# assim.
func add_to_first_empty_storage_slot(data: UnitData) -> bool:
	for i in storage.size():
		if storage[i] == null:
			storage[i] = data
			return true
	return false

# "Giovanni's Account" — reserva separada só pras unidades que o jogador
# PERDEU pra um treinador Rocket (ver battle.gd::resolve_capture, chamado
# quando um `defender.is_enemy == false` é "capturado": a unidade do
# jogador vai pra cá em vez de pra `storage` normal). Mesmo formato/tamanho
# fixo de `storage` (slot vazio = null, mesma paginação em "Box" feita por
# pc_screen.gd) — pedido do usuário: "that works in exactly the same way
# 'PLAYERNAME's Account' works". A diferença toda mora em QUEM pode ver essa
# caixa (ver GameState.flags "GIOVANNI_ACCOUNT_UNLOCKED" e open_pc.gd), não
# em como ela funciona por dentro.
var giovanni_storage: Array[UnitData] = []

func get_giovanni_slot(index: int) -> UnitData:
	if index < 0 or index >= giovanni_storage.size():
		return null
	return giovanni_storage[index]

func swap_giovanni_slots(a: int, b: int) -> void:
	if a < 0 or a >= giovanni_storage.size() or b < 0 or b >= giovanni_storage.size():
		return
	var tmp = giovanni_storage[a]
	giovanni_storage[a] = giovanni_storage[b]
	giovanni_storage[b] = tmp

# Chamada por resolve_capture() quando um treinador Rocket rouba a unidade
# do jogador — mesmo padrão de add_to_first_empty_storage_slot acima, só
# que na caixa do Giovanni. O jogador resgata de volta pro time via
# swap_active_with_giovanni() abaixo, exatamente como já faz com a reserva
# normal (swap_active_with_storage).
func add_to_first_empty_giovanni_slot(data: UnitData) -> bool:
	for i in giovanni_storage.size():
		if giovanni_storage[i] == null:
			giovanni_storage[i] = data
			return true
	return false

# Gêmea de swap_active_with_storage, só que trocando com giovanni_storage em
# vez de storage — usada quando o jogador resgata uma unidade roubada de
# volta pro time ativo (ver comentário grande em swap_active_with_storage
# pros 4 casos possíveis, mesma lógica aqui).
func swap_active_with_giovanni(active_index: int, giovanni_index: int) -> void:
	if active_index < 0 or active_index >= roster.size():
		return
	if giovanni_index < 0 or giovanni_index >= giovanni_storage.size():
		return
	# Mesma guarda de swap_active_with_storage: não deixa o time ativo ficar
	# TOTALMENTE vazio (a última unidade do time não pode ser depositada).
	if roster[active_index] != null and giovanni_storage[giovanni_index] == null:
		var active_count = 0
		for data in roster:
			if data != null:
				active_count += 1
		if active_count <= 1:
			return
	var tmp = roster[active_index]
	roster[active_index] = giovanni_storage[giovanni_index]
	giovanni_storage[giovanni_index] = tmp

# Troca uma unidade do time ATIVO por uma da RESERVA (as duas únicas
# operações que o PC sabe fazer, ver pc_screen.gd — reordenar dentro do
# time usa swap_roster_slots, dentro da reserva usa swap_storage_slots
# acima, e essa aqui cobre o caso "entre as duas listas"). Um swap comum já
# cobre os 4 casos possíveis sozinho, quase sem checagem nenhuma:
#   - time cheio <-> reserva cheia: as duas trocam de lugar
#   - time cheio <-> reserva vazia: "deposita" a unidade (time fica vazio) —
#     EXCETO se for a última unidade ativa, ver guarda abaixo
#   - time vazio <-> reserva cheia: "resgata" a unidade (reserva fica vazia)
#   - time vazio <-> reserva vazia: troca dois nulls, sem efeito nenhum
func swap_active_with_storage(active_index: int, storage_index: int) -> void:
	if active_index < 0 or active_index >= roster.size():
		return
	if storage_index < 0 or storage_index >= storage.size():
		return

	# Não deixa o time ativo ficar TOTALMENTE vazio. battle.gd só chama
	# start_battle() quando o jogador termina de posicionar TODAS as
	# unidades staged (ver check_deploy_complete) — com roster inteiro
	# vazio, spawn_player_units_staged() não cria nenhuma unidade, então
	# esse gatilho nunca dispara e o jogador fica preso na fase de Deploy
	# pra sempre, sem nada pra clicar. Só bloqueia quando a troca de fato
	# esvaziaria o slot (reserva de destino vazia) E essa é a ÚLTIMA
	# unidade ativa restante — mover pra um slot de reserva OCUPADO nunca
	# esvazia o time (troca uma unidade pela outra), então isso continua
	# liberado normalmente.
	if roster[active_index] != null and storage[storage_index] == null:
		var active_count = 0
		for data in roster:
			if data != null:
				active_count += 1
		if active_count <= 1:
			return

	var tmp = roster[active_index]
	roster[active_index] = storage[storage_index]
	storage[storage_index] = tmp

# Cura completamente o time ATIVO (roster, não a reserva) — usado pelo botão
# Heal do Computador. Ignora slots vazios (null); usa a mesma fórmula de HP
# máximo de sempre (Unit.calc_hp_static), no nível atual de cada unidade.
#
# Também registra ESTE lugar/momento como o novo "checkpoint" de derrota
# (ver last_heal_grid_pos/last_heal_facing acima) — copia de live_grid_pos/
# live_facing, que test.gd mantém sempre atualizado com a posição de
# verdade do jogador. Assim, se o time inteiro desmaiar numa batalha
# qualquer (mesmo longe daqui), battle.gd::end_battle sabe pra onde mandar
# o jogador de volta.
func heal_active_roster() -> void:
	for data in roster:
		if data != null:
			data.current_hp = UnitScript.calc_hp_static(data.hp_base, data.level, data.weight)
	last_heal_grid_pos = live_grid_pos
	last_heal_facing = live_facing

# Catálogo de TODAS as espécies já implementadas no jogo — NÃO é o time do
# jogador nem a reserva do PC (roster/storage guardam só o que o jogador
# TEM; isso aqui é "isso existe no jogo", ponto). battle.gd::spawn_enemies()
# não sorteia mais direto daqui (ver current_area abaixo — quem
# aparece agora é decidido por EncounterArea/EncounterGroup, por área do
# overworld); isso continua existindo como catálogo geral pra qualquer
# sistema futuro que precise "escolher uma espécie qualquer" (loja,
# Pokédex, evento aleatório).
#
# SEM .duplicate() de propósito, diferente de `roster`: essas instâncias
# nunca são mutadas (inimigos usam Unit.apply_fresh_data, que só LÊ dados
# base — nunca escreve level/xp/current_hp de volta aqui), então não tem
# risco de uma unidade inimiga vazar estado pra outra que aponte pro mesmo
# UnitData — inclusive é isso que permite a MESMA espécie aparecer mais de
# uma vez entre os inimigos sem duplicar nada.
const ALL_SPECIES: Array[UnitData] = [
	preload("res://data/units/0001.tres"),
	preload("res://data/units/0004.tres"),
	preload("res://data/units/0007.tres"),
	preload("res://data/units/0220.tres"),
	preload("res://data/units/0358.tres"),
	preload("res://data/units/0158.tres"),
	preload("res://data/units/0473.tres"),
	preload("res://data/units/0202.tres"),
	preload("res://data/units/0255.tres"),
	preload("res://data/units/0221.tres"),
	preload("res://data/units/0002.tres"),
	preload("res://data/units/0003.tres"),
	preload("res://data/units/0005.tres"),
	preload("res://data/units/0006.tres"),
	preload("res://data/units/0008.tres"),
	preload("res://data/units/0009.tres"),
	preload("res://data/units/0010.tres"),
	preload("res://data/units/0011.tres"),
	preload("res://data/units/0012.tres"),
	preload("res://data/units/0019.tres"),
	preload("res://data/units/0020.tres"),
]

# Em qual área do overworld o jogador está AGORA — test.gd seta isso (a
# partir do seu próprio @export var encounter_area) assim que a cena
# carrega (ver test.gd::_enter_area), e é o mesmo valor que sobrevive à
# troca de cena pra battle.tscn, onde battle.gd::spawn_enemies() lê daqui
# pra saber QUAIS unidades selvagens podem aparecer e com que peso (ver
# encounter_area.gd/encounter_group.gd). Um EncounterArea já carrega tanto o
# NOME da área (area_name, usado pela notificação de "você entrou em...")
# quanto sua tabela de encontros — as duas informações vivem juntas de
# propósito, não tem sentido uma área "ter" um nome sem ter (nem que vazia)
# uma lista de encontros, ou vice-versa.
#
# O valor default abaixo (a área inicial) é só uma rede de segurança pra
# spawn_enemies() nunca ficar sem tabela nenhuma — no fluxo normal, test.gd
# sempre sobrescreve isso ao carregar.
var current_area: EncounterArea = preload("res://data/areas/starting_area.tres")

# ---------- Batalha contra Trainer (ver trainer.gd) ----------
# Espelha, do mesmo jeito que current_area faz pra encontro selvagem, os
# dados que battle.gd precisa DEPOIS que change_scene_to_file() já destruiu
# a cena de overworld inteira (Trainer incluso) — sem isso, spawn_enemies()
# não teria como saber "qual time botar em campo" numa batalha de Trainer.
# test.gd::start_trainer_battle() preenche os quatro antes de trocar de cena;
# battle.gd::end_battle() zera de volta depois (vitória ou derrota), pra uma
# batalha selvagem seguinte não pensar por engano que ainda é contra Trainer.

# false (padrão) = próxima batalha é um encontro selvagem normal (spawna de
# current_area, ver battle.gd::spawn_enemies). true = próxima batalha spawna
# de current_trainer_team em vez disso, e resolve_capture() falha QUALQUER
# Ball na hora (regra do usuário: "Balls will ALWAYS fail... on a trainer
# battle") — não interessa is_trainer_battle é lido, não guardado por
# Trainer nenhum, então nada precisa reverter isso manualmente: end_battle()
# sempre volta pra false ao sair da batalha, batalha selvagem nenhuma corre
# risco de "herdar" true por acidente.
var is_trainer_battle: bool = false

# trainer_id da instância atual (ver trainer.gd) — usado só pra registrar em
# defeated_trainer_badges na vitória (ver end_battle). "" enquanto
# is_trainer_battle for false.
var current_trainer_id: String = ""

# Time ativo (Trainer.get_active_team(), já resolvido pro tier de badge
# certo) da batalha atual — Array[TrainerTeamEntry], mesmo formato de
# EncounterGroup.entries só que com loadout opcional por entrada (ver
# trainer_team_entry.gd).
var current_trainer_team: Array[TrainerTeamEntry] = []

# Prêmio em dinheiro (Trainer.get_prize_money(), já calculado: nível mais
# alto do time x modifier da classe — regra 2 do usuário) — creditado em
# money só se o jogador VENCER (ver battle.gd::end_battle).
var current_trainer_prize: int = 0

# Trainer.iq (ver comentário grande lá) — copiado pra cá junto dos outros
# 3 current_trainer_* antes da troca de cena, e usado por battle.gd::
# _spawn_enemy_unit pra sobrescrever o iq individual de CADA unidade
# spawnada deste time (não só a primeira). "" (nunca uma batalha selvagem
# de verdade tem isso preenchido) = não sobrescreve nada, cada UnitData usa
# o próprio iq.
var current_trainer_iq: String = ""

# trainer_id -> GameState.badges.size() de quando esse Trainer foi
# derrotado (vitória do jogador) pela ÚLTIMA vez — regra 6 do usuário:
# "Once defeated, they will NOT force a battle again, but the player may
# battle them again by interacting after winning a new badge". Duas
# perguntas, um Dictionary só:
#   - "já foi derrotado alguma vez?" == defeated_trainer_badges.has(id)
#     (trainer.gd usa isso pra desligar o gatilho automático de Spot
#     Behavior de vez — nunca mais força batalha, mesmo depois de uma
#     badge nova)
#   - "pode bater de novo AGORA?" == badges.size() > defeated_trainer_badges[id]
#     (trainer.gd::interact() usa isso — só permite revanche se o número de
#     badges realmente SUBIU desde a última derrota; interagir sem badge
#     nova não faz nada, ver comentário lá)
var defeated_trainer_badges: Dictionary = {}

# trainer_id -> true, pra cada Trainer com iq == "Rocket" que já entrou em
# batalha ao menos uma vez — pedido do usuário: "Rocket trainers also
# vanish after defeating or being defeated. They cannot be rematched".
# Diferente de defeated_trainer_badges acima (rematch libera com badge
# nova), um Trainer Rocket marcado aqui NUNCA mais aparece, não importa o
# resultado da luta (vitória OU derrota do jogador) nem quantas badges
# vierem depois — mesmo espírito "some pra sempre, só has() importa" de
# collected_loot logo abaixo, só que pra Trainer em vez de LootBall.
# Marcado por battle.gd::end_battle() assim que a batalha termina, ainda
# com GameState.current_trainer_iq == "Rocket" disponível (lido ANTES
# desse campo ser limpo de volta pro estado neutro); lido por
# trainer.gd::_ready(), que se destrói na hora (queue_free), igual
# loot_ball.gd já faz com collected_loot, se este trainer_id estiver aqui.
var vanished_trainers: Dictionary = {}

# trainer_id -> grid_pos/facing de onde esse Trainer parou por ÚLTIMO, escrito
# por Trainer._begin_battle() (ver trainer.gd) bem antes de start_trainer_
# battle() destruir a cena inteira. Sem isso, um Trainer que andou até o
# jogador (Spinner/Walker/Stander perseguindo, ver _advance_toward_player)
# voltava pra posição AUTORADA na .tscn toda vez que a cena recarregava
# depois da batalha — pedido do usuário: "the trainer must remain on the spot
# they moved to when going towards the player, at the end of combat". Só tem
# entrada pra Trainer que já chegou a entrar em batalha ao menos uma vez;
# trainer.gd::_ready() usa has() pra saber se deve sobrescrever a posição
# autorada ou deixar como está (primeira vez, nunca perseguiu ninguém ainda).
var trainer_positions: Dictionary = {}
var trainer_facings: Dictionary = {}

# loot_id (ver LootBall.loot_id) -> true, pra cada LootBall já aberta —
# mesmo espírito de defeated_trainer_badges acima, só que sem "pode de
# novo" nenhum: uma LootBall aberta some PRA SEMPRE (queue_free), então só
# precisa de has() (não importa o valor, sempre true) pra loot_ball.gd
# saber, em _ready(), se deve se destruir na hora em vez de aparecer de
# novo depois de recarregar a cena (ex: voltando de uma batalha "Battle").
var collected_loot: Dictionary = {}

# Flags de progresso GENÉRICAS (nome -> bool) — diferente de collected_loot
# (que é sempre "esta LootBall específica já foi aberta"), flags são pra
# qualquer evento de história que precise ser lembrado e não tem uma classe
# própria já cuidando disso. Motivo de existir agora: pedido do usuário
# pros LootBalls do laboratório do Oak — "It also needs a flag
# STARTER1_CHOSEN that stops the player from being able to take the unit
# ... Taking any STARTER1 unit makes the flag true" — três LootBalls
# diferentes (um por starter) compartilhando o MESMO nome de flag é o que
# implementa "escolha exclusiva" (pegar um bloqueia os outros dois), sem
# precisar de um Dictionary/sistema dedicado só pra isso. Ver
# loot_ball.gd::exclusive_flag.
var flags: Dictionary = {}

func get_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false)

func set_flag(flag_name: String, value: bool = true) -> void:
	if flag_name == "":
		return
	flags[flag_name] = value

# Nome da última área que já mostrou a notificação de entrada (ver
# area_notification.gd) — existe só pra test.gd saber se a área que está
# carregando agora é REALMENTE nova (mostra notificação) ou é a mesma de
# antes (ex: voltando de uma batalha pro mesmo mapa — não deve notificar de
# novo). Comparar por NOME (String) em vez de comparar o Resource
# EncounterArea direto é de propósito: mesmo que no futuro duas cenas
# diferentes apontem pro mesmo arquivo .tres de área (instâncias diferentes,
# mesmo conteúdo), o nome ainda identifica "é o mesmo lugar" corretamente.
var last_notified_area_name: String = ""

# Inventário de itens do jogador (ver ItemData/bag_screen.gd/
# item_list_screen.gd). Dictionary em vez de Array porque item não tem
# estado próprio nenhum pra guardar por instância (diferente de UnitData,
# que precisa de nível/xp/HP individuais) — só "quantos eu tenho", que é
# exatamente o que um mapa ItemData -> int já representa sozinho. As
# ItemData usadas como chave aqui são as MESMAS instâncias compartilhadas
# de ALL_SPECIES/ActionData (sem duplicate() nenhum, de propósito).
var inventory: Dictionary = {}

# Estoque inicial só pra Bag não abrir vazia. Sem sistema de loja/drop
# ainda — ajustar/expandir aqui livremente conforme esses sistemas forem
# aparecendo.
func _seed_starting_inventory() -> void:
	add_item(preload("res://data/items/potion.tres"), 3)
	add_item(preload("res://data/items/super_potion.tres"), 1)
	add_item(preload("res://data/items/oran_berry.tres"), 2)
	add_item(preload("res://data/items/focus_band.tres"), 1)
	add_item(preload("res://data/items/masterball.tres"), 1)   # só pra já dar pra testar captura
	add_item(preload("res://data/items/pokeball.tres"), 5)     # 5 pra testar fracassos (Master Ball nunca falha)
	add_item(preload("res://data/items/tm10_ice_fang.tres"), 8) # 8 pra testar Stackable + consumo em batalha
	add_item(preload("res://data/items/bicycle.tres"), 1)       # Tool: Use liga/desliga is_biking, nunca é consumida
	add_item(preload("res://data/items/ability_patch.tres"), 1) # pra testar revelar Sheer Force do Totodile (0158)

func add_item(item: ItemData, amount: int = 1) -> void:
	inventory[item] = get_item_quantity(item) + amount

# Contraparte de add_item — usado por merchant_sell_screen.gd ao vender
# (tira do inventário) e por qualquer outro consumo futuro que precise
# remover sem passar pelos fluxos específicos (give_item/use_tool/etc, que
# já mexem em inventory[item] direto). Nunca deixa negativo (max com 0) —
# mesmo espírito defensivo de spend_money() logo abaixo, ainda que quem
# chama já devesse ter conferido a quantidade antes.
func remove_item(item: ItemData, amount: int) -> void:
	inventory[item] = max(get_item_quantity(item) - amount, 0)

func get_item_quantity(item: ItemData) -> int:
	return inventory.get(item, 0)

# Usado pela Bag pra listar só os itens de UMA categoria que o jogador
# realmente possui (quantidade > 0) — itens zerados ficam de fora mesmo que
# ainda estejam na chave do Dictionary (add_item nunca remove a entrada).
func get_items_in_category(category: String) -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in inventory:
		if item.category == category and inventory[item] > 0:
			result.append(item)
	result.sort_custom(func(a, b): return a.action_name < b.action_name)
	return result

# Quantos slots de loadout (Array[ActionData]) toda unidade tem — mesmo
# valor de unit_loadout.gd::SLOT_COUNT, duplicado aqui em vez de importado
# porque unit_loadout.gd não é class_name global (é uma cena/CanvasLayer,
# não faz sentido virar dependência de GameState). Usado só por give_item()
# abaixo, pra garantir que data.slots já tem os 6 espaços (alguns .tres de
# unidade não preenchem os 6 na mão, ficam menores até algo os completar).
const LOADOUT_SLOT_COUNT = 6

# "Use" de um item (ver ItemData.can_use) — cura heal_amount HP da unidade
# alvo (clampado no HP máximo dela, calculado no nível atual), revela a
# Habilidade Hidden dela se o item fizer isso (ver ItemData.
# reveals_hidden_ability, ex: Ability Patch), e consome 1 unidade do
# inventário. Os dois efeitos são independentes (um item podia até ter os
# dois, embora nenhum tenha hoje) — cada um só roda se o campo dele estiver
# configurado. Não faz nada se o jogador não tiver o item (defesa contra
# chamada indevida; a Bag só deveria oferecer "Use" quando
# get_item_quantity > 0).
func use_item(item: ItemData, target: UnitData) -> void:
	if item == null or target == null or get_item_quantity(item) <= 0:
		return
	var hp_max = UnitScript.calc_hp_static(target.hp_base, target.level, target.weight)
	# Item que só cura não faz nada num alvo com HP já cheio — não consome
	# nem "usa" à toa. item_list_screen.gd já filtra isso na escolha do alvo
	# (ver picker_filter); esta é só a segunda trava, mesmo padrão de
	# battle.gd re-conferir antes de agir mesmo com o botão já desabilitado.
	if item.heal_amount > 0 and target.current_hp >= hp_max:
		return
	# Mesma lógica pro Ability Patch: não faz nada (não consome) numa
	# unidade sem Habilidade Hidden nenhuma pra revelar, ou que já revelou
	# a dela — item_list_screen.gd já filtra isso na escolha do alvo, esta
	# é a segunda trava.
	if item.reveals_hidden_ability and not target.has_unrevealed_hidden_ability():
		return
	target.current_hp = min(target.current_hp + item.heal_amount, hp_max)
	if item.reveals_hidden_ability:
		target.hidden_ability_revealed = true
	inventory[item] = get_item_quantity(item) - 1

# "Use" de um item Tool (ver ItemData.category == "Tool") — diferente de
# use_item() acima, NÃO tem unidade alvo nenhuma (o efeito é sobre o
# TREINADOR, não sobre um Pokémon) e NÃO consome o item (Tool pode ser usado
# infinitas vezes, ver comentário em ItemData). item_list_screen.gd chama
# isso em vez de abrir o seletor de unidade quando category == "Tool".
#
# Cada efeito de Tool novo vira mais um "if item.<campo>" aqui, do mesmo
# jeito que battle.gd tem um bloco por categoria pra Ball/TM — hoje só
# existe toggles_bike (Bicycle).
func use_tool(item: ItemData) -> void:
	if item == null:
		return
	if item.toggles_bike:
		is_biking = not is_biking

# True se `item` já ocupa um dos 4 atalhos de Tool — item_action_menu.gd usa
# isso pra decidir se mostra "Register" ou "Unregister" (ver ItemData.
# can_register).
func is_item_registered(item: ItemData) -> bool:
	return tool_shortcuts.has(item)

# Bota `item` no atalho `slot_index`, substituindo o que estivesse lá (sem
# checagem nenhuma de "já ocupado" — sobrescrever é a intenção, mesmo
# espírito de unit_loadout.gd::_choose_picker_option ao trocar a ação de um
# slot já preenchido).
func register_tool(item: ItemData, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= tool_shortcuts.size():
		return
	tool_shortcuts[slot_index] = item

# Tira `item` de qualquer atalho que ele esteja ocupando (fica vazio de
# novo, null) — usado pela opção "Unregister" (ver item_list_screen.gd).
func unregister_tool(item: ItemData) -> void:
	var index = tool_shortcuts.find(item)
	if index != -1:
		tool_shortcuts[index] = null

# "Give" de um item (ver ItemData.can_give) — bota o item no primeiro slot
# VAZIO do loadout da unidade alvo (não substitui nada já equipado) e
# consome `amount` unidades do inventário. Retorna false (sem consumir
# nada) se não houver slot vazio — cabe à UI (item_list_screen.gd) avisar o
# jogador desse caso, hoje só via print (ver comentário lá).
#
# amount só importa pra item Stackable (ver ItemData.stackable — Ball/TM):
# clampado entre 1 e min(99, quanto o jogador tem) — é ESSA quantidade que
# ocupa o slot inteiro de uma vez (ver UnitData.set_slot_quantity), não 1
# slot por unidade. Item NÃO-stackable ignora amount por completo, sempre
# consome exatamente 1 (mesmo comportamento de antes desse parâmetro
# existir) — dar 5 Focus Band não faz sentido, um item não-empilhável
# sempre ocupa 1 slot = 1 unidade.
func give_item(item: ItemData, target: UnitData, amount: int = 1) -> bool:
	if item == null or target == null or get_item_quantity(item) <= 0:
		return false
	while target.slots.size() < LOADOUT_SLOT_COUNT:
		target.slots.append(null)
	var give_amount = clampi(amount, 1, min(99, get_item_quantity(item))) if item.stackable else 1
	for i in target.slots.size():
		if target.slots[i] == null:
			target.slots[i] = item
			if item.stackable:
				target.set_slot_quantity(i, give_amount)
			inventory[item] = get_item_quantity(item) - give_amount
			return true
	return false

# --- Save/Load (ver save_data.gd, title_screen.gd, save_slot_screen.gd,
# name_entry_screen.gd, game_menu.gd) ---

# 3 slots fixos (pedido do usuário) — cada um é um arquivo .tres separado em
# user://, não dentro de res:// (ver comentário grande em save_data.gd sobre
# por quê). SAVE_SLOT_COUNT é usado tanto por save_slot_screen.gd (pra saber
# quantas linhas desenhar) quanto por title_screen.gd (pra saber se existe
# ALGUM save, decidindo se mostra "Load Game").
const SAVE_SLOT_COUNT = 3

func _save_path(slot: int) -> String:
	return "user://save_slot_%d.tres" % slot

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_save_path(slot))

# Carrega um slot só pra LER um resumo (nome + badges, ver save_slot_screen.gd)
# sem aplicar nada em GameState — load_game() abaixo é quem de fato troca o
# estado atual pelo do save. CACHE_MODE_IGNORE evita que o Godot devolva uma
# instância em cache de uma leitura anterior do mesmo caminho (o slot pode
# ter sido sobrescrito por um save_game() novo desde a última vez que
# alguém olhou pra ele, ex: save_slot_screen reabrindo depois de um
# "New Game" que escreveu por cima do mesmo slot).
func peek_save(slot: int) -> SaveData:
	if not has_save(slot):
		return null
	return ResourceLoader.load(_save_path(slot), "SaveData", ResourceLoader.CACHE_MODE_IGNORE) as SaveData

# Sobrescreve o slot com o estado ATUAL de GameState — mesma função tanto
# pro primeiro save de uma partida nova (ver start_new_game() abaixo) quanto
# pra "Save" do game_menu.gd (que sempre sobrescreve o slot já em uso, ver
# current_save_slot). ResourceSaver.save() serializa roster/storage/
# inventory_items (Array de Resource, incluindo os aninhados de cada
# UnitData: sprite_frames, slots, learnset) do mesmo jeito que qualquer
# .tres de unidade em data/units/ já funciona — não tem nada de especial
# acontecendo aqui além de "SaveData é só mais um Resource".
func save_game(slot: int) -> void:
	var data := SaveData.new()
	data.player_name = player_name
	data.money = money
	data.badges = badges.duplicate()
	data.defeated_trainer_badges = defeated_trainer_badges.duplicate()
	data.vanished_trainers = vanished_trainers.duplicate()
	data.trainer_positions = trainer_positions.duplicate()
	data.trainer_facings = trainer_facings.duplicate()
	data.collected_loot = collected_loot.duplicate()
	data.flags = flags.duplicate()
	data.player_gender = player_gender
	data.roster = roster.duplicate()
	data.storage = storage.duplicate()
	data.giovanni_storage = giovanni_storage.duplicate()
	# inventory.keys() devolve um Array comum (não tipado) — Array[ItemData](...)
	# pareceria o jeito óbvio de "converter", mas isso é erro de sintaxe em
	# GDScript (o Parser lê "Array[ItemData]" como uma expressão e tenta
	# CHAMAR ela com "(...)", daí o erro "Cannot call on an expression").
	# O jeito certo de encher um Array JÁ tipado a partir de um Array comum
	# é Array.assign() — por isso inventory_items começa vazio (mas já
	# tipado, ver @export var inventory_items: Array[ItemData] em
	# save_data.gd) e assign() copia os elementos de inventory.keys() pra
	# dentro dele, validando o tipo de cada um.
	data.inventory_items.assign(inventory.keys())
	data.inventory_quantities = []
	for item in data.inventory_items:
		data.inventory_quantities.append(inventory[item])
	data.tool_shortcuts = tool_shortcuts.duplicate()
	data.current_area = current_area
	data.overworld_scene_path = overworld_scene_path
	# live_grid_pos/live_facing (não player_grid_pos/player_facing) porque
	# Save só é possível de dentro do overworld (game_menu.gd, aberto pelo
	# "A" — nunca em batalha), e são esses dois que test.gd mantém
	# sincronizados com a posição de VERDADE a cada passo (ver comentário
	# de GameState.live_grid_pos).
	data.player_grid_pos = live_grid_pos
	data.player_facing = live_facing
	data.last_heal_grid_pos = last_heal_grid_pos
	data.last_heal_facing = last_heal_facing
	current_save_slot = slot
	var err = ResourceSaver.save(data, _save_path(slot))
	if err != OK:
		push_error("Falha ao salvar slot %d: erro %d" % [slot, err])

# Substitui TODO o estado atual de GameState pelo do slot — chamado por
# save_slot_screen.gd (opção "Load Game"). Quem troca de cena pro overworld
# depois é sempre quem chamou isto (ver save_slot_screen.gd::
# _activate_selected_slot), não esta função, mesmo padrão de
# start_new_game() abaixo.
func load_game(slot: int) -> void:
	var data := peek_save(slot)
	if data == null:
		return
	player_name = data.player_name
	money = data.money
	badges = data.badges.duplicate()
	defeated_trainer_badges = data.defeated_trainer_badges.duplicate()
	vanished_trainers = data.vanished_trainers.duplicate()
	trainer_positions = data.trainer_positions.duplicate()
	trainer_facings = data.trainer_facings.duplicate()
	collected_loot = data.collected_loot.duplicate()
	flags = data.flags.duplicate()
	player_gender = data.player_gender
	roster = data.roster.duplicate()
	storage = data.storage.duplicate()
	giovanni_storage = data.giovanni_storage.duplicate()
	# Saves gravados ANTES do sistema de treinadores Rocket existir carregam
	# giovanni_storage vazio (campo novo, default [] em SaveData) — completa
	# até STORAGE_CAPACITY com null, mesma forma que _apply_fresh_state() já
	# garante pra jogo novo, senão os índices que pc_screen.gd usa pra essa
	# caixa (0..STORAGE_CAPACITY-1) ficariam fora dos limites do array.
	while giovanni_storage.size() < STORAGE_CAPACITY:
		giovanni_storage.append(null)
	inventory = {}
	for i in data.inventory_items.size():
		inventory[data.inventory_items[i]] = data.inventory_quantities[i]
	tool_shortcuts = data.tool_shortcuts.duplicate()
	current_area = data.current_area
	overworld_scene_path = data.overworld_scene_path
	has_saved_position = true
	player_grid_pos = data.player_grid_pos
	player_facing = data.player_facing
	live_grid_pos = data.player_grid_pos
	live_facing = data.player_facing
	last_heal_grid_pos = data.last_heal_grid_pos
	last_heal_facing = data.last_heal_facing
	current_save_slot = slot

# "New Game" num slot específico (ver save_slot_screen.gd/name_entry_screen.gd)
# — reseta tudo pro estado de jogo novo (ver _apply_fresh_state()) e já
# escreve o save na hora, com o nome escolhido, pra o slot deixar de
# aparecer como "Empty" mesmo antes do jogador dar Save pela primeira vez
# de propósito.
func start_new_game(slot: int, chosen_name: String) -> void:
	_apply_fresh_state()
	player_name = chosen_name
	current_save_slot = slot
	save_game(slot)
