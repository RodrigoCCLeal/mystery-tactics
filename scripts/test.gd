extends Node2D

# Encontros aleatórios: cada passo dado em cima de um tile de grama alta
# conta pra um contador regressivo sorteado (entre MIN/MAX_ENCOUNTER_STEPS)
# — quando ele chega a 0, a batalha começa. É o mesmo princípio dos jogos
# Pokémon clássicos (probabilidade por passo), só que expresso como "só sei
# depois de quantos passos" em vez de "checa uma chance % a cada passo" —
# mais fácil de prever/testar, e foi assim que o usuário pediu.

@onready var tile_map: TileMapLayer = $TileMapLayer
# Player (e qualquer Npc, ver npc.gd) mora dentro de "Actors" (Node2D com
# y_sort_enabled = true) em vez de direto em Test — é isso que resolve o
# personagem "atravessando por baixo" de um NPC (ou vice-versa): dentro de um
# nó com y_sort_enabled, o Godot desenha os filhos ordenados pela posição Y
# de cada um (quem está mais embaixo na tela desenha por CIMA), em vez da
# ordem fixa em que aparecem na árvore. TileMapLayer/TreeTopLayer ficam DE
# FORA desse grupo de propósito — o chão deve continuar sempre atrás de
# tudo, e o topo das árvores sempre na frente (z_index=1), não faz sentido
# nenhum deles competirem por posição Y com os personagens.
@onready var player: Node2D = $Actors/Player
@onready var area_notification: CanvasLayer = $AreaNotification

const GRASS_RUSTLE_SCENE: PackedScene = preload("res://scenes/effects/grass_rustle.tscn")
const GAME_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/game_menu.tscn")
const SYSTEM_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/system_menu.tscn")

# Direção "facing" (string, ver Player.facing) -> vetor de célula — usado só
# por _try_interact() abaixo pra achar a célula bem na frente do jogador.
const FACING_TO_DIR = {
	"down": Vector2i(0, 1),
	"up": Vector2i(0, -1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}

# Qual área (nome + tabela de encontros selvagens, ver encounter_area.gd/
# encounter_group.gd) vale NESTA cena de overworld — configurável no
# Inspector pra essa instância de Test, assim uma área diferente no futuro
# (outra cena, ou uma sub-região desta mesma cena) pode apontar pra outro
# .tres de área sem mexer em código nenhum aqui. Espelhado em
# GameState.current_area assim que a cena carrega (ver _enter_area), que é
# de onde battle.gd::spawn_enemies() de fato lê depois.
@export var encounter_area: EncounterArea

# Coordenada do tile de grama alta DENTRO do atlas do tileset (não é uma
# célula do mapa — é "qual peça da folha de tiles é essa", a mesma peça
# pode estar pintada em várias células do mapa).
const GRASS_ATLAS_COORDS = Vector2i(7, 5)

const MIN_ENCOUNTER_STEPS = 5
const MAX_ENCOUNTER_STEPS = 15

var steps_until_encounter: int = 0

# Qual dos 2 menus (ver game_menu.gd/system_menu.gd) está aberto agora, ou
# null se nenhum — impede abrir um POR CIMA do outro (ex: apertar "A" já
# com o menu de Esc aberto). Os dois pausam a árvore igual (ver
# _open_game_menu/_open_system_menu), então só um de cada vez faz sentido.
var active_menu: CanvasLayer = null

# Trava contra DUAS batalhas disparando ao mesmo tempo — ex: correr por
# grama alta bem atrás de um Trainer que te avista naquele exato instante
# (grama alta -> _start_encounter, Trainer -> start_trainer_battle, os dois
# no MESMO frame: Player._process roda antes de Trainer._process, ver ordem
# dos nodes em Actors). Sem essa trava, os dois chamavam change_scene_to_file()
# — o primeiro (deferred) destruía a cena Test inteira, Trainer incluso,
# enquanto ele ainda podia estar no meio de uma sequência assíncrona (ver
# trainer.gd::_spot_player() esperando a animação do "!" com await) — a
# retomada daquele await num node já destruído é o que "quebrava o jogo".
# Ambos os métodos abaixo checam/ligam isto ANTES de fazer qualquer coisa.
var _battle_starting: bool = false

# Lido por trainer.gd::_process() ANTES de sequer checar visão/avistar — se
# uma batalha selvagem já está a caminho (grama alta, mesmo frame, ver
# comentário de _battle_starting acima), o Trainer nem começa a própria
# sequência (senão pausaria a árvore e ia esperar uma animação numa cena
# que está prestes a ser destruída de qualquer jeito).
func is_battle_starting() -> bool:
	return _battle_starting

func _ready() -> void:
	player.tile_entered.connect(_on_player_tile_entered)
	_reset_encounter_counter()
	_restore_player_state()
	# teleport_to() (usado tanto no spawn padrão quanto ao restaurar do
	# GameState) NÃO emite tile_entered — de propósito, pra não contar como
	# "passo" pro contador de encontro — mas isso também significa que o
	# efeito de afundar na grama não se reajustava sozinho ao voltar da
	# batalha (o shader ficava com o "sunk" de antes da troca de cena, sem
	# checar se a célula restaurada é grama de verdade). Resolve aqui, uma
	# vez, olhando a célula final direto.
	player.set_sunk_in_grass(_is_tall_grass(player.grid_pos))
	_enter_area()
	_sync_live_position()

# "Entrar" nesta área do overworld: espelha encounter_area em
# GameState.current_area (pra battle.gd::spawn_enemies() ler depois) e
# mostra a notificação de nome (ver area_notification.gd) SÓ se a área
# realmente mudou desde a última vez — comparando por nome (ver
# GameState.last_notified_area_name) em vez de sempre mostrar, senão
# reapareceria toda vez que _ready() roda de novo (ex: voltando de uma
# batalha pro mesmo mapa), o que não é "entrar numa área nova" de verdade.
func _enter_area() -> void:
	if encounter_area == null:
		return
	GameState.current_area = encounter_area
	if encounter_area.area_name != GameState.last_notified_area_name:
		GameState.last_notified_area_name = encounter_area.area_name
		area_notification.show_area(encounter_area.area_name)

# Se GameState tem uma posição salva (viemos de uma troca de cena, ex:
# voltando de uma batalha), reposiciona o Player ali em vez de deixar ele no
# spawn padrão (grid_pos = ZERO, definido em Player._ready()).
func _restore_player_state() -> void:
	if GameState.has_saved_position:
		player.teleport_to(GameState.player_grid_pos, GameState.player_facing)

func _on_player_tile_entered(cell: Vector2i) -> void:
	_sync_live_position()

	# Porta/entrada (ver door.gd) manda ANTES de qualquer coisa — andar em
	# cima da célula troca de cena na hora, não faz sentido checar grama
	# alta ou continuar o passo normalmente depois disso.
	var door = get_door_at(cell)
	if door != null:
		use_door(door)
		return

	var in_grass = _is_tall_grass(cell)
	player.set_sunk_in_grass(in_grass)

	if not in_grass:
		return

	_spawn_grass_rustle(cell)

	steps_until_encounter -= 1
	if steps_until_encounter <= 0:
		_start_encounter()

# Mesma varredura de _get_npc_at, só que no grupo "door" (ver door.gd).
func get_door_at(cell: Vector2i) -> Door:
	for door in get_tree().get_nodes_in_group("door"):
		if door.grid_pos == cell:
			return door
	return null

# Salva onde o jogador deve aparecer NA CENA DE DESTINO (ver
# Door.target_grid_pos/target_facing) e troca de cena — mesma função
# (GameState.save_player_state) que o caminho overworld -> batalha já usa,
# só que aqui o "scene_path" é o da porta em vez do padrão (overworld); é
# por isso que save_player_state aceita esse terceiro parâmetro.
#
# SceneTransition (autoload, ver scripts/scene_transition.gd) faz um fade
# pra preto ANTES de trocar e clareia DEPOIS. door.play_open_animation()
# (se a porta tiver door_sheet configurado — ver door.gd) toca ANTES disso,
# então a sequência fica: porta abre -> tela escurece -> troca de cena ->
# tela clareia. "await" aqui porque a ORDEM importa (não queremos escurecer
# a tela antes da porta terminar de abrir) — mas isso não trava o resto do
# jogo: _on_player_tile_entered já rodou o resto do que precisava antes de
# chamar isso.
func use_door(door: Door) -> void:
	await door.play_open_animation()
	GameState.save_player_state(door.target_grid_pos, door.target_facing, door.target_scene_path)
	SceneTransition.change_scene_with_fade(door.target_scene_path)

# Mantém GameState.live_grid_pos/live_facing sempre em dia com a posição de
# VERDADE do jogador nesta cena — chamado tanto no _ready() (posição
# inicial/restaurada, que não passa por tile_entered) quanto a cada passo
# (tile_entered dispara pra QUALQUER tile, grama ou não). Ver comentário de
# GameState.live_grid_pos pra saber por que isso precisa existir separado
# de GameState.player_grid_pos (que só é atualizado no instante de entrar
# numa batalha, não a cada passo).
func _sync_live_position() -> void:
	GameState.live_grid_pos = player.grid_pos
	GameState.live_facing = player.facing

# Instancia o efeito de folhas mexendo na célula onde o personagem acabou
# de pisar. Sem efeito visual nenhum enquanto grass_rustle_frames.tres não
# tiver quadros de verdade (ver comentário em grass_rustle.gd) — mas já
# fica plugado, então basta preencher os quadros depois pra funcionar sem
# mexer em mais nada aqui.
func _spawn_grass_rustle(cell: Vector2i) -> void:
	var effect = GRASS_RUSTLE_SCENE.instantiate()
	add_child(effect)
	effect.position = tile_map.map_to_local(cell)

func _is_tall_grass(cell: Vector2i) -> bool:
	return tile_map.get_cell_atlas_coords(cell) == GRASS_ATLAS_COORDS

# Delegado por player.gd::can_move_to() — só quem hospeda o Player (Test ou
# World, ver world.gd) sabe quantos TileMapLayers existem nesta cena e como
# lê-los. Aqui é só UM (tile_map), então a checagem é direta; world.gd tem
# a mesma função combinando Ground+Objects (Objetos manda quando as duas
# camadas têm tile na mesma célula).
# move_dir (opcional) existe só pra manter a MESMA assinatura de
# world.gd::is_cell_walkable (ver comentário grande lá sobre ladeira de mão
# única) — Test ainda não tem tile nenhum marcado com "one_way_dir", então
# o parâmetro fica sem uso aqui por enquanto; sem ele, player.gd::can_move_to
# não conseguiria
# chamar world.is_cell_walkable(cell, dir) de um jeito só, igual pras três
# cenas de overworld (Test/World/HouseInterior).
func is_cell_walkable(cell: Vector2i, move_dir: Vector2i = Vector2i.ZERO) -> bool:
	var tile_data = tile_map.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_custom_data("walkable")

# Mesma MVP-parity de is_cell_walkable acima: Test só tem UMA camada, sem
# nenhum tile "one_way_dir" pintado ainda — sempre false por enquanto, só
# existe pra player.gd::_try_start_move() poder chamar
# world.is_one_way_tile() sem se importar se o host é Test, World ou
# HouseInterior (ver world.gd::is_one_way_tile pra a versão que faz alguma
# coisa de verdade).
func is_one_way_tile(cell: Vector2i) -> bool:
	return false

# Idem — player.gd usa isso só pra conta de posição (map_to_local,
# tile_set.tile_size etc.), nunca pra decidir colisão (isso é sempre
# is_cell_walkable acima).
#
# NÃO devolve a var "tile_map" (onready) aqui — ela só fica preenchida
# quando o PRÓPRIO Test roda seu _ready(), e isso acontece DEPOIS do Player
# (filho de Actors, que é filho de Test): Godot chama _ready() de baixo pra
# cima na árvore, então quando o onready do Player tenta resolver o tile_map
# dele (ver player.gd) chamando esta função, o Test ainda nem processou o
# próprio onready — "tile_map" ainda seria null nesse instante. $TileMapLayer
# aqui busca o node DE NOVO, na hora, o que funciona a qualquer momento (o
# node já existe na árvore desde que a cena foi montada, só o _ready() dele
# é que roda depois) — foi exatamente esse null que causou o erro
# "Invalid access to property or key 'tile_set' on a base object of type
# 'Nil'" em player.gd::_align_sprite_to_tile().
func get_ground_tile_map() -> TileMapLayer:
	return $TileMapLayer

func _reset_encounter_counter() -> void:
	steps_until_encounter = randi_range(MIN_ENCOUNTER_STEPS, MAX_ENCOUNTER_STEPS)

# Guarda onde o personagem está (pra devolver ele aqui quando a batalha
# acabar — GameState sobrevive à troca de cena) e troca pra batalha.
# change_scene_to_file() descarta o Test inteiro. O caminho de volta
# (batalha -> overworld) ainda não existe — batle.gd não tem um fim de
# batalha implementado ainda (vitória/derrota/fuga); quando tiver, é lá que
# vamos chamar change_scene_to_file(GameState.overworld_scene_path).
func _start_encounter() -> void:
	if _battle_starting:
		return
	_battle_starting = true
	_reset_encounter_counter()
	# Terceiro parâmetro (scene_path) explícito agora — o padrão da função
	# é "res://scenes/overworld/test.tscn", que ATÉ FUNCIONA aqui só por coincidência
	# de sermos literalmente o Test. Deixar implícito escondia um bug real:
	# world.gd tinha essa MESMA linha, e ficaria voltando o jogador pro
	# Test depois de uma batalha começada em STARTINGTOWN em vez de voltar
	# pro World. Ver correção equivalente em world.gd/house_interior.gd.
	GameState.save_player_state(player.grid_pos, player.facing, "res://scenes/overworld/test.tscn")
	# GameState.current_area já foi setado em _enter_area() (rodou no
	# _ready() desta cena) — não precisa repetir aqui.
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

# Wrapper PÚBLICO de _start_encounter() — existe só pra objetos de fora
# (ex: loot_ball.gd, recompensa "Battle") poderem disparar um encontro
# selvagem sem precisar chamar um método com "_" na frente (convenção do
# projeto: "_" é implementação interna, o resto do jogo fala só com a API
# pública do host, mesmo espírito de start_trainer_battle/is_battle_starting/
# get_ground_tile_map). Mesma lógica, mesmo guard contra chamada dupla.
func trigger_wild_encounter() -> void:
	_start_encounter()

# Chamado por Trainer._begin_battle() (ver trainer.gd) — mesmo espírito de
# _start_encounter() acima, só que pra uma batalha CONTRA TRAINER em vez de
# selvagem: salva a posição do jogador do mesmo jeito, mas em vez de deixar
# battle.gd ler GameState.current_area, copia pra GameState os 4 campos que
# trainer.gd::get_active_team()/get_prize_money() já resolveram (tier certo
# pro número de badges, prêmio já calculado) — precisa ser copiado ANTES de
# trocar de cena porque change_scene_to_file() vai destruir este Trainer
# junto com o resto de Test, não dá pra battle.gd ler o node depois.
func start_trainer_battle(trainer: Node) -> void:
	if _battle_starting:
		return
	_battle_starting = true
	# Trainer.gd::_spot_player() pausa a árvore (get_tree().paused = true)
	# pra travar o jogador durante o "!" + caixa de texto + perseguição (ver
	# comentário lá) — SceneTree.paused é do TREE, não da cena, então
	# sobrevive a change_scene_to_file() se ninguém desligar antes; sem isso
	# battle.tscn nasceria pausada por engano (HUD/input de batalha
	# travados, já que os nodes de lá não usam PROCESS_MODE_ALWAYS).
	get_tree().paused = false
	GameState.save_player_state(player.grid_pos, player.facing, "res://scenes/overworld/test.tscn")
	GameState.is_trainer_battle = true
	GameState.current_trainer_id = trainer.trainer_id
	GameState.current_trainer_team = trainer.get_active_team()
	GameState.current_trainer_prize = trainer.get_prize_money()
	GameState.current_trainer_iq = trainer.iq
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

# "A" abre o menu do JOGO (Pokémon/Computador/Bag/Save, ver game_menu.gd);
# Esc abre o menu do SISTEMA (Configurações/Exit, ver system_menu.gd) — dois
# menus separados agora (era um só, pause_menu.gd, removido). Os dois
# pausam a árvore (get_tree().paused = true) e desligam de novo só quando
# fecham (ver _on_menu_closed) — process_mode padrão (PROCESS_MODE_INHERIT)
# faz qualquer node comum parar de rodar _process/_input enquanto a árvore
# está pausada, sem precisar desligar o Player manualmente; os dois menus
# em si rodam com PROCESS_MODE_ALWAYS (ver game_menu.gd/system_menu.gd),
# então continuam recebendo input normalmente mesmo com o jogo pausado.
#
# 1/2/3/4 (action_slot_1..4) usam um Tool registrado direto, sem abrir a Bag
# (ver GameState.tool_shortcuts/register_tool) — as MESMAS actions que
# battle.gd usa pros slots de ataque 1-6, só que aqui (overworld) só as 4
# primeiras têm sentido, e o efeito é completamente diferente (usar um Tool,
# não uma ação de batalha). Não há conflito: Test e Battle nunca rodam ao
# mesmo tempo (uma troca a outra via change_scene_to_file), cada script só
# escuta essas actions na sua própria cena.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_menu"):
		get_viewport().set_input_as_handled()
		_open_game_menu()
	elif event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_open_system_menu()
	elif event.is_action_pressed("confirm"):
		# set_input_as_handled() ANTES de _try_interact() agora — interagir
		# com um Trainer (ver trainer.gd::interact()) pode trocar de cena na
		# HORA (change_scene_to_file, síncrono dentro desta mesma chamada),
		# e depois disso get_viewport() já não resolve mais (Test não está
		# mais na árvore) — chamar set_input_as_handled() DEPOIS crashava
		# com "Cannot call method 'set_input_as_handled' on a null value".
		# Falar com Nurse/Merchant/Baldo continua funcionando igual (eles só
		# pausam a árvore, nunca trocam de cena direto em interact()).
		get_viewport().set_input_as_handled()
		_try_interact()
	else:
		for i in TOOL_SHORTCUT_ACTIONS.size():
			if event.is_action_pressed(TOOL_SHORTCUT_ACTIONS[i]):
				get_viewport().set_input_as_handled()
				_trigger_tool_shortcut(i)
				return

# Igual ACTION_SLOT_ACTIONS de battle.gd, mas só os 4 primeiros — só existem
# 4 slots de Tool (GameState.TOOL_SHORTCUT_COUNT), diferente dos 6 slots de
# ataque em batalha.
const TOOL_SHORTCUT_ACTIONS = [
	"action_slot_1", "action_slot_2", "action_slot_3", "action_slot_4",
]

# Usa o Tool registrado no atalho `index`, se houver (slot vazio = não faz
# nada). Mesmo efeito de abrir a Bag e escolher "Use" num item Tool (ver
# item_list_screen.gd), só que sem abrir menu nenhum — é exatamente esse o
# ponto do atalho. Bloqueado enquanto o personagem está no meio de um passo
# (is_moving) pelo mesmo motivo de _try_interact(): evita usar a Bicycle e
# trocar de sprite/velocidade no meio de uma animação de passo já em curso.
func _trigger_tool_shortcut(index: int) -> void:
	if player.is_moving:
		return
	var item: ItemData = GameState.tool_shortcuts[index]
	if item != null:
		GameState.use_tool(item)

# X de frente pra um NPC (ver npc.gd/nurse.gd) fala com ele. Só olha a célula
# EXATA na frente do jogador (mesma direção de player.facing, não o alcance
# nenhum) — sem isso o jogador podia "gritar" com um NPC de longe. Enquanto
# o jogador está no meio de um passo (is_moving), não tenta interagir: a
# célula da frente pode não corresponder mais à direção que ele estava
# olhando quando o passo começou.
func _try_interact() -> void:
	if player.is_moving:
		return
	var dir = FACING_TO_DIR.get(player.facing, Vector2i.ZERO)
	var target_cell = player.grid_pos + dir
	var npc = _get_npc_at(target_cell)
	if npc != null:
		# Vira o NPC pra encarar o jogador ANTES de interagir — vale pra
		# qualquer NPC (ver npc.gd::face_towards), não só a Nurse, por isso
		# fica aqui em vez de em cada interact() sobrescrito.
		npc.face_towards(player.grid_pos)
		npc.interact()

# Percorre o grupo "npc" (todo Npc se registra sozinho em npc.gd::_ready,
# via add_to_group) procurando quem ocupa `cell`. Sem física nenhuma (Area2D/
# CollisionShape2D) — mesmo espírito 100% grid do resto do overworld (ver
# player.gd::can_move_to, que usa isso pra bloquear o passo em cima de um
# NPC, e battle.gd::get_unit_at pro equivalente em batalha).
func _get_npc_at(cell: Vector2i) -> Npc:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.grid_pos == cell:
			return npc
	return null

# Usado por player.gd::can_move_to — impede o jogador de andar POR CIMA de
# um NPC (sem isso, ele simplesmente atravessaria, já que NPCs não têm
# colisão física nenhuma).
func has_npc_at(cell: Vector2i) -> bool:
	return _get_npc_at(cell) != null

func _open_game_menu() -> void:
	if active_menu != null:
		return
	var menu = GAME_MENU_SCENE.instantiate()
	add_child(menu)
	active_menu = menu
	menu.closed.connect(_on_menu_closed)
	get_tree().paused = true

func _open_system_menu() -> void:
	if active_menu != null:
		return
	var menu = SYSTEM_MENU_SCENE.instantiate()
	add_child(menu)
	active_menu = menu
	menu.closed.connect(_on_menu_closed)
	get_tree().paused = true

# Fechar qualquer um dos dois menus (Z/Esc, ou "Save"/qualquer sub-menu
# terminando) chega aqui — quem despausa o jogo de verdade é aqui, escutando
# o sinal "closed". system_menu.gd::_on_exit_answered troca de cena direto
# em vez de passar por aqui quando o jogador confirma "Exit" (ver comentário
# lá), então este caminho só cobre "fechou sem sair do jogo".
func _on_menu_closed() -> void:
	active_menu = null
	get_tree().paused = false
