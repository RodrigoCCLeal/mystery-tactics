extends CanvasLayer

# Editor do loadout de uma unidade (os 6 slots de ação — ataque/habilidade/
# item, ver UnitData.slots) — aberto pela opção "Loadout" do
# slot_action_menu (ver party_screen.gd::_open_loadout).
#
# Layout em colunas, TODAS SEMPRE ABERTAS ao mesmo tempo — nada de clicar
# num slot pra só então abrir um sub-menu por cima ou do lado: a esquerda
# lista os 6 slots atuais, a direita já mostra de cara as opções
# disponíveis pro slot selecionado, SEPARADAS EM 4 PAINÉIS PERMANENTES
# (pedido do usuário, 2026-07-22: "Make it 3 columns, Attack Support and
# Ability" — Attack = AttackData com is_status=false, Support = AttackData
# com is_status=true, Ability = AbilityData, ver _column_for_action — mais
# "Item", pedido do usuário 2026-08-04: "Make the 'Item' column on loadout
# screen permanent, and show all 'Held Items' options". Item nunca vem do
# learnset (ver comentário grande em _refresh_picker_options), por isso tem
# sua própria fonte: GameState.get_items_in_category("Held Items"), o
# inventário de verdade do jogador, não a lista fixa por espécie das outras
# 3 colunas). Mover a seleção na esquerda (mouse ou seta) atualiza as
# colunas de opções NA HORA (ver _refresh_picker_options(), chamada toda
# vez que selected_row muda).
#
# Navegação (decidida com o usuário): ui_left/ui_right andam em ANEL por
# TODAS as colunas — Slots -> Attack -> Support -> Ability -> Item -> Slots
# de novo (ver _step_column/_visible_ring). Up/down navega dentro da coluna
# com foco. X escolhe a opção realçada (só faz efeito com o foco numa
# coluna de opções) ou, com o foco nos slots, avança o foco em 1 passo no
# anel (atalho, equivalente a apertar seta direita). Z tira o foco de volta
# pros slots, ou fecha a tela inteira se o foco já estiver nos slots.
# Clicar direto numa opção com o mouse aplica na hora, sem precisar "entrar"
# na coluna primeiro.
#
# Grava DIRETO em data.slots (o mesmo Resource compartilhado por
# GameState.roster e, dentro de uma batalha, por Unit.apply_persisted_data()) — como
# já estava documentado em unit_data.gd ("Trocável fora de batalha num menu
# futuro"), é essa a intenção. Não persiste em disco (não existe save ainda,
# ver o TODO da opção "Save" no menu de pausa) — vale só pro resto desta
# sessão de jogo, igual o resto do progresso agora.

signal closed

enum Column { SLOTS, ATTACK, SUPPORT, ABILITY, ITEM }

# Ordem do anel de navegação (ver _visible_ring/_step_column) — as 4
# colunas de opções são permanentes agora (ver comentário grande no topo do
# arquivo), então o anel inteiro está sempre disponível.
const COLUMN_RING: Array = [Column.SLOTS, Column.ATTACK, Column.SUPPORT, Column.ABILITY, Column.ITEM]

# As 4 colunas de opções (tudo exceto Slots) — usado pra iterar "todas as
# colunas de opções" sem precisar repetir a lista toda hora.
const OPTION_COLUMNS: Array = [Column.ATTACK, Column.SUPPORT, Column.ABILITY, Column.ITEM]

const SLOT_COUNT = 6

@onready var title_label: Label = $Center/Pair/SlotsBox/MarginContainer/Content/Title
@onready var rows_container: VBoxContainer = $Center/Pair/SlotsBox/MarginContainer/Content/Rows

# Um painel (Panel) por coluna de opções — só usado aqui pra ligar/desligar
# `.visible` da coluna Item (ver _refresh_picker_options).
@onready var picker_boxes: Dictionary = {
	Column.ATTACK: $Center/Pair/OptionsRow/AttackBox,
	Column.SUPPORT: $Center/Pair/OptionsRow/SupportBox,
	Column.ABILITY: $Center/Pair/OptionsRow/AbilityBox,
	Column.ITEM: $Center/Pair/OptionsRow/ItemBox,
}

# A VBoxContainer de cada coluna onde as Labels de opção são inseridas.
@onready var picker_lists: Dictionary = {
	Column.ATTACK: $Center/Pair/OptionsRow/AttackBox/MarginContainer/PickerContent/PickerScroll/PickerList,
	Column.SUPPORT: $Center/Pair/OptionsRow/SupportBox/MarginContainer/PickerContent/PickerScroll/PickerList,
	Column.ABILITY: $Center/Pair/OptionsRow/AbilityBox/MarginContainer/PickerContent/PickerScroll/PickerList,
	Column.ITEM: $Center/Pair/OptionsRow/ItemBox/MarginContainer/PickerContent/PickerScroll/PickerList,
}

# ScrollContainer de cada coluna (ver comentário grande que costumava viver
# aqui sobre o bug "the loadout screen needs to be scrollable" — agora cada
# uma das 4 colunas tem o próprio scroll independente, mesmo princípio,
# usado em _update_picker_visual() pra manter a opção realçada visível).
@onready var picker_scrolls: Dictionary = {
	Column.ATTACK: $Center/Pair/OptionsRow/AttackBox/MarginContainer/PickerContent/PickerScroll,
	Column.SUPPORT: $Center/Pair/OptionsRow/SupportBox/MarginContainer/PickerContent/PickerScroll,
	Column.ABILITY: $Center/Pair/OptionsRow/AbilityBox/MarginContainer/PickerContent/PickerScroll,
	Column.ITEM: $Center/Pair/OptionsRow/ItemBox/MarginContainer/PickerContent/PickerScroll,
}

var data: UnitData
var focus_column: Column = Column.SLOTS

var row_labels: Array[Label] = []
var selected_row: int = 0

# Estado POR COLUNA (chave = Column) — cada uma tem sua própria lista de
# opções, labels e índice selecionado, ao contrário do picker único de
# antes. null em column_options[col] == "-- vazio --" (mesma convenção de
# sempre).
var column_options: Dictionary = {}    # Column -> Array (ActionData ou null)
var column_labels: Dictionary = {}     # Column -> Array[Label]
var column_selected: Dictionary = {}   # Column -> int

func setup(unit_data: UnitData) -> void:
	data = unit_data
	title_label.text = "%s   Lv.%d — Loadout" % [data.unit_name.to_upper(), data.level]
	while data.slots.size() < SLOT_COUNT:
		data.slots.append(null)
	_build_rows()
	_refresh_rows()
	# As colunas de opções já nascem preenchidas (pro slot 0, selected_row
	# default) — tudo abre JUNTO, não uma coluna depois da outra.
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
# Usado tanto na lista dos 6 slots quanto nas colunas de opções, pra o
# jogador ver de cara qual Habilidade é a Hidden antes de equipar.
func _display_name(action: ActionData) -> String:
	if action is AbilityData and data.is_ability_hidden(action):
		return "%s (Hidden)" % action.action_name
	return action.action_name

# Em qual coluna uma ActionData cai — pedido do usuário: "Attack has attacks
# and special attacks. Support has status moves. Ability has Abilities".
# AttackData.is_status já distingue Attack de Support (mesmo campo usado
# em todo o resto do projeto, ver battle.gd::execute_attack vs
# execute_status_attack) — não interessa se é físico ou especial, os dois
# vão pra Attack, só status vai pra Support. Item nunca vem do learnset
# (ver comentário grande de show_item_column em _refresh_picker_options),
# então cai aqui só quando alguém já equipou um Item nesse slot por fora
# (Bag).
func _column_for_action(action: ActionData) -> Column:
	if action is ItemData:
		return Column.ITEM
	if action is AbilityData:
		return Column.ABILITY
	if action is AttackData:
		return Column.SUPPORT if action.is_status else Column.ATTACK
	return Column.ATTACK

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
		_step_column(-1)
	elif event.is_action_pressed("ui_right"):
		_step_column(1)
	elif focus_column == Column.SLOTS:
		_handle_slots_input(event)
		return
	else:
		_handle_options_input(event, focus_column)
		return
	get_viewport().set_input_as_handled()

# Anel de colunas VISÍVEIS agora — na prática todas (Item virou permanente,
# ver comentário grande no topo do arquivo), mas o filtro continua aqui por
# segurança/genericidade, caso alguma coluna volte a ser condicional no
# futuro.
func _visible_ring() -> Array:
	var ring: Array = []
	for col in COLUMN_RING:
		if col == Column.ITEM and not picker_boxes[Column.ITEM].visible:
			continue
		ring.append(col)
	return ring

# Anda `delta` passos (±1) no anel de colunas visíveis, a partir da coluna
# com foco agora — pedido do usuário: "Left/right cycles Slots -> Attack ->
# Support -> Ability -> back to Slots". Se a coluna com foco não estiver
# mais no anel (ex: era Item e ela acabou de sumir), recomeça do início.
func _step_column(delta: int) -> void:
	var ring = _visible_ring()
	var idx = ring.find(focus_column)
	if idx == -1:
		idx = 0
	idx = wrapi(idx + delta, 0, ring.size())
	focus_column = ring[idx]
	_refresh_all_picker_visuals()

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
		# direita, avança o foco 1 passo no anel (cai em Attack, a
		# primeira coluna de opções — já populada, não tem "abrir" nenhum
		# aqui).
		_step_column(1)
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _handle_options_input(event: InputEvent, col: Column) -> void:
	var options: Array = column_options.get(col, [])
	if options.is_empty():
		return
	if event.is_action_pressed("ui_down"):
		column_selected[col] = wrapi(column_selected[col] + 1, 0, options.size())
		_update_picker_visual(col)
	elif event.is_action_pressed("ui_up"):
		column_selected[col] = wrapi(column_selected[col] - 1, 0, options.size())
		_update_picker_visual(col)
	elif event.is_action_pressed("confirm"):
		_choose_picker_option(col)
		focus_column = Column.SLOTS
		# _choose_picker_option já chama _refresh_picker_options() (repinta
		# tudo) por conta própria, mas ISSO roda ANTES da linha de cima
		# mudar focus_column — o repaint de lá ainda usou o `col` antigo
		# como foco. Precisa de mais um agora que focus_column já é SLOTS,
		# senão a coluna recém-escolhida ficava "presa" em amarelo.
		_refresh_all_picker_visuals()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		# Só tira o foco de volta pros slots — NÃO fecha a tela (isso só
		# acontece com cancel/menu já com o foco em slots, ver
		# _handle_slots_input). As opções continuam abertas, do lado.
		focus_column = Column.SLOTS
		_refresh_all_picker_visuals()
	else:
		return
	get_viewport().set_input_as_handled()

# "-- vazio --" (null) sempre é a primeira opção de CADA coluna, pra
# desequipar o slot ser tão fácil quanto trocar ele, não importa em qual
# coluna o jogador está — sem precisar de um botão "remover" à parte.
#
# Ações já equipadas em OUTRO slot ficam de fora de TODAS as listas — não
# faz sentido a mesma unidade carregar "Tackle" duas vezes. O slot
# SELECIONADO agora é EXCLUÍDO dessa checagem (senão a própria ação atual
# dele desapareceria da lista e escolher "a mesma de novo" ficaria
# impossível).
#
# Chamada toda vez que selected_row muda (troca de slot no mouse ou nas
# setas) — todas as colunas ficam abertas o tempo todo, então cada uma
# precisa se manter em dia sozinha, não só numa hora de "abrir" pontual.
func _refresh_picker_options() -> void:
	var equipped_elsewhere: Array = []
	for i in SLOT_COUNT:
		if i != selected_row and data.slots[i] != null:
			equipped_elsewhere.append(data.slots[i])

	var current = data.slots[selected_row]

	for col in OPTION_COLUMNS:
		column_options[col] = [null]

	for action in data.get_available_actions(data.level):
		if equipped_elsewhere.has(action):
			continue
		var col = _column_for_action(action)
		column_options[col].append(action)

	# Held Items (ver GameState.get_items_in_category) — pedido do usuário:
	# "Make the 'Item' column on loadout screen permanent, and show all
	# 'Held Items' options". ANTES a coluna Item só existia pra mostrar o
	# item que a unidade JÁ carregava (dado pela Bag por fora, ver o bloco
	# "current != null" logo abaixo) — nunca listava o resto do inventário
	# pra ESCOLHER um novo aqui dentro. Itens nunca vêm do learnset (ver
	# get_available_actions/_column_for_action), então precisam da própria
	# fonte: get_items_in_category já filtra só o que o jogador REALMENTE
	# possui (quantidade > 0). Mesmo filtro "equipado em outro slot" de cima
	# também vale aqui — não faz sentido a mesma unidade segurar dois Focus
	# Band ao mesmo tempo, e mais importante: cada Held Item só existe 1x no
	# inventário até ser devolvido (ver _choose_picker_option abaixo).
	for item in GameState.get_items_in_category("Held Items"):
		if equipped_elsewhere.has(item):
			continue
		column_options[Column.ITEM].append(item)

	# `current` pode ser um Item dado pela Bag (ver GameState.give_item,
	# nunca vem do learnset) ou uma Habilidade Hidden ainda não revelada
	# (ver UnitData.get_available_actions/hidden_ability_revealed, que já
	# filtrou ela da lista normal) — nos dois casos, força ele na coluna
	# certa mesmo caindo fora da lista normal daquela coluna. Sem isso, o
	# slot atual simplesmente NÃO apareceria em lugar nenhum, o cursor
	# cairia em "-- vazio --" por padrão, e escolher ali (achando que só
	# estava olhando) apagaria a ação.
	if current != null:
		var current_col = _column_for_action(current)
		if not column_options[current_col].has(current):
			column_options[current_col].append(current)

	# Coluna Item — ANTES só aparecia quando o slot selecionado já era um
	# Item (comentário antigo: "Small 4th Item slot/column, only shown when
	# relevant"). Pedido do usuário agora: "Make the 'Item' column on
	# loadout screen permanent" — sempre visível, os 4 painéis (Attack/
	# Support/Ability/Item) dividem o espaço o tempo todo, não só às vezes.
	picker_boxes[Column.ITEM].visible = true

	for col in OPTION_COLUMNS:
		var selected = 0
		for i in column_options[col].size():
			if column_options[col][i] == current:
				selected = i
				break
		column_selected[col] = selected

		for child in picker_lists[col].get_children():
			child.queue_free()
		var labels: Array[Label] = []
		for i in column_options[col].size():
			var action = column_options[col][i]
			var label = Label.new()
			label.text = "-- vazio --" if action == null else _display_name(action)
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			label.mouse_entered.connect(_on_picker_mouse_entered.bind(col, i))
			label.gui_input.connect(_on_picker_gui_input.bind(col, i))
			picker_lists[col].add_child(label)
			labels.append(label)
		column_labels[col] = labels

	for col in OPTION_COLUMNS:
		_update_picker_visual(col)

func _on_picker_mouse_entered(col: Column, index: int) -> void:
	focus_column = col
	column_selected[col] = index
	# Todas, não só `col` — a coluna que TINHA o foco antes (mouse veio de
	# outra coluna, ou dos Slots) precisa perder o amarelo dela também.
	_refresh_all_picker_visuals()

func _on_picker_gui_input(event: InputEvent, col: Column, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		focus_column = col
		column_selected[col] = index
		_choose_picker_option(col)

# Pedido do usuário (2026-08-04): "When selecting a loadout item, only
# highlight in yellow the column exactly where the player is" — ANTES cada
# coluna pintava sua própria opção realçada de amarelo o tempo TODO, mesmo
# as 3 colunas que não tinham foco nenhum (dava a impressão de "4 seleções
# ativas ao mesmo tempo"). Agora só pinta se ESTA coluna (col) for a que
# está com focus_column agora — as outras 3 caem pra WHITE (sem destaque
# nenhum), mesmo com column_selected[col] continuando guardado por baixo
# (não esquece a posição, só para de mostrar enquanto sem foco).
func _update_picker_visual(col: Column) -> void:
	var labels: Array = column_labels.get(col, [])
	var selected: int = column_selected.get(col, 0)
	var has_focus = col == focus_column
	for i in labels.size():
		labels[i].modulate = Color.YELLOW if (has_focus and i == selected) else Color.WHITE
	# Rola a lista sozinha pra manter a opção realçada visível — sem isso,
	# navegar com as setas além do que cabe na tela deixava o cursor "sumir"
	# por trás da borda do ScrollContainer, mesmo bug reportado pelo usuário
	# (agora vale por coluna, cada uma com o próprio scroll).
	if selected >= 0 and selected < labels.size():
		picker_scrolls[col].ensure_control_visible(labels[selected])

# Repinta as 4 colunas de opções de uma vez — precisa rodar toda vez que
# focus_column MUDA (não só quando a seleção DENTRO de uma coluna muda),
# senão a coluna que ACABOU de perder o foco ficava com o amarelo "grudado"
# de antes, já que _update_picker_visual(col) sozinha só sabe repintar UMA
# coluna por chamada.
func _refresh_all_picker_visuals() -> void:
	for col in OPTION_COLUMNS:
		_update_picker_visual(col)

func _choose_picker_option(col: Column) -> void:
	var old_action = data.slots[selected_row]
	var new_action = column_options[col][column_selected[col]]
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
	# Espelho do bloco de cima: escolher um Held Item NOVO direto da coluna
	# Item (ver GameState.get_items_in_category("Held Items") em
	# _refresh_picker_options) tira ele do inventário — mesma semântica de
	# "Give" pela Bag (ver item_list_screen.gd/GameState.give_item), só que
	# disparada daqui agora que a coluna deixou de só EXIBIR o item já
	# equipado e passou a deixar ESCOLHER um novo. Held Items nunca são
	# Stackable (ver comentário grande de ItemData.stackable — só Ball/TM
	# são), então é sempre exatamente 1 saindo do inventário.
	if new_action is ItemData and new_action != old_action:
		GameState.remove_item(new_action, 1)
	_refresh_rows()
	# A ação escolhida pode ter mudado o que "equipado em outro slot"
	# exclui, e/ou mudado se a coluna Item deveria aparecer — reconstrói
	# TODAS as colunas de opções também, já apontando pra elas como a nova
	# "atual" do slot.
	_refresh_picker_options()

func _close() -> void:
	closed.emit()
	queue_free()
