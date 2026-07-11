extends CanvasLayer

# Editor do loadout de uma unidade (os 6 slots de ação — ataque/habilidade/
# item, ver UnitData.slots) — aberto pela opção "Loadout" do
# slot_action_menu (ver party_screen.gd::_open_loadout).
#
# Duas "camadas" na mesma tela em vez de duas cenas separadas (ROWS lista os
# 6 slots atuais; PICKING é o sub-menu que aparece por cima pra escolher uma
# ação nova pra um slot) — mais simples que encadear mais uma CanvasLayer
# pra algo tão pequeno. X abre o escolhedor no slot selecionado; dentro
# dele, X escolhe (ou "-- vazio --", que sempre é a primeira opção, pra
# desequipar) e Z cancela sem mudar nada; Z na lista de slots fecha a tela
# inteira.
#
# Grava DIRETO em data.slots (o mesmo Resource compartilhado por
# GameState.roster e, dentro de uma batalha, por Unit.apply_persisted_data()) — como
# já estava documentado em unit_data.gd ("Trocável fora de batalha num menu
# futuro"), é essa a intenção. Não persiste em disco (não existe save ainda,
# ver o TODO da opção "Save" no menu de pausa) — vale só pro resto desta
# sessão de jogo, igual o resto do progresso agora.

signal closed

enum Mode { ROWS, PICKING }

const SLOT_COUNT = 6

@onready var title_label: Label = $Center/Panel/MarginContainer/Content/Title
@onready var rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Rows
@onready var picker_layer: CenterContainer = $PickerCenter
@onready var picker_list: VBoxContainer = $PickerCenter/Panel/MarginContainer/PickerContent/PickerList

var data: UnitData
var mode: Mode = Mode.ROWS

var row_labels: Array[Label] = []
var selected_row: int = 0

var picker_options: Array = []   # ActionData ou null (== "-- vazio --")
var picker_labels: Array[Label] = []
var picker_selected: int = 0

func setup(unit_data: UnitData) -> void:
	data = unit_data
	title_label.text = "%s   Lv.%d — Loadout" % [data.unit_name.to_upper(), data.level]
	while data.slots.size() < SLOT_COUNT:
		data.slots.append(null)
	_build_rows()
	_refresh_rows()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	picker_layer.visible = false

func _build_rows() -> void:
	for i in SLOT_COUNT:
		var label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_row_mouse_entered.bind(i))
		label.gui_input.connect(_on_row_gui_input.bind(i))
		rows_container.add_child(label)
		row_labels.append(label)

func _refresh_rows() -> void:
	for i in SLOT_COUNT:
		var action = data.slots[i]
		var text = action.action_name if action != null else "-- vazio --"
		row_labels[i].text = "%d. %s" % [i + 1, text]
		row_labels[i].modulate = Color.YELLOW if i == selected_row and mode == Mode.ROWS else Color.WHITE

func _on_row_mouse_entered(index: int) -> void:
	if mode != Mode.ROWS:
		return
	selected_row = index
	_refresh_rows()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if mode != Mode.ROWS:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_row = index
		_open_picker()

func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.ROWS:
		_handle_rows_input(event)
	else:
		_handle_picker_input(event)

func _handle_rows_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		selected_row = wrapi(selected_row + 1, 0, SLOT_COUNT)
		_refresh_rows()
	elif event.is_action_pressed("ui_up"):
		selected_row = wrapi(selected_row - 1, 0, SLOT_COUNT)
		_refresh_rows()
	elif event.is_action_pressed("confirm"):
		_open_picker()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _handle_picker_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		picker_selected = wrapi(picker_selected + 1, 0, picker_options.size())
		_update_picker_visual()
	elif event.is_action_pressed("ui_up"):
		picker_selected = wrapi(picker_selected - 1, 0, picker_options.size())
		_update_picker_visual()
	elif event.is_action_pressed("confirm"):
		_choose_picker_option()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close_picker()
	else:
		return
	get_viewport().set_input_as_handled()

# "-- vazio --" (null) sempre é a primeira opção, pra desequipar o slot ser
# tão fácil quanto trocar ele — sem precisar de um botão "remover" à parte.
#
# Ações já equipadas em OUTRO slot ficam de fora da lista — não faz sentido
# a mesma unidade carregar "Tackle" duas vezes. O slot que está sendo
# editado agora É EXCLUÍDO dessa checagem (senão a própria ação atual dele
# desapareceria da lista e escolher "a mesma de novo" ficaria impossível).
func _open_picker() -> void:
	var equipped_elsewhere: Array = []
	for i in SLOT_COUNT:
		if i != selected_row and data.slots[i] != null:
			equipped_elsewhere.append(data.slots[i])

	var current = data.slots[selected_row]

	picker_options = [null]
	for action in data.get_available_actions(data.level):
		if not equipped_elsewhere.has(action):
			picker_options.append(action)

	# Item dado pela Bag (ver GameState.give_item) não vem do learnset —
	# sem isso, o slot atual simplesmente NÃO aparece na lista, o cursor cai
	# em "-- vazio --" por padrão, e confirmar ali (achando que só estava
	# olhando) apaga o item. Precisa continuar selecionável, igual qualquer
	# ataque/habilidade já equipado.
	if current is ItemData and not picker_options.has(current):
		picker_options.append(current)

	picker_selected = 0
	for i in picker_options.size():
		if picker_options[i] == current:
			picker_selected = i
			break

	for child in picker_list.get_children():
		child.queue_free()
	picker_labels.clear()
	for i in picker_options.size():
		var action = picker_options[i]
		var label = Label.new()
		label.text = "-- vazio --" if action == null else action.action_name
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_picker_mouse_entered.bind(i))
		label.gui_input.connect(_on_picker_gui_input.bind(i))
		picker_list.add_child(label)
		picker_labels.append(label)

	mode = Mode.PICKING
	picker_layer.visible = true
	_refresh_rows()
	_update_picker_visual()

func _on_picker_mouse_entered(index: int) -> void:
	picker_selected = index
	_update_picker_visual()

func _on_picker_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		picker_selected = index
		_choose_picker_option()

func _update_picker_visual() -> void:
	for i in picker_labels.size():
		picker_labels[i].modulate = Color.YELLOW if i == picker_selected else Color.WHITE

func _choose_picker_option() -> void:
	var old_action = data.slots[selected_row]
	var new_action = picker_options[picker_selected]
	data.slots[selected_row] = new_action
	# Item que sai do loadout (trocado por outra coisa ou por "-- vazio --")
	# volta pro inventário em vez de sumir — era isso que causava o bug
	# reportado (dar um item, depois "esvaziar" o slot dele, e o item
	# nunca mais aparecer na Bag). Só devolve se REALMENTE mudou (escolher
	# a mesma opção que já estava lá, ver ajuste acima em _open_picker, não
	# deve devolver nada).
	#
	# Item Stackable (ver ItemData.stackable) devolve a PILHA INTEIRA que
	# estava no slot (UnitData.get_slot_quantity), não só 1 — senão
	# desequipar 8 TM 10 de uma vez devolvia só 1 pro inventário e sumia
	# com as outras 7. Não-stackable continua devolvendo 1, como sempre.
	if old_action is ItemData and old_action != new_action:
		var amount = data.get_slot_quantity(selected_row) if old_action.stackable else 1
		GameState.add_item(old_action, max(amount, 1))
		data.set_slot_quantity(selected_row, 0)
	_close_picker()
	_refresh_rows()

func _close_picker() -> void:
	mode = Mode.ROWS
	picker_layer.visible = false
	_refresh_rows()

func _close() -> void:
	closed.emit()
	queue_free()
