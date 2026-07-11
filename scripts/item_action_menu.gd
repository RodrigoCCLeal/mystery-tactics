extends CanvasLayer

# Popup pequeno que abre ao selecionar um item na Bag (ver
# item_list_screen.gd::_open_item_actions) — mesmo padrão de
# slot_action_menu.gd (setas + X confirma + Z cancela, mouse em paralelo,
# um sinal só "closed(option)" pra evitar ordem de eventos ruim). "" como
# option significa "cancelado", sem opção nenhuma escolhida.
#
# Diferente de slot_action_menu.gd, as opções NÃO são fixas: cada item
# decide quais tem (ver ItemData.can_use/can_give/can_register) — Potion só
# tem Use, Focus Band só tem Give, Oran Berry tem as duas, Bicycle tem Use
# E Register. setup() monta os Labels em código por causa disso, em vez de
# vir prontos da cena.
#
# "Register"/"Unregister" são a MESMA entrada de can_register — o texto
# muda sozinho dependendo se o item já ocupa um atalho ou não (ver
# GameState.is_item_registered), então nunca aparecem as duas ao mesmo
# tempo.

signal closed(option: String)

@onready var header_label: Label = $Box/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Box/Panel/MarginContainer/Options

var options: Array[String] = []
var option_labels: Array[Label] = []
var selected_index: int = 0

func setup(item: ItemData) -> void:
	header_label.text = item.action_name.to_upper()
	if item.can_use:
		options.append("Use")
	if item.can_give:
		options.append("Give")
	if item.can_register:
		options.append("Unregister" if GameState.is_item_registered(item) else "Register")
	for option in options:
		var label = Label.new()
		label.text = option
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var index = option_labels.size()
		label.mouse_entered.connect(_on_option_mouse_entered.bind(index))
		label.gui_input.connect(_on_option_gui_input.bind(index))
		options_container.add_child(label)
		option_labels.append(label)
	_update_selection_visual()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if options.is_empty():
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_confirm_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_finish("")
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, options.size())
	_update_selection_visual()

func _on_option_mouse_entered(index: int) -> void:
	selected_index = index
	_update_selection_visual()

func _on_option_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_confirm_selected()

func _confirm_selected() -> void:
	_finish(options[selected_index])

func _finish(option: String) -> void:
	closed.emit(option)
	queue_free()

func _update_selection_visual() -> void:
	for i in option_labels.size():
		option_labels[i].modulate = Color.YELLOW if i == selected_index else Color.WHITE
