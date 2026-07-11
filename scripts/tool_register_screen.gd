extends CanvasLayer

# Popup de "em qual atalho eu registro esse Tool" — aberto pela opção
# "Register" do item_action_menu (ver item_list_screen.gd::
# _open_register_screen). Mostra os 4 slots de GameState.tool_shortcuts,
# cada um com o nome do item que já ocupa (ou "-- vazio --"); confirmar num
# slot registra ali (sobrescrevendo o que estivesse, ver GameState.
# register_tool) e fecha. Mesmo padrão de navegação/mouse do resto do
# projeto (setas + X confirma + Z cancela sem registrar nada).
#
# Lista de UM nível só (diferente de unit_loadout.gd, que tem ROWS + PICKING
# — aqui não precisa da segunda camada porque não existe "abrir um sub-menu
# de opções dentro do slot", é só "escolher qual dos 4" e pronto).

signal closed

@onready var title_label: Label = $Box/Panel/MarginContainer/Content/Title
@onready var rows_container: VBoxContainer = $Box/Panel/MarginContainer/Content/Rows

var item: ItemData
var row_labels: Array[Label] = []
var selected_row: int = 0

func setup(tool_item: ItemData) -> void:
	item = tool_item
	title_label.text = "Registrar %s em qual atalho?" % item.action_name
	_build_rows()
	_refresh_rows()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _build_rows() -> void:
	for i in GameState.TOOL_SHORTCUT_COUNT:
		var label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_row_mouse_entered.bind(i))
		label.gui_input.connect(_on_row_gui_input.bind(i))
		rows_container.add_child(label)
		row_labels.append(label)

func _refresh_rows() -> void:
	for i in GameState.TOOL_SHORTCUT_COUNT:
		var slot_item: ItemData = GameState.tool_shortcuts[i]
		var text = slot_item.action_name if slot_item != null else "-- vazio --"
		row_labels[i].text = "%d. %s" % [i + 1, text]
		row_labels[i].modulate = Color.YELLOW if i == selected_row else Color.WHITE

func _on_row_mouse_entered(index: int) -> void:
	selected_row = index
	_refresh_rows()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_row = index
		_confirm_selected()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		selected_row = wrapi(selected_row + 1, 0, GameState.TOOL_SHORTCUT_COUNT)
		_refresh_rows()
	elif event.is_action_pressed("ui_up"):
		selected_row = wrapi(selected_row - 1, 0, GameState.TOOL_SHORTCUT_COUNT)
		_refresh_rows()
	elif event.is_action_pressed("confirm"):
		_confirm_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _confirm_selected() -> void:
	GameState.register_tool(item, selected_row)
	_close()

func _close() -> void:
	closed.emit()
	queue_free()
