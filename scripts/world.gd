extends Node2D

# Script da cena "World" — hoje é onde mora ARCHI (a primeira cidade
# do mundo, desenhada pelo usuário direto em world.tscn), a cena overworld
# de verdade do jogo. Mesma mecânica de house_interior.gd (passo a passo,
# grama alta com encontro aleatório, menu A/Esc, atalhos de Tool, interação
# com NPC) — só que adaptada pra uma cena de overworld com TRÊS
# TileMapLayers (Ground/Objects/Top) em vez de um só (ver comentário grande
# abaixo sobre por que isso importa), já que aqui fora existe grama alta,
# água, etc. Se um dia os dois scripts ficarem parecidos demais a ponto de
# incomodar, dá pra puxar a parte comum (menus, tools, interact) pra uma
# classe base — por enquanto, copiado é mais simples de entender/mexer.

# Aqui em ARCHI, o usuário desenhou em TRÊS camadas separadas
# (diferente de um interior comum, que costuma se virar com só uma
# TileMapLayerGround — ver house_interior.gd), então "onde ando" e "onde
# bate parede" não são sempre a mesma pergunta:
#   - TileMapLayerGround: chão andável, grama (bate encontro) e água
#     (custom data "water", ver is_cell_water abaixo — só andável surfando,
#     ver Player.can_move_to/apply_song).
#   - TileMapLayerObjects: colisão + elementos interativos (árvores, casas,
#     placas...) — quando uma célula tem tile AQUI, ele manda: mesmo que o
#     Ground embaixo seja andável, um objeto em cima pode bloquear (ex: uma
#     árvore plantada em cima de grama).
#   - TileMapLayerTop: SEM colisão nenhuma — é só o "topo" de alguma coisa
#     (o telhado de uma casa, a copa de uma árvore) que o jogador precisa
#     passar POR BAIXO visualmente. Por isso ela fica de fora do grupo
#     "Actors" (que tem y_sort_enabled) E ganha z_index=1 (mesma técnica de
#     house_interior.gd::tile_map_top) — sempre desenhada por CIMA do
#     jogador, nunca compete de posição Y com ele.
@onready var tile_map_ground: TileMapLayer = $TileMapLayerGround
@onready var tile_map_objects: TileMapLayer = $TileMapLayerObjects

@onready var player: Node2D = $Actors/Player
@onready var area_notification: CanvasLayer = $AreaNotification
# CanvasModulate de brilho bem sutil por período do dia — máscara que só
# afeta o mapa/Actors (não afeta NENHUM CanvasLayer, como area_notification,
# menus ou TimeHud), ver GameState.get_time_of_day_mask_color().
@onready var canvas_modulate: CanvasModulate = $CanvasModulate

const GRASS_RUSTLE_SCENE: PackedScene = preload("res://scenes/effects/grass_rustle.tscn")
# Sprite selvagem visível na grama (ver wild_sprite.gd/_refresh_grass_patch
# abaixo) — refactor de encontro selvagem, 2026-09-10.
const WILD_SPRITE_SCENE: PackedScene = preload("res://scenes/npc/wild_sprite.tscn")
const GAME_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/game_menu.tscn")
const SYSTEM_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/system_menu.tscn")
const SONG_MENU_SCENE: PackedScene = preload("res://scenes/ui/popups/song_menu.tscn")
# Mesma caixa de 1 linha que trainer.gd/loot_ball.gd já usam — reaproveitada
# aqui pro aviso do Oak (ver _block_leaving_without_starter).
const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")

# ---------- Professor Oak: travar saída de Archi sem starter ----------
# Pedido do usuário (2026-08-04): "Professor Oak: Stops the player from
# leaving Archis town the first time they try to, if the 'chose a starter'
# flag is negative, then teleports the player to his lab." Resposta do
# usuário à pergunta de esclarecimento (não existe porta nenhuma de "sair
# da cidade" ainda, só as entradas de casa/ginásio) — "leaving" aqui
# significa ENTRAR no mato alto/área selvagem (Route 1 via ROUTE1_BOUNDARY_Y
# ou Barias via BARIAS_BOUNDS), não atravessar uma Door. Mesma flag que os
# 3 StarterX de oak_lab_interior.tscn já usam como exclusive_flag
# (loot_ball.gd), então escolher QUALQUER starter já destrava isto de
# graça, sem precisar duplicar nada.
const OAK_LAB_SCENE_PATH = "uid://cw0tstklsgtt6"
# Mesmo alvo que DoorToOakLab/BackDoorToOakLab (ver world.tscn) já usam pra
# entrar no laboratório — reaproveitado aqui pra cair no mesmo lugar de
# sempre, não um ponto novo.
const OAK_LAB_ENTRY_GRID_POS = Vector2i(0, 2)
const OAK_BLOCK_MESSAGE = "OAK: Whoa there! You shouldn't wander out without a Pokémon partner. Let's get you sorted first."

const FACING_TO_DIR = {
	"down": Vector2i(0, 1),
	"up": Vector2i(0, -1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}

@export var encounter_area: EncounterArea

# ---------- Divisão de áreas (ARCHI <-> ROUTE 1) ----------
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

# ---------- Barias (retângulo, não linha) ----------
# Pedido do usuário: "The rectangle with (-2,-57) (25,-37) for edges is the
# town of Barias" — diferente de ARCHI/ROUTE 1 acima (uma única linha de
# fronteira em Y), aqui os dois pontos descrevem os CANTOS opostos de um
# retângulo de verdade, então precisa checar X e Y juntos, não só Y. Rect2i
# em Godot é meio-aberto (position <= ponto < position+size — o canto
# position+size NÃO conta como "dentro"), por isso size é (25-(-2)+1,
# -37-(-57)+1) em vez de só (25-(-2), -37-(-57)): sem o +1 em cada eixo, a
# própria borda direita/inferior descrita pelo usuário (x=25, y=-37) ficaria
# FORA do retângulo. Checado ANTES da linha ARCHI/ROUTE 1 em
# _area_for_position() — Barias é uma área "furada" dentro do resto do
# mapa, não mais uma faixa que se estende pro X inteiro.
const BARIAS_BOUNDS = Rect2i(Vector2i(-2, -57), Vector2i(28, 21))
@export var barias_area: EncounterArea

# Coordenada do tile de grama alta DENTRO do atlas do TileSet outside.tres
# (diferente do forest_tileset.tres usado em Test — cada folha de tiles tem
# sua própria grama num lugar diferente). O valor abaixo é só um PLACEHOLDER
# — ainda não sabemos qual célula do atlas é a grama de verdade em
# outside.tres. Pra descobrir: abra world.tscn, clique na camada
# TileMapLayerGround, abra o painel de tiles (embaixo) e clique no tile de
# grama alta que você pintou — o Godot mostra as coordenadas dele (algo tipo
# "(x, y)") no rodapé/tooltip do painel. Depois é só selecionar o node World
# no Inspector e digitar esse valor em "Grass Atlas Coords" — sem isso, o
# encontro aleatório na grama de ARCHI não vai disparar (ou vai
# disparar no tile errado).
@export var grass_atlas_coords: Vector2i = Vector2i(-1, -1)

const MIN_ENCOUNTER_STEPS = 5
const MAX_ENCOUNTER_STEPS = 15

# Pedido original do usuário (2026-09-10, verbatim): "let's limit each grass
# group to 6 units max spawning, and each group refreshes when moving
# between areas or after 5 seconds" — "grass group" = o mesmo "patch de
# grama conectada" que _get_connected_grass_patch já calcula (ver comentário
# grande lá, resposta do usuário à pergunta de esclarecimento do refactor
# anterior). Ajustado no dia seguinte (2026-09-11, verbatim): "group of
# grass spawns a number of units depending on its size. For every 10 tiles
# in the group, an extra unit is allowed to spawn, up to a maximum of 6" —
# MAX_UNITS_PER_GRASS_GROUP virou o TETO SUPERIOR (patches grandes), não
# mais o teto de todo patch; o teto de verdade por patch é calculado por
# _max_units_for_patch (ver lá pra fórmula exata), usado por
# _refresh_grass_patch. GRASS_GROUP_REFRESH_INTERVAL: intervalo (em
# segundos) do Timer que re-sorteia TODOS os patches — ver
# _start_grass_refresh_timer/_refresh_all_grass_patches. A troca de área
# (Archi <-> Route 1 <-> Barias) é o OUTRO gatilho de refresh, sem constante
# própria — ver _update_current_area.
const MAX_UNITS_PER_GRASS_GROUP = 6
const GRASS_GROUP_REFRESH_INTERVAL = 5.0

# Contador de passos SURFANDO em cima d'água até o próximo encontro (ver
# _on_player_tile_entered) — ainda por STEP, diferente de grama alta agora
# (ver comentário grande em _refresh_grass_patch/_trigger_wild_sprite_
# encounter): o refactor de encontro selvagem (2026-09-10) só pediu pra
# mudar "grass areas", água continua no sistema antigo de sempre.
var steps_until_water_encounter: int = 0

# Cache de TODOS os patches de grama conectada do mapa (cada item é um
# Array[Vector2i], ver _compute_grass_patches) — calculado UMA vez em
# _ready(), reaproveitado por todo refresh depois (nunca precisa refazer o
# flood-fill inteiro de novo, só re-sortear quem nasce em cima de cada
# patch já conhecido). Ver MAX_UNITS_PER_GRASS_GROUP/GRASS_GROUP_REFRESH_
# INTERVAL acima.
var _grass_patches: Array[Array] = []

var active_menu: CanvasLayer = null

# Trava contra DUAS batalhas disparando ao mesmo tempo — mesmo comentário
# grande gêmeo em house_interior.gd::_battle_starting (mesmo bug, mesma
# correção: grama alta + Trainer avistando no MESMO frame não podem trocar
# de cena os dois; ver is_battle_starting/start_trainer_battle logo abaixo).
var _battle_starting: bool = false

# Lido por trainer.gd::_process() ANTES de sequer checar visão/avistar —
# mesmo comentário de house_interior.gd::is_battle_starting.
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

# Mesmo guard/motivo de _objects_has_one_way_layer acima, agora pra "water"
# (ver Player.can_move_to/is_cell_water abaixo) — checado nas DUAS camadas
# (Ground e Objects, diferente de one_way_dir que só existe em Objects),
# porque água normalmente é pintada na camada de Chão, não na de Objetos.
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
	_update_current_area()
	_sync_live_position()
	canvas_modulate.color = GameState.get_time_of_day_mask_color()   # sem esperar o primeiro _process, já entra na cor certa

# Roda a CADA frame sem comparar contra o valor anterior — GameState.
# get_time_of_day_mask_color() já é barato o bastante (só um match de 3
# ramos), não vale a pena cachear/comparar só pra evitar essa chamada.
func _process(_delta: float) -> void:
	canvas_modulate.color = GameState.get_time_of_day_mask_color()

func _tileset_has_custom_data(tile_set: TileSet, layer_name: String) -> bool:
	if tile_set == null:
		return false
	for i in tile_set.get_custom_data_layers_count():
		if tile_set.get_custom_data_layer_name(i) == layer_name:
			return true
	return false

# Qual EncounterArea vale pra célula `cell` — Barias primeiro (retângulo
# fechado, ver BARIAS_BOUNDS acima), DEPOIS a linha ARCHI/ROUTE 1 (só olha
# o Y, ver comentário grande em ROUTE1_BOUNDARY_Y). Ordem importa: se
# Barias um dia ficar do lado ROUTE 1 da linha (y <= ROUTE1_BOUNDARY_Y), o
# retângulo ainda precisa vencer, senão o jogador nunca veria "BARIAS" no
# HUD lá dentro.
func _area_for_position(cell: Vector2i) -> EncounterArea:
	if barias_area != null and BARIAS_BOUNDS.has_point(cell):
		return barias_area
	if route1_area != null and cell.y <= ROUTE1_BOUNDARY_Y:
		return route1_area
	return encounter_area

# Chamado tanto na entrada da cena (_ready, com a posição já restaurada por
# _restore_player_state) quanto A CADA passo (ver _on_player_tile_entered) —
# é o segundo caso que faz a troca ARCHI <-> ROUTE 1 acontecer sozinha
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
		# Pedido do usuário: "each group refreshes when moving between areas
		# or after 5 seconds" — esta é a metade "moving between areas" (a
		# outra metade é o Timer de _start_grass_refresh_timer). Re-sorteia
		# TODOS os patches, não só os da área nova/antiga — mais simples, e
		# barato o bastante (a mesma coisa já roda a cada 5s de qualquer
		# jeito). Nota: na PRIMEIRA chamada de _update_current_area() (dentro
		# de _ready(), logo abaixo), GameState.last_notified_area_name ainda
		# está "" (save novo) ou já é diferente da área calculada agora, então
		# este bloco roda de novo aqui — refresh redundante com o de _ready(),
		# mas inofensivo (só re-sorteia mais uma vez antes do jogador ver a
		# tela).
		_refresh_all_grass_patches()

func _restore_player_state() -> void:
	if GameState.has_saved_position:
		player.teleport_to(GameState.player_grid_pos, GameState.player_facing)

func _on_player_tile_entered(cell: Vector2i) -> void:
	_sync_live_position()
	_update_current_area()

	# Professor Oak (ver comentário grande em OAK_LAB_SCENE_PATH acima) —
	# roda ANTES de porta/água/grama de propósito: sem starter nenhum, o
	# jogador não deveria conseguir nem abrir uma porta de dentro de Route
	# 1/Barias (não que exista uma lá) nem disparar um encontro selvagem
	# impossível de vencer. Vale TODA VEZ que a área mudar pra fora de Archi
	# enquanto a flag continuar negativa, não só a primeira tentativa —
	# GameState.current_area já foi atualizado por _update_current_area()
	# uma linha acima.
	if _block_leaving_without_starter():
		return

	# Porta/entrada (ver door.gd) manda ANTES de qualquer coisa.
	var door = get_door_at(cell)
	if door != null:
		use_door(door)
		return

	# Surfando em cima d'água — pedido do usuário: "While surfing, the
	# player may encounter wild units just like grass, and the encounter
	# table is different from the grass on that area". Ainda por CONTADOR de
	# passos (steps_until_water_encounter) — diferente da grama alta agora
	# (ver _refresh_grass_patch/_trigger_wild_sprite_encounter mais abaixo:
	# refactor 2026-09-10 só mudou "grass areas", água ficou de fora do
	# pedido). GameState.is_surfing != null aqui é sempre true na prática (só
	# dá pra pisar numa célula de água ESTANDO surfando, ver Player.
	# can_move_to) — checado mesmo assim por clareza/defesa, mesmo estilo do
	# resto do projeto. `return` no final: uma célula de água nunca é TAMBÉM
	# grama alta, não faz sentido cair no bloco de baixo depois.
	if GameState.is_surfing and is_cell_water(cell):
		steps_until_water_encounter -= 1
		if steps_until_water_encounter <= 0 and GameState.current_area != null and GameState.current_area.has_source("Water"):
			_start_encounter("Water")
		return

	# Sprite selvagem (ver wild_sprite.gd) — refactor de encontro selvagem
	# (2026-09-10, pedido do usuário verbatim): "will initiate combat when
	# touched by the player". WildSprite NÃO bloqueia o passo (ver comentário
	# grande lá), então o jogador só "toca" nele ao entrar de fato na mesma
	# célula — exatamente este callback. Checado ANTES da grama comum porque
	# todo tile com WildSprite também É grama (_refresh_grass_patch só
	# spawna em cima de grama elegível), mas o inverso não vale (a maioria
	# dos tiles de grama fica sem sprite nenhum).
	var sprite = get_wild_sprite_at(cell)
	if sprite != null:
		_trigger_wild_sprite_encounter(sprite)
		return

	var in_grass = _is_tall_grass(cell)
	player.set_sunk_in_grass(in_grass)

	if not in_grass:
		return

	# Sem contador de passos aqui mais — grama alta virou só decoração
	# visual (afunda o Player, toca o efeito de "rustle") + o CHÃO onde
	# WildSprite pode ter nascido (ver _refresh_grass_patch). O encontro em
	# si só dispara ao TOCAR um sprite de verdade (bloco acima) — pedido do
	# usuário: "There won't be any random encounters from stepping on grass.
	# Instead, grass areas will spawn overworld sprites".
	_spawn_grass_rustle(cell)

# Mesma varredura de _get_npc_at, só que no grupo "door" (ver door.gd).
func get_door_at(cell: Vector2i) -> Door:
	for door in get_tree().get_nodes_in_group("door"):
		if door.grid_pos == cell:
			return door
	return null

# Porta abre (se tiver animação configurada) -> fade pra preto -> troca de
# cena -> fade clareia. Mesmo comentário de house_interior.gd::use_door.
func use_door(door: Door) -> void:
	await door.play_open_animation()
	GameState.save_player_state(door.target_grid_pos, door.target_facing, door.target_scene_path)
	SceneTransition.change_scene_with_fade(door.target_scene_path)

# true (e já disparou a mensagem/teleporte) se o jogador acabou de entrar
# numa área que NÃO é Archi (Route 1 ou Barias, ver _area_for_position)
# enquanto GameState.get_flag("STARTER1_CHOSEN") ainda for false — ver
# comentário grande em OAK_LAB_SCENE_PATH acima. current_area == null
# (encounter_area de Archi não configurado no Inspector) ou == encounter_area
# (ainda dentro de Archi) = nada a bloquear, false direto, sem gastar
# mensagem nenhuma.
func _block_leaving_without_starter() -> bool:
	if GameState.get_flag("STARTER1_CHOSEN"):
		return false
	if GameState.current_area == null or GameState.current_area == encounter_area:
		return false
	get_tree().paused = true
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(OAK_BLOCK_MESSAGE)
	box.closed.connect(_on_oak_block_message_closed)
	return true

# Só desliga o pause e troca de cena DEPOIS do jogador ler o aviso — mesmo
# GameState.save_player_state + SceneTransition.change_scene_with_fade que
# use_door() já usa pra qualquer outra transição de cena, só que sem porta
# nenhuma envolvida (não tem play_open_animation() aqui, o jogador não
# "abriu" nada, foi Oak quem interviu).
func _on_oak_block_message_closed() -> void:
	get_tree().paused = false
	GameState.save_player_state(OAK_LAB_ENTRY_GRID_POS, "down", OAK_LAB_SCENE_PATH)
	SceneTransition.change_scene_with_fade(OAK_LAB_SCENE_PATH)

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

# ---------- Sprites selvagens no overworld (grama alta) ----------
# Refactor de encontro selvagem, 2026-09-10 (pedido do usuário, ver resumo
# grande no topo do arquivo de conversa/commits desta sessão): substitui o
# antigo "% chance por passo" de grama por sprites visíveis, um touch-to-
# battle igual LootBall só que sem precisar de confirm.

# Divide TODO tile de grama alta do mapa em patches conectados disjuntos
# (ver _get_connected_grass_patch) e guarda em _grass_patches — chamado UMA
# vez em _ready(), antes do primeiro _refresh_all_grass_patches(). `visited`
# aqui é só pra não processar o mesmo tile duas vezes (cada flood-fill já
# devolve o patch INTEIRO de uma vez, então um tile já visto nunca precisa
# de outro flood-fill próprio) — não tem nada a ver com o `visited` local
# de dentro de _get_connected_grass_patch, que é descartado a cada chamada.
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

# Re-sorteia TODOS os patches conhecidos (ver _grass_patches) — os DOIS
# gatilhos de refresh pedidos pelo usuário chamam esta função: o Timer de
# _start_grass_refresh_timer (a cada GRASS_GROUP_REFRESH_INTERVAL segundos)
# e _update_current_area (ao trocar de área). Também é quem faz o povoamento
# INICIAL da cena (chamado uma vez em _ready(), logo depois de
# _compute_grass_patches) — não existe uma função de "primeira vez" separada,
# povoar do zero e "refrescar" são a mesma operação (despawna quem tiver,
# spawna de novo), então reaproveitar é mais simples que duplicar.
func _refresh_all_grass_patches() -> void:
	for patch in _grass_patches:
		_refresh_grass_patch(patch)

# Re-sorteia UM patch: derruba (queue_free) todo WildSprite que já estava
# nele, depois sorteia de novo — pra CADA célula do patch, em ORDEM
# EMBARALHADA (mesmo espírito de antes: nenhuma célula tem vantagem fixa de
# "ser checada primeiro"), entre as WildSpawnEntry elegíveis da área dona
# do patch (ver _area_for_position — todo o patch pertence à MESMA área,
# já que _get_connected_grass_patch não atravessa fronteira nenhuma sozinho,
# só grama fisicamente contígua) TAMBÉM em ordem embaralhada, até a PRIMEIRA
# cujo spawn_chance passe no roll — essa nasce ali, célula segue pro próximo
# (só 1 sprite por tile, igual antes). Só que agora existe um TETO por
# TAMANHO do patch (ver _max_units_for_patch): assim que esse teto de
# sprites já tiver nascido neste patch nesta rodada, o resto das células
# fica vazio de propósito, mesmo que teria passado no roll. A maioria das
# células continua sem sprite nenhum de qualquer jeito (ver comentário em
# wild_spawn_entry.gd), então o teto raramente chega a ser o fator
# limitante de verdade num patch pequeno.
func _refresh_grass_patch(patch: Array[Vector2i]) -> void:
	for sprite in _get_wild_sprites_in_patch(patch):
		sprite.queue_free()
	if patch.is_empty():
		return
	var area = _area_for_position(patch[0])
	if area == null:
		return
	var eligible = area.get_eligible_wild_spawn_entries()
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

# Teto de WildSprite simultâneos NESTE patch — pedido do usuário (2026-09-11,
# verbatim): "group of grass spawns a number of units depending on its size.
# For every 10 tiles in the group, an extra unit is allowed to spawn, up to
# a maximum of 6". Lido como: 1 unidade "de base" (qualquer patch com pelo
# menos 1 tile já permite 1), +1 a cada 10 tiles inteiros a mais (divisão
# inteira — 10 tiles = +1, 19 tiles ainda só +1, 20 tiles = +2), nunca
# passando de MAX_UNITS_PER_GRASS_GROUP mesmo que o patch seja enorme.
func _max_units_for_patch(patch: Array[Vector2i]) -> int:
	return min(MAX_UNITS_PER_GRASS_GROUP, 1 + patch.size() / 10)

func _spawn_wild_sprite(entry: WildSpawnEntry, cell: Vector2i) -> void:
	var sprite: WildSprite = WILD_SPRITE_SCENE.instantiate()
	$Actors.add_child(sprite)
	sprite.setup(entry.species, entry.level, cell, tile_map_ground)

# Timer repetitivo (one_shot = false, diferente de todo `await get_tree().
# create_timer(...).timeout` já usado no resto do projeto — ver battle.gd/
# bed.gd/capture_ball.gd, todos casos de ATRASO único, não de repetição sem
# fim) — pedido do usuário: "each group refreshes... after 5 seconds".
# Criado em código (Timer.new()) em vez de um node na cena porque é um
# detalhe puramente interno deste sistema, sem nada pra configurar no
# Inspector (diferente de grass_atlas_coords/encounter_area, que o usuário
# PRECISA poder ajustar por cena).
func _start_grass_refresh_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = GRASS_GROUP_REFRESH_INTERVAL
	timer.one_shot = false
	timer.timeout.connect(_refresh_all_grass_patches)
	add_child(timer)
	timer.start()

# Mesma varredura de _get_npc_at, só que no grupo "wild_sprite" (ver
# wild_sprite.gd) — grupo PRÓPRIO, separado de "npc" de propósito (ver
# comentário grande lá sobre por quê).
func get_wild_sprite_at(cell: Vector2i) -> WildSprite:
	for sprite in get_tree().get_nodes_in_group("wild_sprite"):
		if sprite.grid_pos == cell:
			return sprite
	return null

# Flood-fill 4-direcional (ortogonal, sem diagonal) sobre tiles de grama
# CONTÍGUOS a partir de `start` — pedido do usuário, resposta EXPLÍCITA à
# pergunta de esclarecimento sobre "o que conta como o mesmo grupo de
# grama": "Just the current area, and more specifically, just the ones
# from that 'group' of grass, meaning the grass patches have to be
# connected to each other" — NÃO a EncounterArea inteira (Route 1 pode ter
# várias manchas de grama separadas por caminho/água), NÃO o mapa inteiro.
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

# Todos os WildSprite cuja grid_pos cai dentro de `patch` (ver
# _get_connected_grass_patch acima) — não precisa checar área/badge/horário
# de novo, os sprites já nasceram com os filtros aplicados na hora do spawn
# (ver _refresh_grass_patch); aqui é só "quem está fisicamente nesse
# pedaço de grama agora".
func _get_wild_sprites_in_patch(patch: Array[Vector2i]) -> Array[WildSprite]:
	var patch_set: Dictionary = {}
	for cell in patch:
		patch_set[cell] = true
	var result: Array[WildSprite] = []
	for sprite in get_tree().get_nodes_in_group("wild_sprite"):
		if patch_set.has(sprite.grid_pos):
			result.append(sprite)
	return result

# Chamado por _on_player_tile_entered quando o jogador pisa em cima de um
# WildSprite — monta GameState.current_wild_group com TODOS os sprites do
# MESMO patch de grama conectada que o tocado (ver comentário grande em
# _get_connected_grass_patch, pedido EXATO do usuário), remove esses
# sprites da cena (a batalha "consome" eles — não voltam até a cena
# recarregar do zero) e dispara a troca de cena normal (ver
# _start_encounter). Mesma trava _battle_starting de sempre, pro mesmo
# motivo de qualquer outro caminho de batalha desta cena (ver comentário
# grande em is_battle_starting).
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

# source ("Grass"/"Water"/"Fishing", ver EncounterGroup.source) escrito em
# GameState.current_encounter_source ANTES de trocar de cena — é isso que
# battle.gd::spawn_enemies() lê de volta pra saber qual tabela de encontro
# usar (ver EncounterArea.pick_group). Padrão "Grass" preserva o
# comportamento de sempre pra quem chama sem passar nada (grama alta,
# trigger_wild_encounter/LootBall).
func _start_encounter(source: String = "Grass") -> void:
	if _battle_starting:
		return
	_battle_starting = true
	_reset_water_encounter_counter()
	GameState.current_encounter_source = source
	# scene_path explícito ("res://scenes/overworld/world.tscn", não um
	# default genérico) — é o que garante que uma derrota/vitória volta pra
	# CÁ (ARCHI) e não pra outra cena qualquer, mesmo princípio que
	# house_interior.gd::start_trainer_battle usa com scene_file_path.
	GameState.save_player_state(player.grid_pos, player.facing, "res://scenes/overworld/world.tscn")
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

# Wrapper público de _start_encounter() pra objetos de fora (ex: LootBall)
# dispararem uma batalha selvagem sem entrar em nenhum detalhe interno
# (_battle_starting...). Sempre "Grass" — nenhum LootBall dispara encontro
# de água ainda. Diferente de _trigger_wild_sprite_encounter (que monta
# GameState.current_wild_group a partir de um patch de sprites REAL na
# grama), aqui não existe sprite tocado nenhum — sorteia UMA espécie só (ver
# _pick_random_wild_group logo abaixo) pra imitar o "encontro surpresa" que
# esta chamada sempre representou.
func trigger_wild_encounter() -> void:
	GameState.current_wild_group = _pick_random_wild_group()
	_start_encounter()

# Usado só por trigger_wild_encounter() acima — sem sprite tocado pra formar
# um patch de verdade, sorteia UMA espécie entre as WildSpawnEntry elegíveis
# da área ATUAL do jogador (GameState.current_area), pesada por spawn_chance
# (mesmo espírito de sorteio cumulativo de EncounterArea.pick_group, só que
# por espécie individual em vez de grupo). Vazio se a área não tiver NENHUMA
# WildSpawnEntry elegível — LootBall "Battle" nessa área ficaria sem
# oponente (não deveria acontecer numa área configurada de verdade, mas
# evita travar numa batalha vazia).
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

# Chamado por Trainer._begin_battle() (ver trainer.gd) — mesmo espírito de
# house_interior.gd::start_trainer_battle, só com "res://scenes/overworld/
# world.tscn" como scene_path fixo em vez de scene_file_path (aqui SEMPRE é
# esta cena, não faz sentido genérico).
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
	GameState.current_trainer_badge_name = trainer.badge_name
	GameState.current_trainer_iq = trainer.iq
	GameState.current_trainer_starting_weather = trainer.starting_weather
	GameState.current_trainer_starting_weather_overridable = trainer.starting_weather_overridable
	GameState.generated_map = trainer.generated_map
	GameState.manual_map = trainer.manual_map
	GameState.forced_battle_tileset = trainer.forced_battle_tileset
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

# Chamado por Boss._begin_battle() (ver boss.gd) — mesmo espírito de
# start_trainer_battle() logo acima, só que preenchendo GameState.
# is_boss_battle/current_boss_entry em vez de is_trainer_battle/
# current_trainer_team (ver comentário grande dos dois em game_state.gd).
# is_trainer_battle continua false aqui de propósito: "Boss battles are
# against wild pokémon, so the player CAN catch them" — não pode passar
# pelo mesmo caminho que trava captura de time de Trainer.
func start_boss_battle(boss: Node) -> void:
	if _battle_starting:
		return
	_battle_starting = true
	get_tree().paused = false
	GameState.save_player_state(player.grid_pos, player.facing, "res://scenes/overworld/world.tscn")
	GameState.is_boss_battle = true
	GameState.current_boss_entry = boss.boss_entry
	GameState.current_boss_iq = boss.iq
	GameState.generated_map = boss.generated_map
	GameState.manual_map = boss.manual_map
	GameState.forced_battle_tileset = boss.forced_battle_tileset
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

# Delegado por player.gd::can_move_to(). Objects manda quando tem tile na
# célula (ex: uma árvore plantada em cima de grama do Ground) — só cai pro
# Ground se Objects não tiver NADA pintado ali. Célula sem tile em nenhuma
# das duas camadas conta como não-andável (mesmo critério de house_interior.
# gd: fora do mapa = parede).
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

# Custom data "water" (bool) — pedido do usuário: "Create a 'water' tag so
# I can paint the tileset with the property". Pinte "water" = true nos
# tiles de água na aba Custom Data do TileSet (mesmo lugar/mesma técnica de
# "walkable", ver assets/tiles/tilesets/OW/outside.tres). Usado por
# Player.can_move_to() (surfando, água conta como andável) e por
# _on_player_tile_entered() logo abaixo (disparar encontro selvagem de
# água, ver EncounterGroup.source == "Water").
#
# Objects OU Ground, o que tiver a marca já basta — diferente de
# is_cell_walkable, não existe "um vence o outro" aqui: água é água em
# QUALQUER das duas camadas (a maioria dos tiles de água vive no Ground,
# mas nada impede um objeto decorativo em cima de água, tipo uma ponte
# baixa, de também ser marcado).
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

# NÃO devolve a var "tile_map_ground" (onready) — mesmo motivo do comentário
# gêmeo em house_interior.gd::get_ground_tile_map(): o Player (neto de World, via
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
	if item == null:
		return
	# Fairy Ocarina (ver ItemData.opens_song_menu) precisa de uma escolha
	# (qual Song?) antes de fazer qualquer coisa — não dá pra chamar
	# GameState.use_tool() direto como o resto dos Tools (ver comentário
	# grande em use_tool() sobre por quê).
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
	# SceneTransition.is_active: ver comentário grande naquele var — sem
	# isso, abrir o menu (e pausar a árvore) bem no meio de um fade de porta
	# deixava o jogo "travado" na cena seguinte (bug reportado: "if the
	# player presses A or ESC during scene transitions the game freezes").
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

# Aberto pelo atalho de Tool direto no overworld (ver _trigger_tool_shortcut
# acima) — reusa active_menu/_on_menu_closed do mesmo jeito que
# game_menu/system_menu, então a Song escolhida (GameState.pending_song) já
# é aplicada automaticamente assim que este popup fecha, sem precisar de
# nenhum código novo pra esse caminho específico (ver
# _apply_pending_song_if_any abaixo).
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

# GameState.pending_song só é gravado (nunca aplicado na hora, ver
# comentário grande lá) tanto pelo song_menu aberto aqui em cima quanto
# pelo aberto de dentro da Bag (ver item_list_screen.gd::_open_song_menu) —
# os dois caminhos acabam passando por AQUI eventualmente: o direto assim
# que este popup fecha, o da Bag assim que o jogador termina de fechar
# TODOS os menus (Bag -> Game Menu) e volta pro overworld. A árvore já está
# DESPAUSADA nesse ponto (ver get_tree().paused = false logo acima) — só
# assim o Player consegue de fato animar o pulo/troca de sprite da Song
# (ver Player.apply_song, que depende de _process rodando).
func _apply_pending_song_if_any() -> void:
	if GameState.pending_song == "":
		return
	var song = GameState.pending_song
	GameState.pending_song = ""
	player.apply_song(song)
