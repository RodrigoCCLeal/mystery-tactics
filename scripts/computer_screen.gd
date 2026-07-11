extends CanvasLayer

# Tela do "Computador" — acessível pelo menu de pausa (ver pause_menu.gd::
# _open_computer_screen). Uma opção: "PC" abre pc_screen.tscn (troca de
# unidades entre time ativo e reserva) como sub-tela, escondendo-se por
# baixo — mesmo padrão de esconder/reaparecer usado em pause_menu.gd/
# party_screen.gd pra sub-menus.
#
# "Heal" existia aqui só pra debug (curar o time sem precisar achar a Nurse)
# e foi removido agora que existe um jeito de verdade, dentro da ficção, de
# curar (ver nurse.gd — falar com o NPC "Nurse" no overworld). GameState.
# heal_active_roster() continua existindo, só que quem chama agora é
# nurse.gd, não mais esta tela.
#
# Mesma estrutura de navegação de pause_menu.gd/slot_action_menu.gd: setas
# trocam a opção, X confirma, Z ou Esc fecha; mouse funciona em paralelo.

signal closed

const OPTIONS = ["PC"]
const PC_SCREEN_SCENE: PackedScene = preload("res://scenes/pc_screen.tscn")

@onready var header_label: Label = $Center/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
var selected_index: int = 0

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

# Mesmo motivo do "if not visible: return" em pause_menu.gd — enquanto
# pc_screen está aberta por cima (this hide()-ado), não processa input.
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
	match OPTIONS[selected_index]:
		"PC":
			_open_pc_screen()

func _open_pc_screen() -> void:
	hide()
	var screen = PC_SCREEN_SCENE.instantiate()
	add_child(screen)
	# pc_screen.gd já faz queue_free() em si mesmo ao fechar — só precisamos
	# reaparecer (mesmo padrão de pause_menu.gd::_open_party_screen).
	screen.closed.connect(show)

func _close() -> void:
	closed.emit()
	queue_free()
