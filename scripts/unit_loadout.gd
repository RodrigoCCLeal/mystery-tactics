extends CanvasLayer

# Editor do loadout de uma unidade (os 6 slots de ação — ataque/habilidade/
# item, ver UnitData.slots) — aberto pela opção "Loadout" do
# slot_action_menu (ver party_screen.gd::_open_loadout).
#
# Duas colunas lado a lado, AS DUAS SEMPRE ABERTAS ao mesmo tempo — nada de
# clicar num slot pra só então abrir um sub-menu por cima ou do lado: a
# esquerda lista os 6 slots atuais, a direita já mostra de cara as opções
# disponíveis pro slot selecionado. Mover a seleção na esquerda (mouse ou
# seta) atualiza a direita NA HORA (ver _refresh_picker_options(), chamada
# toda vez que selected_row muda). ui_left/ui_right trocam qual coluna
# recebe as setas up/down (focus_column); X escolhe a opção realçada (só
# faz efeito com o foco na coluna de opções) ou, com o foco nos slots, pula
# o foco pra lá (atalho, equivalente a apertar seta direita); Z tira o foco
# da coluna de opções de volta pros slots, ou fecha a tela inteira se o
# foco já estiver nos slots. Clicar direto numa opção com o mouse aplica na
# hora, sem precisar "entrar" na coluna primeiro — hover já basta pra ver as
# opções, clique já basta pra escolher.
#
# Grava DIRETO em data.slots (o mesmo Resource compartilhado por
# GameState.roster e, dentro de uma batalha, por Unit.apply_persisted_data()) — como
# já estava documentado em unit_data.gd ("Trocável fora de batalha num menu
# futuro"), é essa a intenção. Não persiste em disco (não existe save ainda,
# ver o TODO da opção "Save" no menu de pausa) — vale só pro resto desta
# sessão de jogo, igual o resto do progresso agora.

signal closed

enum Column { SLOTS, OPTIONS }

const SLOT_COUNT = 6

@onready var title_label: Label = $Center/Pair/SlotsBox/MarginContainer/Content/Title
@onready var rows_container: VBoxContainer = $Center/Pair/SlotsBox/MarginContainer/Content/Rows
@onready var picker_list: VBoxContainer = $Center/Pair/OptionsBox/MarginContainer/PickerContent/PickerList

var data: UnitData
var focus_column: Column = Column.SLOTS

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
	# A coluna de opções já nasce preenchida (pro slot 0, selected_row
	# default) — as duas colunas abrem JUNTAS, não uma depois da outra.
	_refresh_picker_options()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

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
		var text = _display_name(action) if action != null else "-- vazio --"
		row_labels[i].text = "%d. %s" % [i + 1, text]
		row_labels[i].modulate = Color.YELLOW if i == selected_row else Color.WHITE

# Nome mostrado pra uma ação — igual action.action_name, só que com "
# (Hidden)" no final quando for uma Habilidade marcada Hidden PRA ESTA
# ESPÉCIE (ver UnitData.is_ability_hidden/LearnsetEntry.is_hidden_ability).
# Usado tanto na lista dos 6 slots quanto na coluna de opções, pra o
# jogador ver de cara qual Habilidade é a Hidden antes de equipar.
func _display_name(action: ActionData) -> String:
	if action is AbilityData and data.is_ability_hidden(action):
		return "%s (Hidden)" % action.action_name
	return action.action_name

func _on_row_mouse_entered(index: int) -> void:
	focus_column = Column.SLOTS
	selected_row = index
	_refresh_rows()
	_refresh_picker_options()

func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focus_column = Column.SLOTS
		selected_row = index
		_refresh_rows()
		_refresh_picker_options()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		focus_column = Column.SLOTS
	elif event.is_action_pressed("ui_right"):
		focus_column = Column.OPTIONS
	elif focus_column == Column.SLOTS:
		_handle_slots_input(event)
		return
	else:
		_handle_options_input(event)
		return
	get_viewport().set_input_as_handled()

func _handle_slots_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		selected_row = wrapi(selected_row + 1, 0, SLOT_COUNT)
		_refresh_rows()
		_refresh_picker_options()
	elif event.is_action_pressed("ui_up"):
		selected_row = wrapi(selected_row - 1, 0, SLOT_COUNT)
		_refresh_rows()
		_refresh_picker_options()
	elif event.is_action_pressed("confirm"):
		# Atalho pra quem só usa teclado: equivalente a apertar seta
		# direita, pula o foco direto pra coluna de opções (que já está
		# populada — não tem "abrir" nenhum aqui).
		focus_column = Column.OPTIONS
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _handle_options_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		picker_selected = wrapi(picker_selected + 1, 0, picker_options.size())
		_update_picker_visual()
	elif event.is_action_pressed("ui_up"):
		picker_selected = wrapi(picker_selected - 1, 0, picker_options.size())
		_update_picker_visual()
	elif event.is_action_pressed("confirm"):
		_choose_picker_option()
		focus_column = Column.SLOTS
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		# Só tira o foco de volta pros slots — NÃO fecha a tela (isso só
		# acontece com cancel/menu já com o foco em slots, ver
		# _handle_slots_input). As opções continuam abertas, do lado.
		focus_column = Column.SLOTS
	else:
		return
	get_viewport().set_input_as_handled()

# "-- vazio --" (null) sempre é a primeira opção, pra desequipar o slot ser
# tão fácil quanto trocar ele — sem precisar de um botão "remover" à parte.
#
# Ações já equipadas em OUTRO slot ficam de fora da lista — não faz sentido
# a mesma unidade carregar "Tackle" duas vezes. O slot SELECIONADO agora é
# EXCLUÍDO dessa checagem (senão a própria ação atual dele desapareceria da
# lista e escolher "a mesma de novo" ficaria impossível).
#
# Chamada toda vez que selected_row muda (troca de slot no mouse ou nas
# setas) — as duas colunas ficam abertas o tempo todo, então a direita
# precisa se manter em dia sozinha, não só numa hora de "abrir" pontual.
func _refresh_picker_options() -> void:
	var equipped_elsewhere: Array = []
	for i in SLOT_COUNT:
		if i != selected_row and data.slots[i] != null:
			equipped_elsewhere.append(data.slots[i])

	var current = data.slots[selected_row]

	picker_options = [null]
	for action in data.get_available_actions(data.level):
		if not equipped_elsewhere.has(action):
			picker_options.append(action)

	# Item dado pela Bag (ver GameState.give_item) não vem do learnset, ou
	# uma Habilidade Hidden ainda não revelada (ver UnitData.
	# get_available_actions/hidden_ability_revealed) — nos dois casos, o
	# slot atual precisa continuar selecionável mesmo caindo fora da lista
	# normal. Sem isso, o slot atual simplesmente NÃO apareceria na lista, o
	# cursor cairia em "-- vazio --" por padrão, e escolher ali (achando que
	# só estava olhando) apagaria a ação.
	if current != null and not picker_options.has(current):
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
		label.text = "-- vazio --" if action == null else _display_name(action)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_picker_mouse_entered.bind(i))
		label.gui_input.connect(_on_picker_gui_input.bind(i))
		picker_list.add_child(label)
		picker_labels.append(label)

	_update_picker_visual()

func _on_picker_mouse_entered(index: int) -> void:
	focus_column = Column.OPTIONS
	picker_selected = index
	_update_picker_visual()

func _on_picker_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focus_column = Column.OPTIONS
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
	# a mesma opção que já estava lá não deve devolver nada).
	#
	# Item Stackable (ver ItemData.stackable) devolve a PILHA INTEIRA que
	# estava no slot (UnitData.get_slot_quantity), não só 1 — senão
	# desequipar 8 TM 10 de uma vez devolvia só 1 pro inventário e sumia
	# com as outras 7. Não-stackable continua devolvendo 1, como sempre.
	if old_action is ItemData and old_action != new_action:
		var amount = data.get_slot_quantity(selected_row) if old_action.stackable else 1
		GameState.add_item(old_action, max(amount, 1))
		data.set_slot_quantity(selected_row, 0)
	_refresh_rows()
	# A ação escolhida pode ter mudado o que "equipado em outro slot"
	# exclui — reconstrói a própria coluna de opções também, já apontando
	# pra ela como a nova "atual" do slot.
	_refresh_picker_options()

func _close() -> void:
	closed.emit()
	queue_free()
