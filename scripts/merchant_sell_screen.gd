extends CanvasLayer

# Subtela "Sell" do Merchant (ver merchant_menu.gd::_open_sell_screen) —
# abre a Bag do jogador (GameState.inventory, não merchant.stock: um
# Merchant NÃO precisa ter comprado o item antes pra poder recomprá-lo de
# volta) e lista todo item vendável: category != "Tool" (pedido do usuário:
# "You can't sell Tools") E sell_price > 0 (ver comentário em ItemData.
# sell_price: "0 = este item não pode ser vendido") E que o jogador realmente
# possui (quantidade > 0). Mesmo esqueleto de merchant_buy_screen.gd, só que
# vendendo em vez de comprando (soma dinheiro, tira item, sem estoque de
# Merchant nenhum envolvido).

signal closed

const ICON_SIZE = 32.0
const PLACEHOLDER_COLOR = Color(0.35, 0.35, 0.35)
const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)

const QUANTITY_PICKER_SCENE: PackedScene = preload("res://scenes/ui/popups/quantity_picker.tscn")

@onready var title_label: Label = $Center/Panel/MarginContainer/Content/Title
@onready var money_label: Label = $Center/Panel/MarginContainer/Content/Money
@onready var rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/RowsScroll/Rows
@onready var close_label: Label = $Center/Panel/MarginContainer/Content/Close

var row_items: Array[ItemData] = []
var row_panels: Array[PanelContainer] = []
var selected_row: int = 0
var _input_locked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	title_label.text = "Sell"
	close_label.mouse_filter = Control.MOUSE_FILTER_STOP
	close_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_label.gui_input.connect(_on_close_gui_input)

func setup() -> void:
	_rebuild_rows()

func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	row_panels.clear()

	row_items.clear()
	for item in GameState.inventory:
		if item.category != "Tool" and item.sell_price > 0 and GameState.inventory[item] > 0:
			row_items.append(item)
	row_items.sort_custom(func(a, b): return a.action_name < b.action_name)
	selected_row = clampi(selected_row, 0, max(row_items.size() - 1, 0))
	money_label.text = "Money: %d" % GameState.money

	if row_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "-- vazio --"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows_container.add_child(empty_label)
		return

	for i in row_items.size():
		var panel = _build_row(row_items[i], i)
		rows_container.add_child(panel)
		row_panels.append(panel)
	_update_row_visuals()

func _build_row(item: ItemData, index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = ROW_STYLE_NORMAL
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_entered.connect(_on_row_mouse_entered.bind(index))
	panel.gui_input.connect(_on_row_gui_input.bind(index))

	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	if item.icon != null:
		var icon = TextureRect.new()
		icon.texture = item.icon
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		var placeholder = ColorRect.new()
		placeholder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		placeholder.color = PLACEHOLDER_COLOR
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(placeholder)

	var name_label = Label.new()
	name_label.text = item.action_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	var price_label = Label.new()
	price_label.text = "$%d" % item.sell_price
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(price_label)

	var qty_label = Label.new()
	qty_label.text = "x%d" % GameState.get_item_quantity(item)
	qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(qty_label)

	return panel

func _on_row_mouse_entered(index: int) -> void:
	selected_row = index
	_update_row_visuals()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if _input_locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_row = index
		_activate_selected_row()

func _update_row_visuals() -> void:
	for i in row_panels.size():
		var style = row_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = ROW_STYLE_SELECTED if i == selected_row else ROW_STYLE_NORMAL

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _input_locked:
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_activate_selected_row()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	if row_items.is_empty():
		return
	selected_row = wrapi(selected_row + step, 0, row_items.size())
	_update_row_visuals()

func _activate_selected_row() -> void:
	if row_items.is_empty():
		return
	_open_quantity_picker(row_items[selected_row])

func _open_quantity_picker(item: ItemData) -> void:
	_input_locked = true
	var picker = QUANTITY_PICKER_SCENE.instantiate()
	add_child(picker)
	picker.setup(item.action_name, min(99, GameState.get_item_quantity(item)))
	picker.closed.connect(_on_quantity_picked.bind(item))

# amount == -1 é "cancelado" (Z no picker de quantidade).
func _on_quantity_picked(amount: int, item: ItemData) -> void:
	_input_locked = false
	if amount > 0:
		GameState.add_money(item.sell_price * amount)
		GameState.remove_item(item, amount)
	_rebuild_rows()

func _on_close_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
