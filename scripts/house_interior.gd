extends Node2D

# Script genérico pra QUALQUER interior (casa, loja, caverna, ginásio...) —
# mesma base de movimento/menus de world.gd, MENOS o que só faz
# sentido lá fora:
#   - sem grama alta/encontro aleatório (não tem grama dentro de casa);
#   - sem AreaNotification (o banner de nome de área é coisa de overworld —
#     rota/cidade tem nome pra mostrar, um cômodo de casa não).
# Isso é o MESMO arquivo pra toda casa/loja/caverna que você desenhar — cada
# interior é uma CENA separada (duplique house_interior.tscn), mas todas
# apontam pra este mesmo script, do jeito que Nurse/Baldo reusam npc.gd.
#
# Uma TileMapLayerGround obrigatória + uma TileMapLayerObjects opcional
# (get_node_or_null — nem todo cômodo precisa de uma camada de objetos
# separada; se não existir, is_cell_walkable() simplesmente ignora essa
# parte e usa só o Chão), do mesmo jeito que World combina as duas (Objetos
# manda quando as duas têm tile na mesma célula).

@onready var tile_map_ground: TileMapLayer = $TileMapLayerGround
@onready var tile_map_objects: TileMapLayer = get_node_or_null("TileMapLayerObjects")
# Opcional, mesmo espírito de tile_map_objects acima — nem todo interior
# precisa de um "topo" (telhado de prateleira alta, viga...) desenhado por
# cima do jogador. Ver _ready() logo abaixo: se existir, ganha z_index=1
# automaticamente — SEM isso, ficava sujeito à ordem dos nodes na cena
# (Actors, que tem o Player, normalmente vem DEPOIS de TileMapLayerTop na
# árvore, o que desenharia o jogador POR CIMA do topo, errado). world.tscn
# já faz isso à mão (z_index=1 direto no node, ver comentário grande em
# world.gd sobre TileMapLayerTop) — aqui vira automático pra qualquer
# interior novo não esquecer de configurar isso (foi exatamente o que
# aconteceu em oak_lab_interior.tscn: bug só ficou visível depois que o
# jogador passou a ser posicionado corretamente, ver fix de global_position
# em npc.gd/player.gd/trainer.gd).
@onready var tile_map_top: TileMapLayer = get_node_or_null("TileMapLayerTop")

@onready var player: Node2D = $Actors/Player

const GAME_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/game_menu.tscn")
const SYSTEM_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/system_menu.tscn")

# HUD permanente (ícone de período do dia + nome da área — ver time_hud.gd)
# instanciado em CÓDIGO em vez de precisar ser arrastado à mão em CADA
# interior (mesmo espírito de tile_map_top.z_index=1 acima, ver comentário
# grande lá — automático pra ninguém esquecer de configurar numa cena nova).
# GameState.current_area continua sendo o da ÁREA DE FORA (nenhum interior
# muda esse valor, ver comentário no topo do arquivo sobre não ter
# AreaNotification aqui) — mostrar esse mesmo nome enquanto o jogador está
# DENTRO de um prédio daquela área é o comportamento certo (ex: "Olivine
# City" continua na tela dentro de uma casa de Olivine City). Sem a máscara
# de brilho (CanvasModulate) — pedido do usuário foi só "no overworld",
# interior tem iluminação própria, não deve escurecer/clarear com a hora.
const TIME_HUD_SCENE: PackedScene = preload("res://scenes/ui/hud/time_hud.tscn")

const FACING_TO_DIR = {
	"down": Vector2i(0, 1),
	"up": Vector2i(0, -1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}

var active_menu: CanvasLayer = null

# Trava contra duas batalhas disparando ao mesmo tempo — ver comentário
# grande gêmeo em world.gd::_battle_starting. Não tem grama aqui dentro (a
# outra ponta do problema, que causava o race de verdade lá fora), mas
# is_battle_starting()/start_trainer_battle() ainda precisam existir: é
# nisso que trainer.gd::_process()/_begin_battle() mexem sem checar QUAL
# cena hospeda o Trainer — sem isso, um Trainer colocado dentro de um
# interior (loja, ginásio...) quebraria com "Nonexistent function
# 'is_battle_starting'", mesmo bug que já apareceu em world.gd.
var _battle_starting: bool = false

func is_battle_starting() -> bool:
	return _battle_starting

# true só se a TileSet da camada de Objetos DESTE interior tiver a custom
# data layer "one_way_dir" (criada em assets/tiles/tilesets/OW/outside.tres
# pro sistema de ladeira de mão única, ver world.gd::is_cell_walkable) — nem
# toda TileSet de interior tem essa layer (ladeira é mecânica de OVERWORLD,
# não faz sentido dentro de casa/loja), e TileData.get_custom_data() lança
# um ERRO de verdade ("TileSet has no layer with name: one_way_dir") se a
# layer não existir na TileSet, em vez de só devolver vazio — foi
# exatamente esse erro que crashou o jogo ao tentar entrar num interior
# (bug reportado: "TileSet has no layer with name: one_way_dir" +
# "Trying to assign value of type 'Nil' to a variable of type 'String'").
# Calculado uma vez aqui (a TileSet de uma camada não muda em runtime) e
# reusado por is_cell_walkable()/is_one_way_tile() abaixo, pra nunca chamar
# get_custom_data("one_way_dir") numa TileSet que não tem essa layer.
var _objects_has_one_way_layer: bool = false

# Mesmo guard/motivo de _objects_has_one_way_layer acima, pra "water" (ver
# is_cell_water abaixo) — quase nenhum interior vai ter essa layer (não
# existe água dentro de casa normalmente), mas o guard existe pelo mesmo
# motivo de sempre: nunca chamar get_custom_data("water") numa TileSet que
# não tem essa layer.
var _ground_has_water_layer: bool = false
var _objects_has_water_layer: bool = false

func _ready() -> void:
	player.tile_entered.connect(_on_player_tile_entered)
	if tile_map_objects != null:
		_objects_has_one_way_layer = _tileset_has_custom_data(tile_map_objects.tile_set, "one_way_dir")
		_objects_has_water_layer = _tileset_has_custom_data(tile_map_objects.tile_set, "water")
	_ground_has_water_layer = _tileset_has_custom_data(tile_map_ground.tile_set, "water")
	if tile_map_top != null:
		tile_map_top.z_index = 1   # ver comentário grande em tile_map_top acima
	add_child(TIME_HUD_SCENE.instantiate())   # ver comentário grande em TIME_HUD_SCENE acima
	_restore_player_state()
	_sync_live_position()

func _tileset_has_custom_data(tile_set: TileSet, layer_name: String) -> bool:
	if tile_set == null:
		return false
	for i in tile_set.get_custom_data_layers_count():
		if tile_set.get_custom_data_layer_name(i) == layer_name:
			return true
	return false

# Todo interior é alcançado por uma Door (ver door.gd) — nunca é a cena
# inicial do jogo, então não existe "spawn padrão" pra um interior: sempre
# tem uma posição salva esperando (a que a Door de entrada configurou).
func _restore_player_state() -> void:
	if GameState.has_saved_position:
		player.teleport_to(GameState.player_grid_pos, GameState.player_facing)

func _on_player_tile_entered(cell: Vector2i) -> void:
	_sync_live_position()
	var door = get_door_at(cell)
	if door != null:
		use_door(door)

func _sync_live_position() -> void:
	GameState.live_grid_pos = player.grid_pos
	GameState.live_facing = player.facing

# Delegado por player.gd::can_move_to() — mesma lógica de world.gd
# (Objetos manda quando tem tile na célula, senão cai pro Chão). move_dir
# (opcional, sem uso aqui ainda) só existe pra bater com a mesma assinatura
# de world.gd::is_cell_walkable — ver comentário gêmeo em world.gd.
func is_cell_walkable(cell: Vector2i, move_dir: Vector2i = Vector2i.ZERO) -> bool:
	if tile_map_objects != null:
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

# Ver world.gd::is_one_way_tile — mesma lógica, só que com a camada de
# Objetos opcional (nem todo interior tem uma, ver tile_map_objects acima) E
# com o guard extra de _objects_has_one_way_layer (ver comentário grande
# acima, em _ready).
func is_one_way_tile(cell: Vector2i) -> bool:
	if tile_map_objects == null or not _objects_has_one_way_layer:
		return false
	var obj_data = tile_map_objects.get_cell_tile_data(cell)
	return obj_data != null and obj_data.get_custom_data("one_way_dir") != ""

# Ver world.gd::is_cell_water — mesma lógica, só que com a camada de
# Objetos opcional (nem todo interior tem uma) igual is_cell_walkable/
# is_one_way_tile acima. Precisa existir mesmo que quase sempre devolva
# false (nenhum interior tem água hoje) — Player.can_move_to() chama isso
# através de `world` sem saber se está dentro de World ou HouseInterior
# (mesma classe de bug já vista com is_battle_starting, ver comentário
# grande em _battle_starting).
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

# Chamado por Trainer._begin_battle() (ver trainer.gd) — mesmo espírito dos
# gêmeos em world.gd::start_trainer_battle. scene_file_path (em vez
# de um caminho fixo tipo "res://scenes/overworld/world.tscn") é o que
# permite este MESMO script servir qualquer interior: cada casa/loja tem seu
# próprio arquivo .tscn, mas todos apontam pra este script — scene_file_path
# é preenchido automaticamente pelo Godot com o caminho do .tscn que está
# rodando de verdade agora, sem precisar hardcodar nada aqui.
func start_trainer_battle(trainer: Node) -> void:
	if _battle_starting:
		return
	_battle_starting = true
	get_tree().paused = false
	GameState.save_player_state(player.grid_pos, player.facing, scene_file_path)
	GameState.is_trainer_battle = true
	GameState.current_trainer_id = trainer.trainer_id
	GameState.current_trainer_team = trainer.get_active_team()
	GameState.current_trainer_prize = trainer.get_prize_money()
	GameState.current_trainer_iq = trainer.iq
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

func get_door_at(cell: Vector2i) -> Door:
	for door in get_tree().get_nodes_in_group("door"):
		if door.grid_pos == cell:
			return door
	return null

# Porta abre (se tiver animação configurada) -> fade pra preto -> troca de
# cena -> fade clareia. Mesmo comentário de world.gd::use_door.
func use_door(door: Door) -> void:
	await door.play_open_animation()
	GameState.save_player_state(door.target_grid_pos, door.target_facing, door.target_scene_path)
	SceneTransition.change_scene_with_fade(door.target_scene_path)

func _get_npc_at(cell: Vector2i) -> Npc:
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.grid_pos == cell:
			return npc
	return null

func has_npc_at(cell: Vector2i) -> bool:
	return _get_npc_at(cell) != null

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

func _try_interact() -> void:
	if player.is_moving:
		return
	var dir = FACING_TO_DIR.get(player.facing, Vector2i.ZERO)
	var target_cell = player.grid_pos + dir
	var npc = _get_npc_at(target_cell)
	if npc != null:
		npc.face_towards(player.grid_pos)
		npc.interact()

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
	_apply_pending_song_if_any()

# Mesmo comentário grande de world.gd::_apply_pending_song_if_any — sem
# atalho de Tool aqui dentro (nenhum interior tem _trigger_tool_shortcut),
# então o ÚNICO jeito de GameState.pending_song vir preenchido é o jogador
# ter usado a Fairy Ocarina de dentro da Bag. "Surf" indoors sempre falha em
# silêncio (Player.apply_song -> _apply_surf_song() não acha água nenhuma
# na frente, ver world.gd::is_cell_water sempre false aqui) — comportamento
# esperado, não é um bug.
func _apply_pending_song_if_any() -> void:
	if GameState.pending_song == "":
		return
	var song = GameState.pending_song
	GameState.pending_song = ""
	player.apply_song(song)
