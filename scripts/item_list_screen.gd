extends CanvasLayer

# Segundo nível da Bag (ver bag_screen.gd) — lista os itens de UMA
# categoria que o jogador possui (GameState.get_items_in_category), cada
# um como ícone + nome + quantidade. Selecionar um item com Use/Give/
# Register disponível (ver ItemData.can_use/can_give/can_register) abre
# item_action_menu.tscn; escolher "Use" ou "Give" ali abre party_screen.tscn
# em picker_mode (ver comentário grande em party_screen.gd) pra escolher a
# unidade alvo, e só então aplica o efeito (GameState.use_item/give_item) e
# reconstrói a lista (a quantidade/loadout pode ter mudado) — EXCETO Use de
# um item Tool (ver GameState.use_tool), que não tem unidade alvo nenhuma e
# pula o picker por completo. "Register"/"Unregister" abrem/pulam
# tool_register_screen.tscn (ver GameState.tool_shortcuts).
#
# custom_minimum_size fixo no Panel (e no ScrollContainer das linhas) desde
# o início — aprendemos com pc_screen.gd que deixar o tamanho variar com o
# conteúdo faz a janela esticar/achatar; aqui já nasce do tamanho final.

signal closed

const ICON_SIZE = 32.0
const PLACEHOLDER_COLOR = Color(0.35, 0.35, 0.35)
const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)

const PARTY_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/party_screen.tscn")
const ITEM_ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/popups/item_action_menu.tscn")
const QUANTITY_PICKER_SCENE: PackedScene = preload("res://scenes/ui/popups/quantity_picker.tscn")
const TOOL_REGISTER_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/tool_register_screen.tscn")
const UnitScript = preload("res://scripts/unit.gd")

@onready var title_label: Label = $Center/Panel/MarginContainer/Content/Title
@onready var rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/RowsScroll/Rows
@onready var close_label: Label = $Center/Panel/MarginContainer/Content/Close

var current_category: String = ""
var row_items: Array[ItemData] = []
var row_panels: Array[PanelContainer] = []
var selected_row: int = 0

# true enquanto o quantity_picker (ver _open_quantity_picker) ainda está
# pra abrir/fechar — segura o reshow/rebuild de _on_party_picker_closed()
# até ESSE popup também resolver, senão a lista reaparecia por baixo do
# picker de quantidade no meio do fluxo de Give (ver comentário lá).
var _awaiting_quantity_pick: bool = false

# true enquanto item_action_menu ou tool_register_screen estão abertos "do
# lado" (ver _open_item_actions/_open_register_screen) — diferente do
# party_screen (tela grande, ainda usa hide()/show() de verdade, ver
# _open_party_picker), esses dois popups pequenos NÃO escondem mais este
# menu (pedido do usuário: evitar piscar janela pra trás/pra frente à toa).
# Mas isso sozinho deixaria os DOIS lendo teclado ao mesmo tempo (setas/X/Z
# valeriam tanto pro popup quanto pra lista por baixo) — esta flag substitui
# o `if not visible` como trava de input SÓ pra esses dois casos, sem
# depender de qual é a ordem real de propagação de _unhandled_input entre
# nó pai/filho (não é garantia que eu queira apostar).
var _input_locked: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_label.mouse_filter = Control.MOUSE_FILTER_STOP
	close_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_label.gui_input.connect(_on_close_gui_input)

func setup(category: String) -> void:
	current_category = category
	title_label.text = category
	_rebuild_rows()

func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	row_items.clear()
	row_panels.clear()
	selected_row = 0

	var items := GameState.get_items_in_category(current_category)
	if items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "-- vazio --"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows_container.add_child(empty_label)
		return

	for item in items:
		var index = row_items.size()
		var panel = _build_row(item, index)
		rows_container.add_child(panel)
		row_items.append(item)
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
		# Nenhum ícone pra essa categoria ainda — retângulo cinza no lugar.
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

# Só abre o menu de ações se o item realmente tiver alguma (ver
# ItemData.can_use/can_give/can_register) — item sem nenhuma das três
# simplesmente não faz nada ao ser selecionado, em vez de abrir um popup
# vazio e travado (Z não fecharia: ver item_action_menu.gd::
# _unhandled_input, que ignora input com options vazio).
func _activate_selected_row() -> void:
	if row_items.is_empty():
		return
	var item = row_items[selected_row]
	if not item.can_use and not item.can_give and not item.can_register:
		return
	_open_item_actions(item)

func _open_item_actions(item: ItemData) -> void:
	# NÃO esconde mais (ver item_action_menu.tscn) — o popup abre do LADO,
	# pequeno o suficiente pra caber na tela sem cobrir a lista. Menos
	# janela pra piscar/esconder no meio do fluxo (pedido do usuário). Trava
	# o PRÓPRIO input enquanto isso (ver _input_locked) — a lista continua
	# visível, mas quem deve reagir a seta/X/Z agora é só o popup.
	_input_locked = true
	var menu = ITEM_ACTION_MENU_SCENE.instantiate()
	add_child(menu)
	menu.setup(item)
	menu.closed.connect(_on_item_action_closed.bind(item))

func _on_item_action_closed(option: String, item: ItemData) -> void:
	# Destrava por padrão — Use(Tool)/Unregister/cancelado (_:) não abrem
	# mais nada, então a lista já pode voltar a reagir a input na hora.
	# Register/Use(não-Tool)/Give travam de novo (ou escondem de vez, ver
	# abaixo) antes de abrir o próximo popup.
	_input_locked = false
	match option:
		"Use":
			# Tool não tem unidade alvo nenhuma (o efeito é sobre o
			# TREINADOR, ver GameState.use_tool) — abrir o seletor de
			# unidade pra isso não faria sentido nenhum, diferente de
			# Medicine/Berry (cura) que sempre precisam de um alvo.
			if item.category == "Tool":
				GameState.use_tool(item)
				_rebuild_rows()
			else:
				_open_party_picker(item, "use")
		"Give":
			_open_party_picker(item, "give")
		"Register":
			_open_register_screen(item)
		"Unregister":
			GameState.unregister_tool(item)
			_rebuild_rows()
		_:
			pass

func _open_register_screen(item: ItemData) -> void:
	# Mesmo raciocínio de _open_item_actions() — sem hide(), o popup de
	# registro (tool_register_screen.tscn) também abre do lado, só travando
	# o input da lista por baixo.
	_input_locked = true
	var screen = TOOL_REGISTER_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(item)
	screen.closed.connect(_on_register_screen_closed)

func _on_register_screen_closed() -> void:
	_input_locked = false
	_rebuild_rows()

# Diferente de item_action_menu/tool_register_screen (pequenos, abrem do
# lado), party_screen é uma tela cheia — continua no padrão antigo de
# esconder de vez (ver _on_party_picker_closed/_on_quantity_picked, que
# trazem de volta com show()). _input_locked não entra aqui: `visible=false`
# já basta pro guard de _unhandled_input.
func _open_party_picker(item: ItemData, mode: String) -> void:
	hide()
	var screen = PARTY_SCREEN_SCENE.instantiate()
	screen.picker_mode = true
	if mode == "use":
		screen.picker_prompt = "Use %s em qual unidade?   (Z: cancelar)" % item.action_name
		# Item que só cura (heal_amount > 0) não faz nada numa unidade com HP
		# já cheio — "se o item não vai fazer nada, ele não pode ser usado"
		# (Potion/Super Potion/Oran Berry). Item sem cura nenhuma (futuro
		# Tool/TM) não entra nessa restrição.
		if item.heal_amount > 0:
			screen.picker_filter = _has_missing_hp
			screen.picker_filter_hint = "(HP cheio)"
		# Mesmo raciocínio pro Ability Patch: não faz nada numa unidade sem
		# Habilidade Hidden nenhuma pra revelar, ou que já revelou a dela
		# (ver UnitData.has_unrevealed_hidden_ability).
		elif item.reveals_hidden_ability:
			screen.picker_filter = _has_unrevealed_hidden_ability
			screen.picker_filter_hint = "(sem Habilidade Hidden)"
	else:
		screen.picker_prompt = "Dar %s pra qual unidade?   (Z: cancelar)" % item.action_name
	add_child(screen)
	screen.unit_picked.connect(_on_party_target_picked.bind(item, mode))
	screen.closed.connect(_on_party_picker_closed)

func _has_missing_hp(data: UnitData) -> bool:
	var hp_max = UnitScript.calc_hp_static(data.hp_base, data.level, data.weight)
	return data.current_hp < hp_max

func _has_unrevealed_hidden_ability(data: UnitData) -> bool:
	return data.has_unrevealed_hidden_ability()

func _on_party_target_picked(index: int, item: ItemData, mode: String) -> void:
	var target = GameState.get_roster_slot(index)
	if target == null:
		return
	if mode == "use":
		GameState.use_item(item, target)
		return
	# Give: item Stackable com mais de 1 disponível precisa perguntar QUANTAS
	# antes de dar de verdade (ver quantity_picker.gd) — com só 1 disponível
	# (ou item não-Stackable, que sempre dá exatamente 1) não tem escolha
	# nenhuma pra fazer, pular a pergunta direto pra _finish_give().
	if item.stackable and GameState.get_item_quantity(item) > 1:
		_awaiting_quantity_pick = true
		_open_quantity_picker(item, target)
	else:
		_finish_give(item, target, 1)

func _open_quantity_picker(item: ItemData, target: UnitData) -> void:
	var picker = QUANTITY_PICKER_SCENE.instantiate()
	add_child(picker)
	picker.setup(item.action_name, min(99, GameState.get_item_quantity(item)))
	picker.closed.connect(_on_quantity_picked.bind(item, target))

# amount == -1 é "cancelado" (Z no picker de quantidade) — nesse caso não
# dá nada, só libera o reshow que _on_party_picker_closed estava segurando.
func _on_quantity_picked(amount: int, item: ItemData, target: UnitData) -> void:
	_awaiting_quantity_pick = false
	if amount > 0:
		_finish_give(item, target, amount)
	show()
	_rebuild_rows()

func _finish_give(item: ItemData, target: UnitData, amount: int) -> void:
	var success = GameState.give_item(item, target, amount)
	if not success:
		print("TODO: feedback visual de 'nenhum slot vazio no loadout' (GameState.give_item falhou)")

# Reaparece e reconstrói a lista (quantidade ou loadout podem ter mudado) —
# chamado tanto depois de escolher um alvo de verdade quanto depois de
# cancelar o picker (Z lá), então não dá pra assumir que algo mudou; refazer
# a lista sempre é barato e mais simples que checar os dois casos.
#
# EXCETO se um quantity_picker ainda vai abrir/fechar por cima (ver
# _awaiting_quantity_pick) — nesse caso a lista reaparece sozinha depois,
# em _on_quantity_picked, quando o fluxo de Give realmente termina; reshow
# aqui a deixaria visível POR BAIXO do picker de quantidade no meio do
# processo, o que pareceria um bug de UI.
func _on_party_picker_closed() -> void:
	if _awaiting_quantity_pick:
		return
	show()
	_rebuild_rows()

func _on_close_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
