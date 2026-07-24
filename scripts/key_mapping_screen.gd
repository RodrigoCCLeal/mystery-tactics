extends CanvasLayer

# Tela de Key Mapping (ver options_screen.gd::_open_key_mapping) — lista
# TODA ação remapeável (ver Settings.REMAPPABLE_ACTIONS/ACTION_LABELS),
# mostrando a tecla física atual de cada uma; selecionar uma (X/clique) entra
# em "modo escuta" (label vira "Press a key...") e a PRÓXIMA tecla apertada
# vira o novo bind daquela ação (ver Settings.rebind_action). Esc durante a
# escuta CANCELA em vez de virar o novo bind — é o único jeito confiável de
# desistir de um rebind sem precisar apertar OUTRA tecla, então Escape nunca
# pode ser atribuído por aqui (ver _handle_listen_input).
#
# Pedido do usuário: "add a Key Mapping feature. Will be important for
# controller support later" — só teclado por enquanto (capturar/mostrar
# botão de joystick é uma feature maior à parte: nomes de botão variam por
# tipo de controle, eixo analógico tem deadzone, etc.), mas a separação
# feita em Settings.rebind_action (só mexe no evento de TECLADO, nunca
# apaga o bind de joystick padrão de ui_up/down/left/right) já deixa isso
# pronto pra ganhar uma segunda coluna "Controller" depois sem precisar
# reescrever nada daqui.
#
# Linhas construídas em código a partir de Settings.REMAPPABLE_ACTIONS
# (mesmo padrão de save_slot_screen.gd::_build_slot_row) — mais fácil de
# manter que escrever um Label fixo por ação no .tscn, e a lista já cresce
# dentro de um ScrollContainer (16 ações não cabem tudo de uma vez no
# painel).

signal closed

const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)
const ROW_SIZE = Vector2(320, 32)

@onready var rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Scroll/Rows
@onready var scroll_container: ScrollContainer = $Center/Panel/MarginContainer/Content/Scroll
@onready var reset_label: Label = $Center/Panel/MarginContainer/Content/ResetAll
@onready var back_label: Label = $Center/Panel/MarginContainer/Content/Back

# Cada entry: {"action": String, "panel": PanelContainer, "key_label": Label}
var rows: Array = []
var selected_index: int = 0
# "" = navegação normal; caso contrário, é a ação esperando a próxima tecla
# (ver _handle_listen_input). Trava clique/teclado nas OUTRAS linhas
# enquanto isso — ver guard em _on_row_gui_input/_activate_selected.
var _listening_action: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in rows_container.get_children():
		child.queue_free()
	rows.clear()
	for action in Settings.REMAPPABLE_ACTIONS:
		var row = _build_row(action)
		rows_container.add_child(row.panel)
		rows.append(row)
	reset_label.mouse_filter = Control.MOUSE_FILTER_STOP
	reset_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset_label.gui_input.connect(_on_reset_gui_input)
	back_label.mouse_filter = Control.MOUSE_FILTER_STOP
	back_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_label.gui_input.connect(_on_back_gui_input)
	_update_selection_visual()

func _build_row(action: String) -> Dictionary:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = ROW_SIZE
	var style = StyleBoxFlat.new()
	style.bg_color = ROW_STYLE_NORMAL
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var box = HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var name_label = Label.new()
	name_label.text = Settings.ACTION_LABELS.get(action, action)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var key_label = Label.new()
	key_label.text = Settings.get_action_key_label(action)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(key_label)

	var index = rows.size()
	panel.mouse_entered.connect(_on_row_mouse_entered.bind(index))
	panel.gui_input.connect(_on_row_gui_input.bind(index))

	return {"action": action, "panel": panel, "key_label": key_label}

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _listening_action != "":
		_handle_listen_input(event)
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

# Só roda enquanto _listening_action != "" — intercepta a tecla física
# BRUTA (InputEventKey), não uma action mapeada, porque a tecla que o
# jogador vai apertar pode ser exatamente a que já está mapeada pra
# "confirm"/"cancel"/etc.; passar por is_action_pressed aqui perderia isso.
# event.echo descarta o auto-repeat de tecla segurada (senão a primeira
# tecla física detectada nem sempre seria a intencional).
func _handle_listen_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode == KEY_ESCAPE:
		# Esc SEMPRE cancela a escuta em vez de virar o novo bind — ver
		# comentário grande no topo do arquivo. Sem essa exceção, desistir
		# de um rebind seria impossível sem acidentalmente atribuir Escape
		# à ação (e potencialmente roubar Escape de "cancel"/"menu").
		_cancel_listening()
		return
	_finish_rebind(event)

func _move_selection(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, rows.size())
	_update_selection_visual()

func _on_row_mouse_entered(index: int) -> void:
	if _listening_action != "":
		return
	selected_index = index
	_update_selection_visual()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if _listening_action != "":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_activate_selected()

func _update_selection_visual() -> void:
	for i in rows.size():
		var style = rows[i].panel.get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = ROW_STYLE_SELECTED if i == selected_index else ROW_STYLE_NORMAL
	# Rola a lista sozinha pra manter a linha realçada visível — pedido do
	# usuário (2026-07-24): "Moving down using arrows doesn't scroll down the
	# options". Mesmo bug (e mesmo remédio) de unit_loadout.gd::
	# _update_picker_visual — sem isso, passar de ~8 ações (16 no total, mais
	# do que cabe no painel) deixava o cursor "sumir" por trás da borda do
	# ScrollContainer em vez de rolar pra acompanhar.
	if selected_index >= 0 and selected_index < rows.size():
		scroll_container.ensure_control_visible(rows[selected_index].panel)

func _activate_selected() -> void:
	if rows.is_empty():
		return
	var row = rows[selected_index]
	_listening_action = row.action
	row.key_label.text = "Press a key..."

func _cancel_listening() -> void:
	var row = _find_row(_listening_action)
	if row != null:
		row.key_label.text = Settings.get_action_key_label(_listening_action)
	_listening_action = ""

func _finish_rebind(event: InputEventKey) -> void:
	var action = _listening_action
	_listening_action = ""

	var old_keycode = Settings.get_action_physical_keycode(action)
	var new_key_event = InputEventKey.new()
	new_key_event.physical_keycode = event.physical_keycode

	# Se outra ação já usa essa MESMA tecla, troca as duas em vez de deixar
	# a outra sem tecla nenhuma — nenhuma ação fica "presa" sem jeito de ser
	# acionada só por causa de um rebind.
	for other_action in Settings.REMAPPABLE_ACTIONS:
		if other_action == action:
			continue
		if Settings.get_action_physical_keycode(other_action) == event.physical_keycode:
			if old_keycode != -1:
				var swapped_event = InputEventKey.new()
				swapped_event.physical_keycode = old_keycode
				Settings.rebind_action(other_action, swapped_event)
			var other_row = _find_row(other_action)
			if other_row != null:
				other_row.key_label.text = Settings.get_action_key_label(other_action)
			break

	Settings.rebind_action(action, new_key_event)
	var row = _find_row(action)
	if row != null:
		row.key_label.text = Settings.get_action_key_label(action)

func _find_row(action: String):
	for row in rows:
		if row.action == action:
			return row
	return null

func _on_reset_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_reset_all()

func _reset_all() -> void:
	if _listening_action != "":
		return
	Settings.reset_all_to_default()
	for row in rows:
		row.key_label.text = Settings.get_action_key_label(row.action)

func _on_back_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
