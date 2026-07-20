extends CanvasLayer

# Popup da Fairy Ocarina (ver item_data.gd::opens_song_menu) — mostra as
# Songs que o jogador já desbloqueou (ver GameState.get_unlocked_songs) e
# guarda a escolha em GameState.pending_song. Mesmo esqueleto de
# tool_register_screen.gd (lista de 1 nível só, setas + X confirma + Z
# cancela), com ícone + nome por linha igual merchant_buy_screen.gd/
# item_list_screen.gd em vez do Label puro de tool_register_screen.gd — o
# usuário pediu pra MOSTRAR as Songs, não só listar texto.
#
# NÃO aplica o efeito da Song aqui dentro — este popup pode abrir tanto de
# dentro da Bag (vários CanvasLayers de distância de World/HouseInterior,
# sem acesso nenhum ao node Player de verdade) quanto direto de um atalho
# de Tool no overworld. Só GRAVA a escolha (GameState.pending_song); quem
# aplica de verdade é world.gd/house_interior.gd::_apply_pending_song_if_any,
# chamado assim que TODOS os menus acabam de fechar (ver comentário grande
# em GameState.pending_song).

signal closed

const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)
const ICON_SIZE = 24.0

# "Fly" já entra na lista (ver GameState.SONG_NAMES) mesmo sem efeito
# nenhum implementado ainda em Player.apply_song() — só o ÍCONE já existe
# (Bag_Fly_Ocarina.png), então já mostramos ele aqui; selecionar "Fly" por
# enquanto simplesmente não faz nada (ver comentário grande em
# Player.apply_song sobre "Fly we will implement at another time").
const SONG_ICONS = {
	"Strength": preload("res://assets/sprites/items/Tool/Songs/Bag_Strength_Ocarina.png"),
	"Surf": preload("res://assets/sprites/items/Tool/Songs/Bag_Surf_Ocarina.png"),
	"Fly": preload("res://assets/sprites/items/Tool/Songs/Bag_Fly_Ocarina.png"),
}

@onready var title_label: Label = $Box/Panel/MarginContainer/Content/Title
@onready var rows_container: VBoxContainer = $Box/Panel/MarginContainer/Content/Rows

var songs: Array[String] = []
var row_panels: Array[PanelContainer] = []
var selected_row: int = 0

func setup(item: ItemData) -> void:
	title_label.text = "%s: qual Song?" % item.action_name
	songs = GameState.get_unlocked_songs()
	_build_rows()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _build_rows() -> void:
	if songs.is_empty():
		var empty_label := Label.new()
		empty_label.text = "-- nenhuma Song aprendida --"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows_container.add_child(empty_label)
		return
	for i in songs.size():
		var panel = _build_row(songs[i], i)
		rows_container.add_child(panel)
		row_panels.append(panel)
	_update_row_visuals()

func _build_row(song_name: String, index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = ROW_STYLE_NORMAL
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(_on_row_mouse_entered.bind(index))
	panel.gui_input.connect(_on_row_gui_input.bind(index))

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var icon_texture: Texture2D = SONG_ICONS.get(song_name)
	if icon_texture != null:
		var icon = TextureRect.new()
		icon.texture = icon_texture
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var name_label = Label.new()
	name_label.text = song_name
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	return panel

func _update_row_visuals() -> void:
	for i in row_panels.size():
		var style = row_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = ROW_STYLE_SELECTED if i == selected_row else ROW_STYLE_NORMAL

func _on_row_mouse_entered(index: int) -> void:
	selected_row = index
	_update_row_visuals()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_row = index
		_confirm_selected()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_confirm_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	if songs.is_empty():
		return
	selected_row = wrapi(selected_row + step, 0, songs.size())
	_update_row_visuals()

func _confirm_selected() -> void:
	if songs.is_empty():
		return
	GameState.pending_song = songs[selected_row]
	_close()

func _close() -> void:
	closed.emit()
	queue_free()
