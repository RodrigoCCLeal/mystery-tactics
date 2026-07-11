extends CanvasLayer

# Popup de confirmação antes de fechar o jogo de vez (ver pause_menu.gd::
# _open_quit_confirm — a opção "Exit" do menu de pausa abre isso em vez de
# só fechar o menu, que já é o que Z faz). Mesmo padrão de navegação do
# resto do projeto (setas + X confirma + Z cancela, mouse em paralelo).
#
# selected_index começa em "Não" (índice 1) de propósito — sair do jogo é
# uma ação destrutiva (perde todo progresso da sessão, não existe save
# ainda), então o cursor não deve começar em cima da opção que sai.

signal closed

const OPTIONS = ["Sim", "Não"]

@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
var selected_index: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in options_container.get_children():
		if child is Label and child.name != "Header":
			option_labels.append(child)
	for i in option_labels.size():
		var label := option_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_option_mouse_entered.bind(i))
		label.gui_input.connect(_on_option_gui_input.bind(i))
	_update_selection_visual()

func _unhandled_input(event: InputEvent) -> void:
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
	selected_index = wrapi(selected_index + step, 0, OPTIONS.size())
	_update_selection_visual()

func _on_option_mouse_entered(index: int) -> void:
	selected_index = index
	_update_selection_visual()

func _on_option_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_activate_selected()

func _update_selection_visual() -> void:
	for i in option_labels.size():
		option_labels[i].modulate = Color.YELLOW if i == selected_index else Color.WHITE

func _activate_selected() -> void:
	if OPTIONS[selected_index] == "Sim":
		get_tree().quit()
	else:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
