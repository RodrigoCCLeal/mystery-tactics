extends CanvasLayer

# Popup "Buy/Sell" que abre ao falar com um Merchant (ver merchant.gd::
# interact()) — MESMA estrutura de bag_screen.gd (não slot_action_menu.gd):
# escolher uma opção não fecha este popup na hora, ele se esconde (hide()) e
# abre a subtela (Buy ou Sell) por cima; quando a subtela fecha sozinha
# (queue_free), este menu reaparece (show()) pra escolher de novo ou sair.
# Só Z/cancelar de fato fecha (queue_free + emite "closed" pro merchant.gd
# destravar o Player). Não tem opção "Leave" explícita na lista por isso —
# cancelar já é a forma de sair (mesma convenção do resto do projeto).

signal closed

const BUY_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/merchant_buy_screen.tscn")
const SELL_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/merchant_sell_screen.tscn")

const OPTIONS = ["Buy", "Sell"]

@onready var header_label: Label = $Center/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
var selected_index: int = 0
var merchant: Node = null

func setup(shop_name: String, merchant_ref: Node) -> void:
	header_label.text = shop_name
	merchant = merchant_ref

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in options_container.get_children():
		if child is Label and child != header_label:
			option_labels.append(child)
	for i in option_labels.size():
		var label := option_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_option_mouse_entered.bind(i))
		label.gui_input.connect(_on_option_gui_input.bind(i))
	_update_selection_visual()

# Mesmo guard de bag_screen.gd — enquanto Buy/Sell está aberta por cima
# (this hide()-ado), não processa input nenhum.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_activate_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, option_labels.size())
	_update_selection_visual()

func _on_option_mouse_entered(index: int) -> void:
	selected_index = index
	_update_selection_visual()

func _on_option_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_activate_selected()

func _activate_selected() -> void:
	match OPTIONS[selected_index]:
		"Buy":
			_open_buy_screen()
		"Sell":
			_open_sell_screen()

func _open_buy_screen() -> void:
	hide()
	var screen = BUY_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(merchant.stock)
	screen.closed.connect(show)

func _open_sell_screen() -> void:
	hide()
	var screen = SELL_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup()
	screen.closed.connect(show)

func _close() -> void:
	closed.emit()
	queue_free()

func _update_selection_visual() -> void:
	for i in option_labels.size():
		option_labels[i].modulate = Color.YELLOW if i == selected_index else Color.WHITE
