extends Node2D

# Script da cena "World" (Route 1) — ANTES disto, ARCHI/ROUTE 1/BARIAS
# moravam TODOS dentro da MESMA cena world.tscn/world.gd (um World gigante
# com três EncounterArea diferentes escolhidas por matemática de posição, ver
# _area_for_position no world.gd antigo). Pedido do usuário (2026-09-21,
# verbatim): "When trying to run the game on a friends laptop, the overworld
# map didn't load any tile, we need to cut down the 'overworld' map into
# smaller parts. Like doing 1 for archis, 1 for barias, 1 for route 1 etc.
# This may actually be beneficial for development aswell" — este arquivo é a
# cópia ROUTE 1 (a trilha entre Archis e Barias) do antigo world.gd, gêmea
# de world_archis.gd/world_barias.gd (mesma mecânica de sempre:
# passo a passo, grama alta com sprite selvagem, menu A/Esc, atalhos de
# Tool, interação com NPC — ver comentário grande igual em house_interior.gd
# sobre por que copiar em vez de puxar uma classe base comum).
#
# world.tscn/world.gd ORIGINAIS continuam existindo intocados (nunca
# apagamos nada, ver convenção do projeto) — só pararam de ser usados por
# qualquer porta/troca de cena NOVA a partir de agora. Uma save antiga que
# ainda aponte pra eles continua funcionando (o arquivo não sumiu), só não
# recebe mais nenhuma atualização de conteúdo.
#
# ---------- Como o mapa foi cortado ----------
# scripts/outputs/split_world.py (rodado uma vez só, fora do projeto) leu
# o world.tscn ORIGINAL e:
#   1. Decodificou as 3 TileMapLayer (Ground/Objects/Top) do formato binário
#      de verdade do Godot (header int16 + registros de 12 bytes: x,y,
#      source_id,atlas_x,atlas_y,alternative_tile) e separou as células por
#      região, usando a MESMA regra de fronteira que _area_for_position já
#      usava (BARIAS_BOUNDS por retângulo, senão y <= ROUTE1_BOUNDARY_Y =
#      Route 1, senão Archis).
#   2. IMPORTANTE: cada cena ganhou também uma FRANJA de 1 célula de
#      profundidade pra dentro do território vizinho (uma célula pertence à
#      cena se a região dela bater OU se algum vizinho ortogonal (cima/
#      baixo/esquerda/direita) bater) — sem isso, o jogador ficaria
#      "trancado" na borda: is_cell_walkable() exige tile pintado em alguma
#      camada, e sem essa franja a última fileira de Archis simplesmente não
#      teria arte nenhuma na cena vizinha logo depois dela, virando parede
#      invisível. Com a franja, o jogador anda normalmente até pisar de
#      verdade na primeira célula "estrangeira" — nesse instante
#      _check_area_transition() (ver abaixo) já dispara a troca de cena de
#      verdade, então a franja nunca chega a ser REALMENTE visível por mais
#      de um frame antes do fade-to-black cobrir a tela (mesmo efeito visual
#      de sempre, só que agora é uma troca de CENA em vez de só um rótulo).
#   3. Cada Actor (porta, NPC, LootBall, Merchant, Boss) foi pra a cena cuja
#      região bate com a posição dele (SEM franja aqui — um Actor pertence a
#      exatamente uma cena). O Player é a única exceção: uma cópia dele
#      existe em TODAS as 3 cenas (mesmo padrão que toda outra cena de
#      overworld/interior já segue — ver red_house_interior.tscn etc.), já
#      que GameState._restore_player_state() reposiciona ele de qualquer
#      jeito assim que a cena carrega.

@onready var tile_map_ground: TileMapLayer = $TileMapLayerGround
@onready var tile_map_objects: TileMapLayer = $TileMapLayerObjects

@onready var player: Node2D = $Actors/Player
@onready var area_notification: CanvasLayer = $AreaNotification
@onready var canvas_modulate: CanvasModulate = $CanvasModulate

const GRASS_RUSTLE_SCENE: PackedScene = preload("res://scenes/effects/grass_rustle.tscn")
const WILD_SPRITE_SCENE: PackedScene = preload("res://scenes/npc/wild_sprite.tscn")
const GAME_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/game_menu.tscn")
const SYSTEM_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/system_menu.tscn")
const SONG_MENU_SCENE: PackedScene = preload("res://scenes/ui/popups/song_menu.tscn")

const FACING_TO_DIR = {
	"down": Vector2i(0, 1),
	"up": Vector2i(0, -1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}

# EncounterArea FIXA desta cena — cada uma das 3 cenas cortadas tem UMA só
# agora (diferente do world.gd antigo, que precisava escolher entre 3 por
# posição). Ver data/areas/archi_area.tres.
@export var encounter_area: EncounterArea

# ---------- Fronteiras entre cenas (mesma matemática de sempre) ----------
# Constantes IDÊNTICAS nas 3 cenas (world_archis.gd/world_route1.gd/
# world_barias.gd) de propósito — cada uma precisa saber reconhecer as
# OUTRAS duas fronteiras, não só a própria, pra decidir pra onde mandar o
# jogador (ver _scene_path_for_position). Mesma filosofia de duplicação que
# o projeto já segue (world.gd/house_interior.gd sempre foram cópias
# paralelas, não uma classe base) — copiado é mais fácil de entender e
# mexer sem quebrar as outras duas cenas sem querer.
const ROUTE1_BOUNDARY_Y = -14
const BARIAS_BOUNDS = Rect2i(Vector2i(-2, -57), Vector2i(28, 21))
const ARCHIS_SCENE_PATH = "res://scenes/overworld/world_archis.tscn"
const ROUTE1_SCENE_PATH = "res://scenes/overworld/world_route1.tscn"
const BARIAS_SCENE_PATH = "res://scenes/overworld/world_barias.tscn"

@export var grass_atlas_coords: Vector2i = Vector2i(-1, -1)

const MIN_ENCOUNTER_STEPS = 5
const MAX_ENCOUNTER_STEPS = 15

const MAX_UNITS_PER_GRASS_GROUP = 6
const GRASS_GROUP_REFRESH_INTERVAL = 5.0

var steps_until_water_encounter: int = 0
var _grass_patches: Array[Array] = []

var active_menu: CanvasLayer = null
var _battle_starting: bool = false

func is_battle_starting() -> bool:
	return _battle_starting

var _objects_has_one_way_layer: bool = false
var _ground_has_water_layer: bool = false
var _objects_has_water_layer: bool = false

func _ready() -> void:
	player.tile_entered.connect(_on_player_tile_entered)
	_objects_has_one_way_layer = _tileset_has_custom_data(tile_map_objects.tile_set, "one_way_dir")
	_ground_has_water_layer = _tileset_has_custom_data(tile_map_ground.tile_set, "water")
	_objects_has_water_layer = _tileset_has_custom_data(tile_map_objects.tile_set, "water")
	_reset_water_encounter_counter()
	_compute_grass_patches()
	_refresh_all_grass_patches()
	_start_grass_refresh_timer()
	_restore_player_state()
	player.set_sunk_in_grass(_is_tall_grass(player.grid_pos))
	_setup_area()
	_sync_live_position()
	canvas_modulate.color = GameState.get_time_of_day_mask_color()

func _process(_delta: float) -> void:
	canvas_modulate.color = GameState.get_time_of_day_mask_color()

func _tileset_has_custom_data(tile_set: TileSet, layer_name: String) -> bool:
	if tile_set == null:
		return false
	for i in tile_set.get_custom_data_layers_count():
		if tile_set.get_custom_data_layer_name(i) == layer_name:
			return true
	return false

# Qual das 3 cenas "dona" a célula `cell` — Barias primeiro (retângulo
# fechado), depois a linha Archis/Route 1 (só olha o Y). Mesma regra de
# sempre (ver antigo world.gd::_area_for_position), só que agora devolve um
# CAMINHO DE CENA em vez de uma EncounterArea — usado só pra decidir se
# _on_player_tile_entered precisa trocar de cena ou não.
func _scene_path_for_position(cell: Vector2i) -> String:
	if BARIAS_BOUNDS.has_point(cell):
		return BARIAS_SCENE_PATH
	if cell.y <= ROUTE1_BOUNDARY_Y:
		return ROUTE1_SCENE_PATH
	return ARCHIS_SCENE_PATH

# Chamado só em _ready() agora (uma vez por carregamento de cena) — antes
# (world.gd antigo) isso rodava A CADA passo porque a área podia mudar SEM
# trocar de cena; agora que cada cena já É uma área fixa, só precisa
# acontecer quando a cena nasce. O aviso "entrando em X" só aparece se a
# área realmente mudou desde a última vez (mesma checagem contra
# GameState.last_notified_area_name de sempre).
func _setup_area() -> void:
	GameState.current_area = encounter_area
	if encounter_area != null and encounter_area.area_name != GameState.last_notified_area_name:
		GameState.last_notified_area_name = encounter_area.area_name
		area_notification.show_area(encounter_area.area_name)

func _restore_player_state() -> void:
	if GameState.has_saved_position:
		player.teleport_to(GameState.player_grid_pos, GameState.player_facing)

func _on_player_tile_entered(cell: Vector2i) -> void:
	_sync_live_position()

	# Fronteira de cena — substitui o antigo _update_current_area() (que só
	# trocava um rótulo dentro da MESMA cena). Agora, sair do território
	# desta cena precisa de uma troca de cena de verdade (ver comentário
	# grande no topo do arquivo sobre a franja de 1 célula que torna isso
	# possível sem virar parede invisível).
	var target_scene = _scene_path_for_position(cell)
	if target_scene != ROUTE1_SCENE_PATH:
		_cross_into(cell, target_scene)
		return

	var door = get_door_at(cell)
	if door != null:
		use_door(door)
		return

	if GameState.is_surfing and is_cell_water(cell):
		steps_until_water_encounter -= 1
		if steps_until_water_encounter <= 0 and GameState.current_area != null and GameState.current_area.has_source("Water"):
			_start_encounter("Water")
		return

	var sprite = get_wild_sprite_at(cell)
	if sprite != null:
		_trigger_wild_sprite_encounter(sprite)
		return

	var in_grass = _is_tall_grass(cell)
	player.set_sunk_in_grass(in_grass)

	if not in_grass:
		return

	_spawn_grass_rustle(cell)

func get_door_at(cell: Vector2i) -> Door:
	for door in get_tree().get_nodes_in_group("door"):
		if door.grid_pos == cell:
			return door
	return null

func use_door(door: Door) -> void:
	await door.play_open_animation()
	GameState.save_player_state(door.target_grid_pos, door.target_facing, door.target_scene_path)
	SceneTransition.change_scene_with_fade(door.target_scene_path)

# Troca de cena "sem porta" (fronteira invisível entre Archis/Route 1/
# Barias) — mesmo mecanismo de use_door() (save_player_state + fade), só
# que o destino É a própria célula que o jogador acabou de pisar (as 3
# cenas compartilham o MESMO sistema de coordenadas de grid, nunca
# renumeramos nada no corte — ver split_world.py), não um target_grid_pos
# fixo de porta. facing continua o mesmo que o jogador já tinha (só
# atravessou uma linha andando, não "entrou" em lugar nenhum).
func _cross_into(cell: Vector2i, target_scene: String) -> void:
	GameState.save_player_state(cell, player.facing, target_scene)
	SceneTransition.change_scene_with_fade(target_scene)

func _sync_live_position() -> void:
	GameState.live_grid_pos = player.grid_pos
	GameState.live_facing = player.facing

func _spawn_grass_rustle(cell: Vector2i) -> void:
	var effect = GRASS_RUSTLE_SCENE.instantiate()
	add_child(effect)
	effect.position = tile_map_ground.map_to_local(cell)

func _is_tall_grass(cell: Vector2i) -> bool:
	return tile_map_ground.get_cell_atlas_coords(cell) == grass_atlas_coords

func _reset_water_encounter_counter() -> void:
	steps_until_water_encounter = randi_range(MIN_ENCOUNTER_STEPS, MAX_ENCOUNTER_STEPS)

func _compute_grass_patches() -> void:
	var visited: Dictionary = {}
	_grass_patches.clear()
	for cell in tile_map_ground.get_used_cells():
		if visited.has(cell) or not _is_tall_grass(cell):
			continue
		var patch := _get_connected_grass_patch(cell)
		for c in patch:
			visited[c] = true
		_grass_patches.append(patch)

func _refresh_all_grass_patches() -> void:
	for patch in _grass_patches:
		_refresh_grass_patch(patch)

# Igual ao world.gd antigo, só que agora usa encounter_area DIRETO (só
# existe uma área por cena, não precisa mais perguntar "de quem é esse
# patch" — todo patch desta cena é sempre da mesma área).
func _refresh_grass_patch(patch: Array[Vector2i]) -> void:
	for sprite in _get_wild_sprites_in_patch(patch):
		sprite.queue_free()
	if patch.is_empty():
		return
	if encounter_area == null:
		return
	var eligible = encounter_area.get_eligible_wild_spawn_entries()
	if eligible.is_empty():
		return
	var max_units = _max_units_for_patch(patch)
	var shuffled_cells: Array[Vector2i] = patch.duplicate()
	shuffled_cells.shuffle()
	var spawned := 0
	for cell in shuffled_cells:
		if spawned >= max_units:
			break
		var shuffled_entries := eligible.duplicate()
		shuffled_entries.shuffle()
		for entry in shuffled_entries:
			if randf() < entry.spawn_chance:
				_spawn_wild_sprite(entry, cell)
				spawned += 1
				break

func _max_units_for_patch(patch: Array[Vector2i]) -> int:
	return min(MAX_UNITS_PER_GRASS_GROUP, 1 + patch.size() / 10)

func _spawn_wild_sprite(entry: WildSpawnEntry, cell: Vector2i) -> void:
	var sprite: WildSprite = WILD_SPRITE_SCENE.instantiate()
	$Actors.add_child(sprite)
	sprite.setup(entry.species, entry.level, cell, tile_map_ground)

func _start_grass_refresh_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = GRASS_GROUP_REFRESH_INTERVAL
	timer.one_shot = false
	timer.timeout.connect(_refresh_all_grass_patches)
	add_child(timer)
	timer.start()

func get_wild_sprite_at(cell: Vector2i) -> WildSprite:
	for sprite in get_tree().get_nodes_in_group("wild_sprite"):
		if sprite.grid_pos == cell:
			return sprite
	return null

func _get_connected_grass_patch(start: Vector2i) -> Array[Vector2i]:
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [start]
	var patch: Array[Vector2i] = []
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if visited.has(cell):
			continue
		visited[cell] = true
		if not _is_tall_grass(cell):
			continue
		patch.append(cell)
		stack.append(cell + Vector2i(1, 0))
		stack.append(cell + Vector2i(-1, 0))
		stack.append(cell + Vector2i(0, 1))
		stack.append(cell + Vector2i(0, -1))
	return patch

func _get_wild_sprites_in_patch(patch: Array[Vector2i]) -> Array[WildSprite]:
	var patch_set: Dictionary = {}
	for cell in patch:
		patch_set[cell] = true
	var result: Array[WildSprite] = []
	for sprite in get_tree().get_nodes_in_group("wild_sprite"):
		if patch_set.has(sprite.grid_pos):
			result.append(sprite)
	return result

func _trigger_wild_sprite_encounter(touched_sprite: WildSprite) -> void:
	if _battle_starting:
		return
	var patch = _get_connected_grass_patch(touched_sprite.grid_pos)
	var sprites = _get_wild_sprites_in_patch(patch)
	var group: Array[EncounterEntry] = []
	for sprite in sprites:
		var entry = EncounterEntry.new()
		entry.species = sprite.species
		entry.level = sprite.level
		group.append(entry)
		sprite.queue_free()
	GameState.current_wild_group = group
	_start_encounter("Grass")

# scene_path explícito ("res://scenes/overworld/world_archis.tscn", não
# mais o antigo "res://scenes/overworld/world.tscn") — garante que
# derrota/vitória volta pra ESTA cena cortada, não pro world.tscn
# monolítico antigo.
func _start_encounter(source: String = "Grass") -> void:
	if _battle_starting:
		return
	_battle_starting = true
	_reset_water_encounter_counter()
	GameState.current_encounter_source = source
	GameState.save_player_state(player.grid_pos, player.facing, ROUTE1_SCENE_PATH)
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

func trigger_wild_encounter() -> void:
	GameState.current_wild_group = _pick_random_wild_group()
	_start_encounter()

func _pick_random_wild_group() -> Array[EncounterEntry]:
	var group: Array[EncounterEntry] = []
	var area = GameState.current_area
	if area == null:
		return group
	var eligible = area.get_eligible_wild_spawn_entries()
	if eligible.is_empty():
		return group
	var total_weight := 0.0
	for e in eligible:
		total_weight += e.spawn_chance
	if total_weight <= 0.0:
		return group
	var roll := randf() * total_weight
	var cumulative := 0.0
	var picked: WildSpawnEntry = eligible[eligible.size() - 1]
	for e in eligible:
		cumulative += e.spawn_chance
		if roll < cumulative:
			picked = e
			break
	var entry = EncounterEntry.new()
	entry.species = picked.species
	entry.level = picked.level
	group.append(entry)
	return group

func start_trainer_battle(trainer: Node) -> void:
	if _battle_starting:
		return
	_battle_starting = true
	get_tree().paused = false
	GameState.save_player_state(player.grid_pos, player.facing, ROUTE1_SCENE_PATH)
	GameState.is_trainer_battle = true
	GameState.current_trainer_id = trainer.trainer_id
	GameState.current_trainer_team = trainer.get_active_team()
	GameState.current_trainer_prize = trainer.get_prize_money()
	GameState.current_trainer_badge_name = trainer.badge_name
	GameState.current_trainer_iq = trainer.iq
	GameState.current_trainer_starting_weather = trainer.starting_weather
	GameState.current_trainer_starting_weather_overridable = trainer.starting_weather_overridable
	GameState.generated_map = trainer.generated_map
	GameState.manual_map = trainer.manual_map
	GameState.forced_battle_tileset = trainer.forced_battle_tileset
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

func start_boss_battle(boss: Node) -> void:
	if _battle_starting:
		return
	_battle_starting = true
	get_tree().paused = false
	GameState.save_player_state(player.grid_pos, player.facing, ROUTE1_SCENE_PATH)
	GameState.is_boss_battle = true
	GameState.current_boss_entry = boss.boss_entry
	GameState.current_boss_iq = boss.iq
	GameState.generated_map = boss.generated_map
	GameState.manual_map = boss.manual_map
	GameState.forced_battle_tileset = boss.forced_battle_tileset
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

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

func is_one_way_tile(cell: Vector2i) -> bool:
	if not _objects_has_one_way_layer:
		return false
	var obj_data = tile_map_objects.get_cell_tile_data(cell)
	return obj_data != null and obj_data.get_custom_data("one_way_dir") != ""

func is_cell_water(cell: Vector2i) -> bool:
	if _objects_has_water_layer:
		var obj_data = tile_map_objects.get_cell_tile_data(cell)
		if obj_data != null and obj_data.get_custom_data("water"):
			return true
	if _ground_has_water_layer:
		var ground_data = tile_map_ground.get_cell_tile_data(cell)
		if ground_data != null and ground_data.get_custom_data("water"):
			return true
	return false

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
	if item == null:
		return
	if item.opens_song_menu:
		_open_song_menu(item)
	else:
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
	if active_menu != null or SceneTransition.is_active:
		return
	var menu = GAME_MENU_SCENE.instantiate()
	add_child(menu)
	active_menu = menu
	menu.closed.connect(_on_menu_closed)
	get_tree().paused = true

func _open_system_menu() -> void:
	if active_menu != null or SceneTransition.is_active:
		return
	var menu = SYSTEM_MENU_SCENE.instantiate()
	add_child(menu)
	active_menu = menu
	menu.closed.connect(_on_menu_closed)
	get_tree().paused = true

func _open_song_menu(item: ItemData) -> void:
	if active_menu != null or SceneTransition.is_active:
		return
	var menu = SONG_MENU_SCENE.instantiate()
	add_child(menu)
	active_menu = menu
	menu.setup(item)
	menu.closed.connect(_on_menu_closed)
	get_tree().paused = true

func _on_menu_closed() -> void:
	active_menu = null
	get_tree().paused = false
	_apply_pending_song_if_any()

func _apply_pending_song_if_any() -> void:
	if GameState.pending_song == "":
		return
	var song = GameState.pending_song
	GameState.pending_song = ""
	player.apply_song(song)
