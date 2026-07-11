extends CanvasLayer

# Popup de "quantas unidades desse item eu vou dar" — aberto só quando faz
# sentido escolher (ver item_list_screen.gd::_on_party_target_picked: item
# Stackable, ver ItemData.stackable, E o jogador tem mais de 1; com só 1
# disponível não há escolha nenhuma, dar 1 é automático). Mesmo padrão de
# popup do resto do projeto (CanvasLayer + Dim + Center + Panel, setas +
# X confirma + Z cancela, mouse em paralelo — ver quit_confirm.gd) — só que
# em vez de opções de texto, o valor muda com esquerda/direita.
#
# closed(amount) — amount == -1 é o sentinela de "cancelado" (equivalente
# ao "" que os popups de opção de texto usam pra cancelar), já que qualquer
# quantidade de verdade escolhida aqui é sempre >= 1.

signal closed(amount: int)

@onready var header_label: Label = $Center/Panel/MarginContainer/Content/Header
@onready var amount_label: Label = $Center/Panel/MarginContainer/Content/AmountRow/AmountLabel
@onready var minus_label: Label = $Center/Panel/MarginContainer/Content/AmountRow/Minus
@onready var plus_label: Label = $Center/Panel/MarginContainer/Content/AmountRow/Plus
@onready var confirm_label: Label = $Center/Panel/MarginContainer/Content/Confirm

var min_amount: int = 1
var max_amount: int = 99
var amount: int = 1

func setup(item_name: String, initial_max: int) -> void:
	header_label.text = "Quantas %s?" % item_name
	max_amount = max(min_amount, initial_max)
	amount = min_amount
	_update_amount_label()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for label in [minus_label, plus_label, confirm_label]:
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	minus_label.gui_input.connect(_on_minus_gui_input)
	plus_label.gui_input.connect(_on_plus_gui_input)
	confirm_label.gui_input.connect(_on_confirm_gui_input)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_change_amount(-1)
	elif event.is_action_pressed("ui_right"):
		_change_amount(1)
	elif event.is_action_pressed("confirm"):
		_finish(amount)
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_finish(-1)
	else:
		return
	get_viewport().set_input_as_handled()

func _change_amount(step: int) -> void:
	amount = clampi(amount + step, min_amount, max_amount)
	_update_amount_label()

func _update_amount_label() -> void:
	amount_label.text = str(amount)

func _on_minus_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_change_amount(-1)

func _on_plus_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_change_amount(1)

func _on_confirm_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish(amount)

func _finish(result: int) -> void:
	closed.emit(result)
	queue_free()
