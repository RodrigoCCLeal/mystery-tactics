extends Node2D

# Script da cena "World" — hoje é onde mora STARTINGTOWN (a primeira cidade
# do mundo, desenhada pelo usuário direto em world.tscn). É basicamente uma
# CÓPIA de test.gd (mesma mecânica: passo a passo, grama alta com encontro
# aleatório, menu A/Esc, atalhos de Tool, interação com NPC) — só que
# adaptada pra uma cena de overworld com TRÊS TileMapLayers (Ground/Objects/
# Top) em vez de um só (ver comentário grande abaixo sobre por que isso
# importa). Se um dia os dois scripts ficarem parecidos demais a ponto de
# incomodar, dá pra puxar a parte comum (menus, tools, interact) pra uma
# classe base — por enquanto, copiado é mais simples de entender/mexer.

# Test.tscn tem UM TileMapLayer só, então "onde ando" e "onde bate parede"
# são a mesma pergunta. Aqui em STARTINGTOWN, o usuário desenhou em TRÊS
# camadas separadas:
#   - TileMapLayerGround: chão andável, grama (bate encontro) e água
#     (não-andável por enquanto, "não dá pra atravessar ainda").
#   - TileMapLayerObjects: colisão + elementos interativos (árvores, casas,
#     placas...) — quando uma célula tem tile AQUI, ele manda: mesmo que o
#     Ground embaixo seja andável, um objeto em cima pode bloquear (ex: uma
#     árvore plantada em cima de grama).
#   - TileMapLayerTop: SEM colisão nenhuma — é só o "topo" de alguma coisa
#     (o telhado de uma casa, a copa de uma árvore) que o jogador precisa
#     passar POR BAIXO visualmente. Por isso ela fica de fora do grupo
#     "Actors" (que tem y_sort_enabled) E ganha z_index=1 (ver comentário
#     igual em TreeTopLayer no test.tscn antigo) — sempre desenhada por CIMA
#     do jogador, nunca compete de posição Y com ele.
@onready var tile_map_ground: TileMapLayer = $TileMapLayerGround
@onready var tile_map_objects: TileMapLayer = $TileMapLayerObjects

@onready var player: Node2D = $Actors/Player
@onready var area_notification: CanvasLayer = $AreaNotification

const GRASS_RUSTLE_SCENE: PackedScene = preload("res://scenes/effects/grass_rustle.tscn")
const GAME_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/game_menu.tscn")
const SYSTEM_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/system_menu.tscn")

const FACING_TO_DIR = {
	"down": Vector2i(0, 1),
	"up": Vector2i(0, -1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}

@export var encounter_area: EncounterArea

# ---------- Divisão de áreas (STARTINGTOWN <-> ROUTE 1) ----------
# Pedido do usuário: a linha (2,-14) -> (9,-14) separa as duas áreas. Hoje só
# existe UMA linha de fronteira, então a regra fica simples: y <=
# ROUTE1_BOUNDARY_Y. O X dos dois pontos só descreve
# ONDE fica o corredor de passagem em si — o resto daquela latitude
# provavelmente já é bloqueado por parede/penhasco (ver camada de Objetos),
# então checar só o Y já basta: não tem como cruzar a "linha" fora do
# corredor de qualquer jeito. Se um dia existir uma segunda fronteira em
# outra parte do mapa, essa checagem precisa virar uma lista de segmentos em
# vez de uma constante única.
@export var route1_area: EncounterArea
const ROUTE1_BOUNDARY_Y = -14

# Coordenada do tile de grama alta DENTRO do atlas do TileSet outside.tres
# (diferente do forest_tileset.tres usado em Test — cada folha de tiles tem
# sua própria grama num lugar diferente). O valor abaixo é só um PLACEHOLDER
# — ainda não sabemos qual célula do atlas é a grama de verdade em
# outside.tres. Pra descobrir: abra world.tscn, clique na camada
# TileMapLayerGround, abra o painel de tiles (embaixo) e clique no tile de
# grama alta que você pintou — o Godot mostra as coordenadas dele (algo tipo
# "(x, y)") no rodapé/tooltip do painel. Depois é só selecionar o node World
# no Inspector e digitar esse valor em "Grass Atlas Coords" — sem isso, o
# encontro aleatório na grama de STARTINGTOWN não vai disparar (ou vai
# disparar no tile errado).
@export var grass_atlas_coords: Vector2i = Vector2i(-1, -1)

const MIN_ENCOUNTER_STEPS = 5
const MAX_ENCOUNTER_STEPS = 15

var steps_until_encounter: int = 0

var active_menu: CanvasLayer = null

# Trava contra DUAS batalhas disparando ao mesmo tempo — ver comentário
# grande gêmeo em test.gd::_battle_starting (mesmo bug, mesma correção:
# grama alta + Trainer avistando no MESMO frame não podem trocar de cena os
# dois). Faltava isto aqui — só existia em test.gd, porque nenhum Trainer
# tinha sido testado em world.tscn até agora (ver is_battle_starting/
# start_trainer_battle logo abaixo, que também faltavam).
var _battle_starting: bool = false

# Lido por trainer.gd::_process() ANTES de sequer checar visão/avistar —
# mesmo comentário de test.gd::is_battle_starting.
func is_battle_starting() -> bool:
	return _battle_starting

# true só se a TileSet da camada de Objetos tiver a custom data layer
# "one_way_dir" — ver comentário grande gêmeo em house_interior.gd::_ready()
# pro motivo completo (TileData.get_custom_data() lança ERRO, não devolve
# vazio, quando a layer não existe na TileSet). Aqui em World a TileSet
# (assets/tiles/tilesets/OW/outside.tres) SEMPRE tem a layer hoje, mas o
# guard é o mesmo por precaução — se um dia a camada de Objetos apontar pra
# outra TileSet (ex: uma variante nova de terreno), isso evita o mesmo crash
# que aconteceu num interior.
var _objects_has_one_way_layer: bool = false

func _ready() -> void:
	player.tile_entered.connect(_on_player_tile_entered)
	_objects_has_one_way_layer = _tileset_has_custom_data(tile_map_objects.tile_set, "one_way_dir")
	_reset_encounter_counter()
	_restore_player_state()
	player.set_sunk_in_grass(_is_tall_grass(player.grid_pos))
	_update_current_area()
	_sync_live_position()

func _tileset_has_custom_data(tile_set: TileSet, layer_name: String) -> bool:
	if tile_set == null:
		return false
	for i in tile_set.get_custom_data_layers_count():
		if tile_set.get_custom_data_layer_name(i) == layer_name:
			return true
	return false

# Qual EncounterArea vale pra célula `cell` — só olha o Y (ver comentário
# grande em ROUTE1_BOUNDARY_Y acima sobre por quê).
func _area_for_position(cell: Vector2i) -> EncounterArea:
	if route1_area != null and cell.y <= ROUTE1_BOUNDARY_Y:
		return route1_area
	return encounter_area

# Chamado tanto na entrada da cena (_ready, com a posição já restaurada por
# _restore_player_state) quanto A CADA passo (ver _on_player_tile_entered) —
# é o segundo caso que faz a troca STARTINGTOWN <-> ROUTE 1 acontecer sozinha
# assim que o jogador atravessa a linha, nos dois sentidos (pedido do
# usuário: "If they cross the line backwards, they will return to starting
# town"). Só reseta GameState.current_area/mostra o aviso quando a área
# realmente MUDA (mesmo espírito do antigo _enter_area) — sem essa checagem,
# o aviso reapareceria a cada passo dentro da MESMA área.
func _update_current_area() -> void:
	var target_area = _area_for_position(player.grid_pos)
	if target_area == null:
		return
	GameState.current_area = target_area
	if target_area.area_name != GameState.last_notified_area_name:
		GameState.last_notified_area_name = target_area.area_name
		area_notification.show_area(target_area.area_name)

func _restore_player_state() -> void:
	if GameState.has_saved_position:
		player.teleport_to(GameState.player_grid_pos, GameState.player_facing)

func _on_player_tile_entered(cell: Vector2i) -> void:
	_sync_live_position()
	_update_current_area()

	# Porta/entrada (ver door.gd) manda ANTES de qualquer coisa.
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

# Porta abre (se tiver animação configurada) -> fade pra preto -> troca de
# cena -> fade clareia. Mesmo comentário de test.gd::use_door.
func use_door(door: Door) -> void:
	await door.play_open_animation()
	GameState.save_player_state(door.target_grid_pos, door.target_facing, door.target_scene_path)
	SceneTransition.change_scene_with_fade(door.target_scene_path)

func _sync_live_position() -> void:
	GameState.live_grid_pos = player.grid_pos
	GameState.live_facing = player.facing

func _spawn_grass_rustle(cell: Vector2i) -> void:
	var effect = GRASS_RUSTLE_SCENE.instantiate()
	add_child(effect)
	effect.position = tile_map_ground.map_to_local(cell)

func _is_tall_grass(cell: Vector2i) -> bool:
	return tile_map_ground.get_cell_atlas_coords(cell) == grass_atlas_coords

func _reset_encounter_counter() -> void:
	steps_until_encounter = randi_range(MIN_ENCOUNTER_STEPS, MAX_ENCOUNTER_STEPS)

func _start_encounter() -> void:
	if _battle_starting:
		return
	_battle_starting = true
	_reset_encounter_counter()
	# scene_path explícito — ver comentário gêmeo em test.gd::_start_encounter
	# sobre o bug que isso corrige (voltar da batalha pro Test em vez de
	# voltar pro World, se a batalha começou aqui em STARTINGTOWN).
	GameState.save_player_state(player.grid_pos, player.facing, "res://scenes/overworld/world.tscn")
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

# Ver comentário gêmeo em test.gd::trigger_wild_encounter — wrapper público
# de _start_encounter() pra objetos de fora (ex: LootBall) dispararem.
func trigger_wild_encounter() -> void:
	_start_encounter()

# Chamado por Trainer._begin_battle() (ver trainer.gd) — mesmo espírito do
# gêmeo em test.gd::start_trainer_battle, só com "res://scenes/overworld/
# world.tscn" como scene_path em vez de test.tscn (mesmo bug que
# _start_encounter acima já evita, ver comentário lá).
func start_trainer_battle(trainer: Node) -> void:
	if _battle_starting:
		return
	_battle_starting = true
	# Trainer.gd::_spot_player() pausa a árvore pra travar o jogador durante
	# o "!" + caixa de texto + perseguição — SceneTree.paused sobrevive a
	# change_scene_to_file() se ninguém desligar antes, então precisa
	# desligar aqui ou battle.tscn nasceria pausada por engano.
	get_tree().paused = false
	GameState.save_player_state(player.grid_pos, player.facing, "res://scenes/overworld/world.tscn")
	GameState.is_trainer_battle = true
	GameState.current_trainer_id = trainer.trainer_id
	GameState.current_trainer_team = trainer.get_active_team()
	GameState.current_trainer_prize = trainer.get_prize_money()
	GameState.current_trainer_iq = trainer.iq
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

# Delegado por player.gd::can_move_to(). Objects manda quando tem tile na
# célula (ex: uma árvore plantada em cima de grama do Ground) — só cai pro
# Ground se Objects não tiver NADA pintado ali. Célula sem tile em nenhuma
# das duas camadas conta como não-andável (mesmo critério de test.gd: fora
# do mapa = parede).
#
# move_dir (opcional, ZERO = "não sei/não importa a direção") é o que
# permite ladeira de mão única existir (ver custom data "one_way_dir" no
# TileSet outside.tres, aba Custom Data do editor — mesmo lugar/mesma
# técnica de "walkable", só que guardando uma String: "up"/"down"/"left"/
# "right" em vez de bool). A propriedade fica GRUDADA NO TILE (não numa
# célula ou retângulo separado à parte no código), então mover/repintar o
# desenho na camada de Objetos já carrega o comportamento junto — era
# exatamente o problema da 1ª versão disto (um retângulo declarado por fora,
# que ficava pra trás se o usuário movesse os tiles no editor). Pra repetir
# numa área nova, o usuário só precisa selecionar as MESMAS variantes de
# tile de novo (ou marcar "one_way_dir" em variantes novas no TileSet), sem
# precisar editar nenhum script.
#
# Chamador que não informa move_dir (ex: trainer.gd checando linha de
# visão/patrulha) trata qualquer tile de mão única como sólido em qualquer
# direção — nenhuma direção bate com ZERO, então required_dir != move_dir
# sempre bloqueia. Padrão mais seguro pra quem ainda não lida com o conceito.
func is_cell_walkable(cell: Vector2i, move_dir: Vector2i = Vector2i.ZERO) -> bool:
	var obj_data = tile_map_objects.get_cell_tile_data(cell)
	if obj_data != null:
		if _objects_has_one_way_layer:
			var one_way: String = obj_data.get_custom_data("one_way_dir")
			if one_way != "":
				return move_dir == FACING_TO_DIR.get(one_way, Vector2i.ZERO)
		return obj_data.get_custom_data("walkable")

	var ground_data = tile_map_ground.get_cell_tile_data(cell)
	if ground_data == null:
		return false
	return ground_data.get_custom_data("walkable")

# Usado por player.gd pra saber SE deve tocar a animação de pulo (ver
# HOP_DURATION/HOP_HEIGHT lá) — pergunta parecida com is_cell_walkable, mas
# SEM direção nenhuma envolvida (só "essa célula é ladeira?", não "posso
# entrar nela?"; a permissão em si já foi decidida antes, em can_move_to).
func is_one_way_tile(cell: Vector2i) -> bool:
	if not _objects_has_one_way_layer:
		return false
	var obj_data = tile_map_objects.get_cell_tile_data(cell)
	return obj_data != null and obj_data.get_custom_data("one_way_dir") != ""

# NÃO devolve a var "tile_map_ground" (onready) — mesmo motivo do comentário
# gêmeo em test.gd::get_ground_tile_map(): o Player (neto de World, via
# Actors) resolve o PRÓPRIO onready ANTES de World chegar no dele (Godot
# chama _ready() de baixo pra cima), então nesse instante tile_map_ground
# ainda seria null. $TileMapLayerGround busca o node de novo, na hora, o que
# funciona não importa a ordem.
func get_ground_tile_map() -> TileMapLayer:
	return $TileMapLayerGround

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_menu"):
		_open_game_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		_open_system_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm"):
		_try_interact()
		get_viewport().set_input_as_handled()
	else:
		for i in TOOL_SHORTCUT_ACTIONS.size():
			if event.is_action_pressed(TOOL_SHORTCUT_ACTIONS[i]):
				get_viewport().set_input_as_handled()
				_trigger_tool_shortcut(i)
				return

const TOOL_SHORTCUT_ACTIONS = [
	"action_slot_1", "action_slot_2", "action_slot_3", "action_slot_4",
]

func _trigger_tool_shortcut(index: int) -> void:
	if player.is_moving:
		return
	var item: ItemData = GameState.tool_shortcuts[index]
	if item != null:
		GameState.use_tool(item)

func _try_interact() -> void:
	if player.is_moving:
		return
	var dir = FACING_TO_DIR.get(player.facing, Vector2i.ZERO)
	var target_cell = player.grid_pos + dir
	var npc = _get_npc_at(target_cell)
	if npc != null:
		npc.face_towards(player.grid_pos)
		npc.interact()

func _get_npc_at(cell: Vector2i) -> Npc:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.grid_pos == cell:
			return npc
	return null

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

func _on_menu_closed() -> void:
	active_menu = null
	get_tree().paused = false
