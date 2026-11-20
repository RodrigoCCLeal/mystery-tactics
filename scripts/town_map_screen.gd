extends CanvasLayer

# Tela do mapa de Tactica. Abre de dois jeitos (ver os dois modos abaixo):
#
#   VIEW    — o jogador usou o item Town Map na Bag (ver
#             item_list_screen.gd). Só mostra onde ele está. Com a Song
#             "Fly" da Fairy Ocarina, dá pra clicar numa cidade já
#             visitada e voar até ela de graça.
#   ARRIVAL — o jogador passou por uma porta que levaria a uma cidade-
#             menu (cidade vermelha ou vilarejo azul — Door.opens_town_map,
#             ver house_interior.gd::use_door). Elas não são andáveis: o
#             indicador vai pra lá e o painel da direita mostra as opções
#             (Pokémon Center, Poké Mart, CityOptions). Pra sair, o jogador
#             clica numa rota vizinha no mapa.
#
# Em qualquer modo, Z/Esc fecha a tela e o jogador continua EXATAMENTE onde
# estava (na frente da porta, ou com a Bag aberta). Nada muda de cena até o
# jogador escolher uma opção ou um vizinho — por isso cancelar é só fechar.
#
# Uso:
#   var map = TOWN_MAP_SCENE.instantiate()
#   add_child(map)
#   map.open_arrival("wushu")   # ou map.open_view()
#   map.closed.connect(...)

signal closed

const MAP_DATA: TacticaMapData = preload("res://data/map/tactica_map.tres")
const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")
const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")
# "!.png" é a spritesheet da animação de exclamação (ver
# exclamation_mark.tscn) — usamos só o ÚLTIMO quadro (o "!" completo).
const EXCLAMATION_SHEET: Texture2D = preload("res://assets/sprites/effects/!.png")
const EXCLAMATION_REGION := Rect2(384, 0, 192, 171)
const ClockIcon = preload("res://scripts/clock_icon.gd")

const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)
const TIME_FADE_DURATION = 0.4

enum Mode { VIEW, ARRIVAL }

# Tamanho do mapa na tela = tamanho da imagem x map_scale.
@export var map_scale: float = 0.76

@onready var map_view: TextureRect = $MapView
@onready var indicator: Control = $MapView/Indicator
@onready var balloon: PanelContainer = $Balloon
@onready var balloon_label: Label = $Balloon/Label
@onready var title_label: Label = $SidePanel/Margin/Content/Title
@onready var subtitle_label: Label = $SidePanel/Margin/Content/Subtitle
@onready var rows_container: VBoxContainer = $SidePanel/Margin/Content/Rows
@onready var hint_label: Label = $SidePanel/Margin/Content/Hint

var mode: Mode = Mode.VIEW
# Onde o indicador está desenhado agora. Em ARRIVAL é a cidade da porta (o
# jogador ainda está fisicamente na cena de antes — GameState.
# current_location_id só muda quando ele de fato troca de cena).
var here_id: String = ""
# true = entramos em ARRIVAL voando a partir do modo VIEW; Z/Esc volta pro
# VIEW em vez de fechar tudo (cancela o voo).
var flew_from_view: bool = false
var hovered: MapLocation = null
# true enquanto um popup (mensagem/sim-não) ou uma transição está rolando —
# a tela ignora input nesse meio-tempo.
var _busy: bool = false

# Máscara do shader (ver assets/shaders/town_map.gdshader): 1 pixel por célula.
var _mask_image: Image
var _mask_texture: ImageTexture

# Linhas do painel da cidade: cada uma é um Dictionary
# {"label": String, "kind": "center"/"mart"/"option", "option": CityOption}.
var rows: Array[Dictionary] = []
var row_panels: Array[PanelContainer] = []
var selected_row: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	balloon.hide()
	var tex_size := MAP_DATA.texture.get_size()
	map_view.texture = MAP_DATA.texture
	map_view.size = tex_size * map_scale
	_mask_image = Image.create(MAP_DATA.grid_size.x, MAP_DATA.grid_size.y, false, Image.FORMAT_RGBA8)
	_mask_texture = ImageTexture.create_from_image(_mask_image)
	var mat := map_view.material as ShaderMaterial
	mat.set_shader_parameter("cell_mask", _mask_texture)
	mat.set_shader_parameter("tex_size", tex_size)
	mat.set_shader_parameter("grid_origin", MAP_DATA.grid_origin)
	mat.set_shader_parameter("cell_size", float(MAP_DATA.cell_size))
	mat.set_shader_parameter("grid_size", Vector2(MAP_DATA.grid_size))
	map_view.gui_input.connect(_on_map_gui_input)
	map_view.mouse_exited.connect(_set_hovered.bind(null))

# ---------- Abrir ----------

func open_view() -> void:
	mode = Mode.VIEW
	flew_from_view = false
	here_id = GameState.current_location_id
	_refresh_all()

func open_arrival(city_id: String) -> void:
	var city := MAP_DATA.get_location(city_id)
	if city == null or not city.is_menu_town():
		push_warning("Town Map: '%s' não é uma cidade/vilarejo do mapa — abrindo no modo VIEW." % city_id)
		open_view()
		return
	mode = Mode.ARRIVAL
	here_id = city_id
	# "Um local é visitado assim que o jogador chega nele pela primeira vez."
	GameState.mark_location_visited(city_id)
	_refresh_all()

func _refresh_all() -> void:
	_refresh_mask()
	_place_indicator()
	_build_panel()

# ---------- Mapa: máscara, indicador, hover ----------

func _refresh_mask() -> void:
	_mask_image.fill(Color(0, 0, 0, 1))
	for loc in MAP_DATA.locations:
		var grey := 0.0 if GameState.is_location_visited(loc.id) else 1.0
		var hover := 1.0 if loc == hovered else 0.0
		for cell in loc.cells:
			_mask_image.set_pixelv(cell, Color(grey, hover, 0, 1))
	_mask_texture.update(_mask_image)

func _place_indicator() -> void:
	var loc := MAP_DATA.get_location(here_id)
	indicator.visible = loc != null
	if loc != null:
		indicator.position = MAP_DATA.cell_to_pixel(loc.get_center_cell()) * map_scale

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := MAP_DATA.pixel_to_cell(event.position / map_scale)
		_set_hovered(MAP_DATA.get_location_at_cell(cell))
		_move_balloon(map_view.global_position + event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hovered != null:
			_on_location_clicked(hovered)
			map_view.accept_event()

func _set_hovered(loc: MapLocation) -> void:
	if loc == hovered:
		return
	hovered = loc
	_refresh_mask()
	if loc == null:
		balloon.hide()
		map_view.mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	balloon_label.text = loc.get_display_name(GameState.is_location_visited(loc.id))
	balloon.reset_size()
	balloon.show()
	map_view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _is_clickable(loc) else Control.CURSOR_ARROW

# Balão um pouco acima e à direita do mouse, sem sair da tela.
func _move_balloon(mouse_pos: Vector2) -> void:
	var screen := balloon.get_viewport_rect().size
	var pos := mouse_pos + Vector2(14, -balloon.size.y - 10)
	pos.x = clampf(pos.x, 4.0, screen.x - balloon.size.x - 4.0)
	pos.y = clampf(pos.y, 4.0, screen.y - balloon.size.y - 4.0)
	balloon.position = pos

# ---------- Cliques no mapa ----------

func _is_neighbor_of_here(loc: MapLocation) -> bool:
	if mode != Mode.ARRIVAL:
		return false
	var here := MAP_DATA.get_location(here_id)
	return here != null and here.neighbors.has(loc.id)

func _can_fly_to(loc: MapLocation) -> bool:
	return GameState.has_fly() and loc.is_menu_town() and loc.id != here_id \
		and GameState.is_location_visited(loc.id)

func _is_clickable(loc: MapLocation) -> bool:
	return _is_neighbor_of_here(loc) or _can_fly_to(loc)

func _on_location_clicked(loc: MapLocation) -> void:
	if _busy or loc.id == here_id:
		return
	# Sair daqui (rota vizinha ou Fly) pode estar travado por uma flag (ver
	# MapLocation.exit_required_flag — ex: Kano sem starter escolhido).
	if (_is_neighbor_of_here(loc) or _can_fly_to(loc)) and not _can_leave_here():
		return
	if _is_neighbor_of_here(loc):
		if loc.is_menu_town():
			# Duas cidades-menu ligadas direto (sem rota no meio) — hoje não
			# existe nenhuma no mapa, mas se existir, é só mudar de menu.
			_go_to_city(loc.id)
		else:
			_travel_to(loc)
	elif _can_fly_to(loc):
		_ask_fly(loc)

# false = sair daqui está travado; já mostra a mensagem do bloqueio.
func _can_leave_here() -> bool:
	var here := MAP_DATA.get_location(here_id)
	if here == null or here.can_leave():
		return true
	_show_message(here.exit_blocked_message if here.exit_blocked_message != "" else "Você ainda não pode sair daqui.")
	return false

func _ask_fly(loc: MapLocation) -> void:
	_busy = true
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	prompt.layer = layer + 1
	add_child(prompt)
	prompt.setup("Tocar Fly e voar para %s?" % loc.get_display_name(true))
	var yes: bool = await prompt.answered
	_busy = false
	if not yes:
		return
	if mode == Mode.VIEW:
		flew_from_view = true
	_go_to_city(loc.id)

func _go_to_city(city_id: String) -> void:
	mode = Mode.ARRIVAL
	here_id = city_id
	GameState.mark_location_visited(city_id)
	_refresh_all()

# Sai da cidade pra um lugar andável vizinho (rota, vilarejo, ponto especial).
func _travel_to(loc: MapLocation) -> void:
	if loc.scene_path == "" or not ResourceLoader.exists(loc.scene_path):
		_show_message("Esse caminho ainda está em construção.")
		return
	var entry := loc.get_entry_from(here_id)
	if entry == null:
		push_warning("Town Map: '%s' não tem MapEntryPoint vindo de '%s' (ver entry_points)." % [loc.id, here_id])
		_show_message("Esse caminho ainda está em construção.")
		return
	GameState.mark_location_visited(here_id)
	GameState.set_current_location(loc.id)
	_change_scene(loc.scene_path, entry.grid_pos, entry.facing)

func _change_scene(scene_path: String, grid_pos: Vector2i, facing: String) -> void:
	_busy = true
	GameState.save_player_state(grid_pos, facing, scene_path)
	SceneTransition.change_scene_with_fade(scene_path)

# ---------- Painel da direita ----------

func _build_panel() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	rows.clear()
	row_panels.clear()
	var hints: Array[String] = []
	if mode == Mode.ARRIVAL:
		var city := MAP_DATA.get_location(here_id)
		title_label.text = city.get_display_name(true)
		subtitle_label.text = "Cidade" if city.is_city() else "Vilarejo"
		if city.has_pokemon_center:
			rows.append({"label": "Pokémon Center", "kind": "center"})
		if city.has_poke_mart:
			rows.append({"label": "Poké Mart", "kind": "mart"})
		for option in city.options:
			if option != null and option.is_available():
				rows.append({"label": option.label, "kind": "option", "option": option})
		if rows.is_empty():
			rows_container.add_child(_build_empty_label())
		hints.append("Clique numa rota vizinha no mapa para sair daqui.")
	else:
		title_label.text = "Town Map"
		var here := MAP_DATA.get_location(here_id)
		subtitle_label.text = "Você está em: %s" % (here.get_display_name(true) if here != null else "???")
	if GameState.has_fly():
		hints.append("Fly: clique numa cidade ou vilarejo já visitado para voar até lá.")
	hints.append("Z / Esc: voltar" if flew_from_view else "Z / Esc: fechar")
	hint_label.text = "\n".join(hints)
	for i in rows.size():
		var panel := _build_row(rows[i], i)
		rows_container.add_child(panel)
		row_panels.append(panel)
	selected_row = clampi(selected_row, 0, maxi(rows.size() - 1, 0))
	_update_row_visuals()

func _build_empty_label() -> Label:
	var label := Label.new()
	label.text = "Nada para fazer aqui ainda."
	label.modulate = Color(0.7, 0.7, 0.7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _build_row(row: Dictionary, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ROW_STYLE_NORMAL
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(_on_row_mouse_entered.bind(index))
	panel.gui_input.connect(_on_row_gui_input.bind(index))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)
	var label := Label.new()
	label.text = row["label"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	var option: CityOption = row.get("option")
	if option != null:
		if option.shows_news(here_id):
			var atlas := AtlasTexture.new()
			atlas.atlas = EXCLAMATION_SHEET
			atlas.region = EXCLAMATION_REGION
			var news := TextureRect.new()
			news.texture = atlas
			news.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			news.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			news.custom_minimum_size = Vector2(20, 20)
			news.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(news)
		if option.advances_time:
			hbox.add_child(ClockIcon.new())
	return panel

func _update_row_visuals() -> void:
	for i in row_panels.size():
		var style := row_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = ROW_STYLE_SELECTED if i == selected_row else ROW_STYLE_NORMAL

func _on_row_mouse_entered(index: int) -> void:
	selected_row = index
	_update_row_visuals()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_row = index
		_activate_selected_row()

func _activate_selected_row() -> void:
	if _busy or rows.is_empty():
		return
	var row: Dictionary = rows[selected_row]
	match row["kind"]:
		"center":
			_enter_shared_building("Pokémon Center", MAP_DATA.pokemon_center_scene, MAP_DATA.pokemon_center_entry, MAP_DATA.pokemon_center_facing)
		"mart":
			_enter_shared_building("Poké Mart", MAP_DATA.poke_mart_scene, MAP_DATA.poke_mart_entry, MAP_DATA.poke_mart_facing)
		"option":
			_run_city_option(row["option"])

# Pokémon Center/Poké Mart: mapa único. GameState.current_location_id = a
# cidade de onde o jogador entrou — a porta de saída desses mapas
# (Door.opens_town_map, town_map_location_id vazio) reabre o mapa nela.
func _enter_shared_building(building_name: String, scene_path: String, grid_pos: Vector2i, facing: String) -> void:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		_show_message("O %s ainda está em construção." % building_name)
		return
	GameState.set_current_location(here_id)
	_change_scene(scene_path, grid_pos, facing)

func _run_city_option(option: CityOption) -> void:
	_busy = true
	if option.is_news:
		GameState.set_flag(option.get_news_flag(here_id))
	if option.advances_time:
		await SceneTransition.fade_to(1.0, TIME_FADE_DURATION)
		GameState.advance_to_next_time_of_day()
		await get_tree().create_timer(TIME_FADE_DURATION).timeout
		await SceneTransition.fade_to(0.0, TIME_FADE_DURATION)
	if option.message != "":
		await _show_message_async(option.message)
	if option.action == CityOption.Action.ENTER_SCENE:
		if option.scene_path != "" and ResourceLoader.exists(option.scene_path):
			GameState.set_current_location(here_id)
			_change_scene(option.scene_path, option.grid_pos, option.facing)
			return
		await _show_message_async("Esse lugar ainda está em construção.")
	_busy = false
	# O tempo pode ter mudado (opções de tempo limitado) e a exclamação some
	# depois do primeiro uso — reconstrói as linhas.
	_build_panel()

# ---------- Mensagens ----------

func _show_message(text: String) -> void:
	_busy = true
	await _show_message_async(text)
	_busy = false

func _show_message_async(text: String) -> void:
	var box = MESSAGE_BOX_SCENE.instantiate()
	box.layer = layer + 1
	add_child(box)
	box.setup(text)
	await box.closed

# ---------- Teclado ----------

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_activate_selected_row()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_go_back()
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	if rows.is_empty():
		return
	selected_row = wrapi(selected_row + step, 0, rows.size())
	_update_row_visuals()

func _go_back() -> void:
	if flew_from_view:
		open_view()
		return
	closed.emit()
	queue_free()
