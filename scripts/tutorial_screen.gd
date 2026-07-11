extends CanvasLayer

# Primeiro nível do tutorial (ver baldo.gd::interact) — lista os TÓPICOS
# disponíveis (TutorialTopics.get_topics(), ver comentário grande lá) e abre
# tutorial_topic_screen.tscn com o texto completo do tópico escolhido.
#
# Mesma estrutura de navegação de bag_screen.gd/item_list_screen.gd (setas +
# X confirma + Z/Esc fecha, mouse em paralelo) — linhas construídas em código
# (não fixas no .tscn) porque a lista de tópicos vive em TutorialTopics, não
# aqui, então dá pra adicionar/remover tópico sem tocar na cena.

signal closed

const TutorialTopics = preload("res://scripts/tutorial_topics.gd")
const TUTORIAL_TOPIC_SCREEN_SCENE: PackedScene = preload("res://scenes/tutorial_topic_screen.tscn")

@onready var rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/RowsScroll/Rows
@onready var close_label: Label = $Center/Panel/MarginContainer/Content/Close

var topics: Array[Dictionary] = []
var row_labels: Array[Label] = []
var selected_row: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_label.mouse_filter = Control.MOUSE_FILTER_STOP
	close_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_label.gui_input.connect(_on_close_gui_input)
	topics = TutorialTopics.get_topics()
	for i in topics.size():
		var label = Label.new()
		label.text = topics[i]["title"]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_row_mouse_entered.bind(i))
		label.gui_input.connect(_on_row_gui_input.bind(i))
		rows_container.add_child(label)
		row_labels.append(label)
	_update_selection_visual()

# Mesmo motivo do "if not visible: return" em bag_screen.gd — enquanto
# tutorial_topic_screen está aberta por cima (this hide()-ado), não processa
# input.
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
	if row_labels.is_empty():
		return
	selected_row = wrapi(selected_row + step, 0, row_labels.size())
	_update_selection_visual()

func _on_row_mouse_entered(index: int) -> void:
	selected_row = index
	_update_selection_visual()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_row = index
		_activate_selected()

func _update_selection_visual() -> void:
	for i in row_labels.size():
		row_labels[i].modulate = Color.YELLOW if i == selected_row else Color.WHITE

func _activate_selected() -> void:
	_open_topic(topics[selected_row])

func _open_topic(topic: Dictionary) -> void:
	hide()
	var screen = TUTORIAL_TOPIC_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(topic["title"], topic["body"])
	screen.closed.connect(show)

func _on_close_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
