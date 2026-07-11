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
# world.gd::_restore_player_state / battle.gd::end_battle).

var has_saved_position: bool = false
var player_grid_pos: Vector2i = Vector2i.ZERO
var player_facing: String = "down"
var overworld_scene_path: String = "res://scenes/world.tscn"

func save_player_state(cell: Vector2i, facing: String, scene_path: String = "res://scenes/world.tscn") -> void:
	has_saved_position = true
	player_grid_pos = cell
	player_facing = facing
	overworld_scene_path = scene_path

# Posição "ao vivo" do jogador no overworld — world.gd mantém isso atualizado
# a CADA passo (ver world.gd::_sync_live_position), diferente de
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
# a Bag — o atalho de teclado no overworld (1/2/3/4, ver world.gd::
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
var roster: Array[UnitData] = [
	preload("res://data/units/0001.tres").duplicate(),
	preload("res://data/units/0004.tres").duplicate(),
	preload("res://data/units/0007.tres").duplicate(),
]

# ensure_initialized() só faz alguma coisa a primeira vez (current_hp ainda
# -1) — dá o nível/xp/HP inicial pra cada unidade do roster antes de
# qualquer tela (Party) ou batalha ler esses valores. O preenchimento de
# `storage` com null até STORAGE_CAPACITY é o que dá à reserva do PC seus
# slots vazios fixos (mesma ideia de `roster`, só que maior).
func _ready() -> void:
	for data in roster:
		if data != null:
			data.ensure_initialized(STARTING_LEVEL)
	# roster começa com só 3 elementos no literal acima (Charmander/Charmeleon/
	# Squirtle) — sem preencher até MAX_TEAM_SIZE com null (igual já fazíamos
	# com storage logo abaixo), swap_roster_slots/swap_active_with_storage
	# rejeitavam qualquer troca envolvendo os índices 3/4/5 (bounds check
	# "index >= roster.size()", com roster.size() == 3), o que fazia esses 3
	# slots "vazios" da tela do PC parecerem clicáveis mas nunca aceitarem
	# nada arrastado pra cima deles. Bug reportado pelo usuário: não dava pra
	# arrastar uma 4ª unidade da reserva pro time.
	while roster.size() < MAX_TEAM_SIZE:
		roster.append(null)
	while storage.size() < STORAGE_CAPACITY:
		storage.append(null)
	_seed_starting_inventory()

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
# live_facing, que world.gd mantém sempre atualizado com a posição de
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
]

# Em qual área do overworld o jogador está AGORA — world.gd seta isso (a
# partir do seu próprio @export var encounter_area) assim que a cena
# carrega (ver world.gd::_enter_area), e é o mesmo valor que sobrevive à
# troca de cena pra battle.tscn, onde battle.gd::spawn_enemies() lê daqui
# pra saber QUAIS unidades selvagens podem aparecer e com que peso (ver
# encounter_area.gd/encounter_group.gd). Um EncounterArea já carrega tanto o
# NOME da área (area_name, usado pela notificação de "você entrou em...")
# quanto sua tabela de encontros — as duas informações vivem juntas de
# propósito, não tem sentido uma área "ter" um nome sem ter (nem que vazia)
# uma lista de encontros, ou vice-versa.
#
# O valor default abaixo (a área inicial) é só uma rede de segurança pra
# spawn_enemies() nunca ficar sem tabela nenhuma — no fluxo normal, world.gd
# sempre sobrescreve isso ao carregar.
var current_area: EncounterArea = preload("res://data/areas/starting_area.tres")

# Nome da última área que já mostrou a notificação de entrada (ver
# area_notification.gd) — existe só pra world.gd saber se a área que está
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

func add_item(item: ItemData, amount: int = 1) -> void:
	inventory[item] = get_item_quantity(item) + amount

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
# alvo (clampado no HP máximo dela, calculado no nível atual) e consome 1
# unidade do inventário. Não faz nada se o jogador não tiver o item (defesa
# contra chamada indevida; a Bag só deveria oferecer "Use" quando
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
	target.current_hp = min(target.current_hp + item.heal_amount, hp_max)
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
