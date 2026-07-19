extends CanvasLayer

# Tela dos 3 save slots — reusada tanto por "New Game" quanto por
# "Load Game" (ver title_screen.gd::_open_slot_screen), o parâmetro `mode`
# (ver setup()) é o que muda o comportamento de confirmar um slot:
#   - "load": só faz алgo em slot OCUPADO (carrega e vai pro overworld);
#     selecionar um slot "Empty" não faz nada, mesmo espírito de
#     item_list_screen.gd::_activate_selected_row com item sem ação nenhuma.
#   - "new": slot vazio vai direto pra escolha de nome (name_entry_screen.gd);
#     slot já OCUPADO pergunta antes de sobrescrever (reusa yes_no_prompt.gd,
#     mesmo componente genérico Sim/Não do resto do projeto).
#
# Cada slot é uma "linha" construída em código (_build_slot_row), mesmo
# padrão de item_list_screen.gd::_build_row — PanelContainer com highlight
# amarelo translúcido quando selecionado, mouse E teclado funcionam em
# paralelo.

signal closed

const NAME_ENTRY_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/name_entry_screen.tscn")
const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")

const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)
const ROW_SIZE = Vector2(260, 56)

@onready var title_label: Label = $Center/Panel/MarginContainer/Content/Title
@onready var rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Rows
@onready var back_label: Label = $Center/Panel/MarginContainer/Content/Back

var mode: String = "new"   # "new" ou "load", ver comentário acima
var slot_panels: Array[PanelContainer] = []
var selected_slot: int = 0

func setup(mode_: String) -> void:
	mode = mode_
	title_label.text = "New Game" if mode == "new" else "Load Game"
	_build_rows()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	back_label.mouse_filter = Control.MOUSE_FILTER_STOP
	back_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_label.gui_input.connect(_on_back_gui_input)

func _build_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	slot_panels.clear()
	for slot in GameState.SAVE_SLOT_COUNT:
		var panel = _build_slot_row(slot)
		rows_container.add_child(panel)
		slot_panels.append(panel)
	selected_slot = 0
	_update_row_visuals()

func _build_slot_row(slot: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = ROW_SIZE
	var style = StyleBoxFlat.new()
	style.bg_color = ROW_STYLE_NORMAL
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(_on_row_mouse_entered.bind(slot))
	panel.gui_input.connect(_on_row_gui_input.bind(slot))

	var box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var data := GameState.peek_save(slot)
	if data == null:
		var empty_label = Label.new()
		empty_label.text = "Empty"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(empty_label)
	else:
		var name_label = Label.new()
		name_label.text = data.player_name
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(name_label)
		var badges_label = Label.new()
		badges_label.text = "Badges: %d" % data.badges.size()
		badges_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(badges_label)
	return panel

func _on_row_mouse_entered(slot: int) -> void:
	selected_slot = slot
	_update_row_visuals()

func _on_row_gui_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_slot = slot
		_activate_selected_slot()

func _update_row_visuals() -> void:
	for i in slot_panels.size():
		var style = slot_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = ROW_STYLE_SELECTED if i == selected_slot else ROW_STYLE_NORMAL

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_activate_selected_slot()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	selected_slot = wrapi(selected_slot + step, 0, GameState.SAVE_SLOT_COUNT)
	_update_row_visuals()

func _activate_selected_slot() -> void:
	if mode == "load":
		if not GameState.has_save(selected_slot):
			return
		GameState.load_game(selected_slot)
		get_tree().change_scene_to_file(GameState.overworld_scene_path)
		return
	# mode == "new"
	if GameState.has_save(selected_slot):
		_confirm_overwrite(selected_slot)
	else:
		_open_name_entry(selected_slot)

func _confirm_overwrite(slot: int) -> void:
	hide()
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("This slot already has a save. Overwrite it with a brand-new game?")
	prompt.answered.connect(_on_overwrite_answered.bind(slot))

func _on_overwrite_answered(yes: bool, slot: int) -> void:
	if yes:
		_open_name_entry(slot)
	else:
		show()

func _open_name_entry(slot: int) -> void:
	hide()
	var screen = NAME_ENTRY_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(slot)
	# Se o jogador cancelar a escolha de nome (Z), volta pra esta tela — se
	# confirmar, name_entry_screen.gd troca de cena pro overworld direto
	# (ver comentário lá), o que destrói esta tela junto sem precisar de
	# nenhum "closed" chegando até aqui.
	screen.closed.connect(show)

func _on_back_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
