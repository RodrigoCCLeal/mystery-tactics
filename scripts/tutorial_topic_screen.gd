extends CanvasLayer

# Segundo nível do tutorial (ver tutorial_screen.gd) — mostra o TEXTO
# completo de um tópico escolhido. Só leitura: não há opções pra escolher
# aqui, só rolar o texto (se ele não couber inteiro no painel) e voltar.
#
# ui_down/ui_up rolam o texto manualmente (o ScrollContainer já rola sozinho
# com a roda do mouse, mas quem só usa teclado precisa de um jeito de ver o
# resto) — confirm/cancel/menu fecham igual o resto do projeto.

signal closed

const SCROLL_STEP = 40.0

@onready var title_label: Label = $Center/Panel/MarginContainer/Content/Title
@onready var body_scroll: ScrollContainer = $Center/Panel/MarginContainer/Content/BodyScroll
@onready var body_label: Label = $Center/Panel/MarginContainer/Content/BodyScroll/Body
@onready var close_label: Label = $Center/Panel/MarginContainer/Content/Close

func setup(topic_title: String, topic_body: String) -> void:
	title_label.text = topic_title
	body_label.text = topic_body
	body_scroll.scroll_vertical = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_label.mouse_filter = Control.MOUSE_FILTER_STOP
	close_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_label.gui_input.connect(_on_close_gui_input)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		body_scroll.scroll_vertical += SCROLL_STEP
	elif event.is_action_pressed("ui_up"):
		body_scroll.scroll_vertical -= SCROLL_STEP
	elif event.is_action_pressed("confirm") or event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _on_close_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
