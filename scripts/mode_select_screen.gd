extends CanvasLayer

# Passo novo entre escolher o nome (name_entry_screen.gd) e de fato criar o
# save — pedido do usuário: "Let's add 3 options when creating a new save
# file: Normal / Debugger / Challenge" (ver comentário grande em
# GameState.game_mode pro que cada um muda). Mesmo padrão de navegação
# (setas + X confirma, mouse em paralelo, Z/Esc volta) que title_screen.gd/
# save_slot_screen.gd já usam — aqui os "options" são 3 Labels FIXOS do
# .tscn (mesmo esquema simples de title_screen.gd, não construídos em
# código como save_slot_screen.gd, porque a lista nunca muda de tamanho).

signal closed

# Ordem tem que bater exatamente com a ordem dos Labels dentro de
# Center/Panel/MarginContainer/Content/Options no .tscn — option_labels
# abaixo é preenchido na mesma ordem em que _ready() encontra os children,
# e MODE_KEYS[i] precisa ser o modo certo pro Label options_container.
# get_children()[i]. Debugger por ÚLTIMO de propósito (pedido do usuário:
# "we will remove debugger on the final release") — quando esse dia
# chegar, basta apagar o último Label do .tscn e a última string daqui,
# sem precisar reordenar mais nada.
const MODE_KEYS = ["normal", "challenge", "debugger"]

@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Options

var target_slot: int = -1
var chosen_name: String = ""
var option_labels: Array[Label] = []
var selected_index: int = 0

func setup(slot: int, name_: String) -> void:
	target_slot = slot
	chosen_name = name_

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in options_container.get_children():
		if child is Label:
			var idx = option_labels.size()
			option_labels.append(child)
			child.mouse_filter = Control.MOUSE_FILTER_STOP
			child.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			child.mouse_entered.connect(_on_option_mouse_entered.bind(idx))
			child.gui_input.connect(_on_option_gui_input.bind(idx))
	_update_selection_visual()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_confirm()
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
		_confirm()

func _update_selection_visual() -> void:
	for i in option_labels.size():
		option_labels[i].modulate = Color.YELLOW if i == selected_index else Color.WHITE

func _confirm() -> void:
	# GameState.start_new_game já grava o save na hora (ver comentário lá) —
	# esta tela nunca precisa emitir `closed` no caminho de sucesso, ela some
	# junto com toda a pilha de telas de New Game quando a cena troca.
	GameState.start_new_game(target_slot, chosen_name, MODE_KEYS[selected_index])
	get_tree().change_scene_to_file(GameState.overworld_scene_path)

func _close() -> void:
	closed.emit()
	queue_free()
