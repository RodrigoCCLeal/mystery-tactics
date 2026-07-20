extends CanvasLayer

# Subtela "Buy" do Merchant (ver merchant_menu.gd::_open_buy_screen) — lista
# merchant.stock (não GameState.inventory, ao contrário de item_list_screen.
# gd) como ícone + nome + preço, com a quantidade restante se o estoque for
# limitado (MerchantStockEntry.quantity != -1). Mesmo esqueleto visual/input
# de item_list_screen.gd (linhas clicáveis + seleção por seta, popup de
# quantidade do lado usando _input_locked pra travar a lista por baixo).
#
# Itens com buy_price <= 0 nunca aparecem (ver comentário em ItemData.
# buy_price: "0 = este item nunca aparece à venda em lugar nenhum"). Linhas
# com min_badges não atingido (ver MerchantStockEntry.min_badges) também não
# aparecem NA LISTA — diferente de "esgotado"/"sem dinheiro" (que mostram a
# linha escurecida), uma badge faltando esconde a linha inteira, mesmo
# espírito de EncounterGroup.min_badges nunca sortear um encontro fora de
# alcance em vez de "mostrar mas bloquear".
# Linhas esgotadas ou que o jogador não tem dinheiro pra comprar nem 1
# unidade ficam escurecidas (modulate) e não fazem nada ao serem
# selecionadas — mesmo princípio de guard que item_list_screen.gd usa pra
# itens sem Use/Give/Register (_activate_selected_row apenas não faz nada).

signal closed

const ICON_SIZE = 32.0
const PLACEHOLDER_COLOR = Color(0.35, 0.35, 0.35)
const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)
const DISABLED_MODULATE = Color(0.5, 0.5, 0.5)

const QUANTITY_PICKER_SCENE: PackedScene = preload("res://scenes/ui/popups/quantity_picker.tscn")

@onready var title_label: Label = $Center/Panel/MarginContainer/Content/Title
@onready var money_label: Label = $Center/Panel/MarginContainer/Content/Money
@onready var rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/RowsScroll/Rows
@onready var close_label: Label = $Center/Panel/MarginContainer/Content/Close

var row_entries: Array[MerchantStockEntry] = []
var row_panels: Array[PanelContainer] = []
var selected_row: int = 0

# Trava a lista enquanto o quantity_picker está aberto do lado — mesmo
# raciocínio de item_list_screen.gd::_input_locked.
var _input_locked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	title_label.text = "Buy"
	close_label.mouse_filter = Control.MOUSE_FILTER_STOP
	close_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_label.gui_input.connect(_on_close_gui_input)

func setup(stock: Array[MerchantStockEntry]) -> void:
	row_entries.clear()
	for entry in stock:
		if entry.item != null and entry.item.buy_price > 0 and entry.meets_badge_requirement():
			row_entries.append(entry)
	_rebuild_rows()

func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	row_panels.clear()
	selected_row = clampi(selected_row, 0, max(row_entries.size() - 1, 0))
	money_label.text = "Money: %d" % GameState.money

	if row_entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "-- vazio --"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows_container.add_child(empty_label)
		return

	for i in row_entries.size():
		var panel = _build_row(row_entries[i], i)
		rows_container.add_child(panel)
		row_panels.append(panel)
	_update_row_visuals()

func _build_row(entry: MerchantStockEntry, index: int) -> PanelContainer:
	var item := entry.item
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
	if _row_disabled(entry):
		panel.modulate = DISABLED_MODULATE

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
	price_label.text = "Esgotado" if not entry.is_in_stock() else "$%d" % item.buy_price
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(price_label)

	# Estoque infinito não mostra nada extra (padrão, ver MerchantStockEntry.
	# is_infinite) — só limitado mostra "x5" etc, pra não poluir a lista com
	# um "x∞" em toda linha quando isso é o caso comum.
	if not entry.is_infinite():
		var stock_label = Label.new()
		stock_label.text = "x%d" % entry.quantity
		stock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(stock_label)

	return panel

func _row_disabled(entry: MerchantStockEntry) -> bool:
	return not entry.is_in_stock() or GameState.money < entry.item.buy_price

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
	if row_entries.is_empty():
		return
	selected_row = wrapi(selected_row + step, 0, row_entries.size())
	_update_row_visuals()

func _activate_selected_row() -> void:
	if row_entries.is_empty():
		return
	var entry = row_entries[selected_row]
	if _row_disabled(entry):
		return
	_open_quantity_picker(entry)

func _open_quantity_picker(entry: MerchantStockEntry) -> void:
	_input_locked = true
	var picker = QUANTITY_PICKER_SCENE.instantiate()
	add_child(picker)
	var affordable_max = GameState.money / entry.item.buy_price
	var stock_max = 99 if entry.is_infinite() else entry.quantity
	var cap = clampi(min(99, affordable_max, stock_max), 1, 99)
	picker.setup(entry.item.action_name, cap)
	picker.closed.connect(_on_quantity_picked.bind(entry))

# amount == -1 é "cancelado" (Z no picker de quantidade) — ver comentário em
# quantity_picker.gd sobre o sentinela.
func _on_quantity_picked(amount: int, entry: MerchantStockEntry) -> void:
	_input_locked = false
	if amount > 0:
		var total_cost = entry.item.buy_price * amount
		if GameState.spend_money(total_cost):
			GameState.add_item(entry.item, amount)
			if not entry.is_infinite():
				entry.quantity -= amount
	_rebuild_rows()

func _on_close_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
