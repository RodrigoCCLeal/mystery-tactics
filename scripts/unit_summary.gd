extends CanvasLayer

# Tela somente-leitura com os atributos completos de uma unidade — aberta
# pela opção "Summary" do slot_action_menu (ver party_screen.gd::_open_summary).
# Nada aqui é selecionável/editável (isso é o Loadout, ver unit_loadout.gd);
# X ou Z fecham do mesmo jeito, e "Fechar" também é clicável, só por
# consistência com o resto do menu (mouse sempre funciona em paralelo do
# teclado neste projeto).

signal closed

const UnitScript = preload("res://scripts/unit.gd")

@onready var title_label: Label = $Center/Panel/MarginContainer/Content/Title
@onready var stats_rows: VBoxContainer = $Center/Panel/MarginContainer/Content/Stats
@onready var loadout_rows: VBoxContainer = $Center/Panel/MarginContainer/Content/Loadout
@onready var close_label: Label = $Center/Panel/MarginContainer/Content/Close

func setup(data: UnitData) -> void:
	var level = data.level
	var types_text = " / ".join(data.types) if not data.types.is_empty() else "--"
	title_label.text = "%s   Lv.%d   [%s]" % [data.unit_name.to_upper(), level, types_text]

	var hp_max = UnitScript.calc_hp_static(data.hp_base, level, data.weight)
	_add_stat_row("HP", "%d/%d" % [max(data.current_hp, 0), hp_max])
	_add_stat_row("Attack", UnitScript.calc_stat_static(data.attack_base, level))
	_add_stat_row("Defense", UnitScript.calc_stat_static(data.defense_base, level))
	_add_stat_row("Sp. Attack", UnitScript.calc_stat_static(data.special_attack_base, level))
	_add_stat_row("Sp. Defense", UnitScript.calc_stat_static(data.special_defense_base, level))
	_add_stat_row("Speed", UnitScript.calc_stat_static(data.speed_base, level))
	_add_stat_row("Weight", data.weight)

	for i in data.slots.size():
		var action = data.slots[i]
		var text = action.action_name if action != null else "-- vazio --"
		_add_loadout_row(i + 1, text)

func _add_stat_row(label_text: String, value) -> void:
	var row = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label = Label.new()
	value_label.text = str(value)
	row.add_child(name_label)
	row.add_child(value_label)
	stats_rows.add_child(row)

func _add_loadout_row(slot_number: int, text: String) -> void:
	var label = Label.new()
	label.text = "%d. %s" % [slot_number, text]
	loadout_rows.add_child(label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_label.mouse_filter = Control.MOUSE_FILTER_STOP
	close_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_label.gui_input.connect(_on_close_gui_input)

func _on_close_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm") or event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	closed.emit()
	queue_free()
