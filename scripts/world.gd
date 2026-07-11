extends Node2D

# Encontros aleatórios: cada passo dado em cima de um tile de grama alta
# conta pra um contador regressivo sorteado (entre MIN/MAX_ENCOUNTER_STEPS)
# — quando ele chega a 0, a batalha começa. É o mesmo princípio dos jogos
# Pokémon clássicos (probabilidade por passo), só que expresso como "só sei
# depois de quantos passos" em vez de "checa uma chance % a cada passo" —
# mais fácil de prever/testar, e foi assim que o usuário pediu.

@onready var tile_map: TileMapLayer = $TileMapLayer
# Player (e qualquer Npc, ver npc.gd) mora dentro de "Actors" (Node2D com
# y_sort_enabled = true) em vez de direto em World — é isso que resolve o
# personagem "atravessando por baixo" de um NPC (ou vice-versa): dentro de um
# nó com y_sort_enabled, o Godot desenha os filhos ordenados pela posição Y
# de cada um (quem está mais embaixo na tela desenha por CIMA), em vez da
# ordem fixa em que aparecem na árvore. TileMapLayer/TreeTopLayer ficam DE
# FORA desse grupo de propósito — o chão deve continuar sempre atrás de
# tudo, e o topo das árvores sempre na frente (z_index=1), não faz sentido
# nenhum deles competirem por posição Y com os personagens.
@onready var player: Node2D = $Actors/Player
@onready var area_notification: CanvasLayer = $AreaNotification

const GRASS_RUSTLE_SCENE: PackedScene = preload("res://scenes/grass_rustle.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/pause_menu.tscn")

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
# Inspector pra essa instância de World, assim uma área diferente no futuro
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

	var in_grass = _is_tall_grass(cell)
	player.set_sunk_in_grass(in_grass)

	if not in_grass:
		return

	_spawn_grass_rustle(cell)

	steps_until_encounter -= 1
	if steps_until_encounter <= 0:
		_start_encounter()

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

func _reset_encounter_counter() -> void:
	steps_until_encounter = randi_range(MIN_ENCOUNTER_STEPS, MAX_ENCOUNTER_STEPS)

# Guarda onde o personagem está (pra devolver ele aqui quando a batalha
# acabar — GameState sobrevive à troca de cena) e troca pra batalha.
# change_scene_to_file() descarta o World inteiro. O caminho de volta
# (batalha -> overworld) ainda não existe — batle.gd não tem um fim de
# batalha implementado ainda (vitória/derrota/fuga); quando tiver, é lá que
# vamos chamar change_scene_to_file(GameState.overworld_scene_path).
func _start_encounter() -> void:
	_reset_encounter_counter()
	GameState.save_player_state(player.grid_pos, player.facing)
	# GameState.current_area já foi setado em _enter_area() (rodou no
	# _ready() desta cena) — não precisa repetir aqui.
	get_tree().change_scene_to_file("res://scenes/battle.tscn")

# Esc abre o menu de pausa (ver pause_menu.gd). get_tree().paused = true
# congela Player e World de graça — process_mode padrão (PROCESS_MODE_
# INHERIT) faz qualquer node parar de rodar _process/_input enquanto a
# árvore está pausada, sem precisar desligar o Player manualmente. O menu
# em si roda com PROCESS_MODE_ALWAYS (ver pause_menu.gd), então continua
# recebendo input normalmente mesmo com o jogo pausado.
#
# 1/2/3/4 (action_slot_1..4) usam um Tool registrado direto, sem abrir a Bag
# (ver GameState.tool_shortcuts/register_tool) — as MESMAS actions que
# battle.gd usa pros slots de ataque 1-6, só que aqui (overworld) só as 4
# primeiras têm sentido, e o efeito é completamente diferente (usar um Tool,
# não uma ação de batalha). Não há conflito: World e Battle nunca rodam ao
# mesmo tempo (uma troca a outra via change_scene_to_file), cada script só
# escuta essas actions na sua própria cena.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_open_pause_menu()
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

func _open_pause_menu() -> void:
	var menu = PAUSE_MENU_SCENE.instantiate()
	add_child(menu)
	menu.closed.connect(_on_pause_menu_closed)
	get_tree().paused = true

# "Exit" no menu (ou Z/Esc a qualquer momento) só fecha o menu — quem
# despausa o jogo de verdade é aqui, escutando o sinal "closed".
func _on_pause_menu_closed() -> void:
	get_tree().paused = false
