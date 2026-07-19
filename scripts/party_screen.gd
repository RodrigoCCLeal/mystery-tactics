extends CanvasLayer

# Tela de Party — grid de 2 colunas x 3 linhas dos 6 slots do time
# (GameState.roster, ver comentário em game_state.gd sobre por que o roster
# mora no autoload em vez de em battle.gd): retrato (animação idle_down),
# nome, nível, barra de HP e barra de XP. SEM arte customizada — só
# Panel/Label/ColorRect do tema padrão do Godot (o usuário removeu do
# projeto o conjunto de imagens que era usado antes).
#
# Aberta pela opção "Pokémon" do menu de pausa (ver
# pause_menu.gd::_open_party_screen), que pausa o jogo por baixo — mesmo
# princípio do próprio menu de pausa (ver comentário process_mode lá).
#
# Layout dos slots: coluna esquerda = 0,1,2 (de cima pra baixo), coluna
# direita = 3,4,5. O GridContainer em si preenche linha por linha (0 e 3 na
# mesma linha, depois 1 e 4, depois 2 e 5) — é por isso que _build_slots()
# adiciona os nodes numa ordem intercalada em vez da ordem 0..5 direto; o
# ÍNDICE de cada slot continua batendo com a posição no roster o tempo todo,
# só a ORDEM DE INSERÇÃO na árvore muda pra dar esse efeito visual de duas
# colunas.
#
# Navegação: setas movem o cursor pelas 4 direções entre os 6 slots (ver
# NEIGHBOR_*). X num slot preenchido abre um popup (slot_action_menu.tscn)
# com 3 opções: "Switch" entra no modo de troca (picked_index != -1 — X de
# novo em outro slot troca as duas posições via GameState.swap_roster_slots,
# X no mesmo slot cancela), "Summary" abre unit_summary.tscn (atributos,
# somente leitura) e "Loadout" abre unit_loadout.tscn (escolher
# ataque/habilidade/item de cada um dos 6 slots de ação da unidade). Z fecha
# a troca em andamento ou, se nada estiver acontecendo, fecha a tela de
# Party inteira.
#
# active_submenu guarda qual popup/tela filha está aberta por cima agora (só
# um de cada vez) — enquanto ele existir, _unhandled_input daqui nem
# processa nada, pra não competir com o input do filho.

signal closed

# Modo alternativo de uso, além do normal (Pokémon do menu de pausa): a Bag
# usa esta MESMA tela pra deixar o jogador escolher a unidade alvo de um
# item (Use cura, Give equipa — ver item_list_screen.gd). Quem abre a tela
# liga picker_mode = true (e opcionalmente troca picker_prompt) ANTES de
# add_child() — como _ready() só roda depois de entrar na árvore, o valor já
# está certo a tempo. Nesse modo, X num slot preenchido não abre o popup de
# Switch/Summary/Loadout: só emite unit_picked com o índice escolhido e
# fecha a tela — Switch fica completamente desligado (não faria sentido
# trocar unidades de posição enquanto se escolhe o alvo de um item).
signal unit_picked(index: int)
var picker_mode: bool = false
var picker_prompt: String = "Escolha o alvo.   (Z: cancelar)"

# Filtro opcional pra picker_mode: recebe a UnitData de um slot preenchido,
# retorna se ela é um alvo VÁLIDO (ex: item_list_screen.gd usa isso pra
# barrar Potion/Oran Berry num alvo com HP já cheio — "se o item não vai
# fazer nada, ele não pode ser usado"). Callable() vazia (padrão) = sem
# filtro, todo slot preenchido é válido, igual sempre foi. Slot que falha o
# filtro continua VISÍVEL (só fica meio apagado, ver _refresh_slot) — X
# nele simplesmente não faz nada, mesmo comportamento de tentar confirmar
# um slot vazio.
var picker_filter: Callable = Callable()
var picker_filter_hint: String = ""

const UnitScript = preload("res://scripts/unit.gd")
const ExpGroups = preload("res://scripts/exp_groups.gd")

const SLOT_ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/popups/slot_action_menu.tscn")
const UNIT_SUMMARY_SCENE: PackedScene = preload("res://scenes/ui/screens/unit_summary.tscn")
const UNIT_LOADOUT_SCENE: PackedScene = preload("res://scenes/ui/screens/unit_loadout.tscn")
const EVOLUTION_CHOICE_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/popups/evolution_choice_screen.tscn")
# Mesma caixa de 1 linha que trainer.gd/loot_ball.gd já usam pra mensagem
# rápida + esperar X/Z — reaproveitada aqui só pro aviso de "não coube o
# peso" (ver _attempt_evolution).
const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")

const SLOT_COUNT = 6
const PORTRAIT_SIZE = 48.0
const HP_BAR_SIZE = Vector2(90, 10)
const XP_BAR_SIZE = Vector2(90, 6)

# Coluna esquerda (0,1,2) / coluna direita (3,4,5) — ver comentário grande
# no topo do arquivo sobre a ordem de inserção no GridContainer.
const BUILD_ORDER = [0, 3, 1, 4, 2, 5]

const NEIGHBOR_DOWN = {0: 1, 1: 2, 2: 0, 3: 4, 4: 5, 5: 3}
const NEIGHBOR_UP = {0: 2, 1: 0, 2: 1, 3: 5, 4: 3, 5: 4}
const NEIGHBOR_RIGHT = {0: 3, 1: 4, 2: 5}
const NEIGHBOR_LEFT = {3: 0, 4: 1, 5: 2}

# Mesmas faixas/cores de unit.gd::update_health_bar() (a barra de vida da
# batalha) — pedido explícito do usuário: "mesmas regras" nos dois lugares.
const HEALTH_COLOR_HIGH = Color(0.2, 0.85, 0.2, 1)
const HEALTH_COLOR_MID = Color(0.9, 0.85, 0.2, 1)
const HEALTH_COLOR_LOW = Color(0.85, 0.2, 0.2, 1)
const BAR_COLOR_BACK = Color(0.15, 0.15, 0.15, 1)
const XP_COLOR = Color(0.3, 0.55, 0.95, 1)

const ROW_STYLE_NORMAL = Color(0, 0, 0, 0)          # transparente
const ROW_STYLE_SELECTED = Color(1, 1, 0.3, 0.25)   # amarelo fraco — cursor
const ROW_STYLE_PICKED = Color(0.3, 0.6, 1, 0.35)   # azul — "na mão" (Switch)
const ROW_STYLE_SWAP_TARGET = Color(0.3, 1, 0.4, 0.3) # verde — destino da troca

@onready var rows_container: GridContainer = $Center/Panel/MarginContainer/Content/Rows
@onready var prompt_label: Label = $Center/Panel/MarginContainer/Content/Prompt

var slot_nodes: Array[PanelContainer] = []
var selected_index: int = 0
var picked_index: int = -1
var active_submenu: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_slots()
	_refresh_all()

func _unhandled_input(event: InputEvent) -> void:
	if active_submenu != null:
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(NEIGHBOR_DOWN)
	elif event.is_action_pressed("ui_up"):
		_move_selection(NEIGHBOR_UP)
	elif event.is_action_pressed("ui_right"):
		_move_selection(NEIGHBOR_RIGHT)
	elif event.is_action_pressed("ui_left"):
		_move_selection(NEIGHBOR_LEFT)
	elif event.is_action_pressed("confirm"):
		_activate_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_on_cancel_pressed()
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(neighbors: Dictionary) -> void:
	if neighbors.has(selected_index):
		selected_index = neighbors[selected_index]
		_refresh_all()

# Em troca (picked_index != -1): X no mesmo slot cancela, em outro slot
# troca de verdade. Fora de troca: X num slot preenchido abre o popup de
# ações (Switch/Summary/Loadout); num slot vazio não faz nada.
func _activate_selected() -> void:
	if picker_mode:
		var picked_data = GameState.get_roster_slot(selected_index)
		if picked_data == null:
			return
		if picker_filter.is_valid() and not picker_filter.call(picked_data):
			return
		unit_picked.emit(selected_index)
		closed.emit()
		queue_free()
		return

	if picked_index != -1:
		if picked_index == selected_index:
			picked_index = -1
		else:
			GameState.swap_roster_slots(picked_index, selected_index)
			picked_index = -1
		_refresh_all()
		return

	var data = GameState.get_roster_slot(selected_index)
	if data == null:
		return
	_open_slot_action_menu(selected_index, data)

func _on_cancel_pressed() -> void:
	if picked_index != -1:
		picked_index = -1
		_refresh_all()
	else:
		closed.emit()
		queue_free()

func _open_slot_action_menu(index: int, data: UnitData) -> void:
	var menu = SLOT_ACTION_MENU_SCENE.instantiate()
	add_child(menu)
	menu.setup(data.unit_name, _get_available_evolutions(data).size() > 0)
	active_submenu = menu
	menu.closed.connect(_on_slot_action_menu_closed.bind(index))

func _on_slot_action_menu_closed(option: String, index: int) -> void:
	active_submenu = null
	match option:
		"Switch":
			picked_index = index
			_refresh_all()
		"Summary":
			_open_summary(index)
		"Loadout":
			_open_loadout(index)
		"Evolve":
			_try_evolve(index)

# Checa os pré-requisitos (nível mínimo, ação equipada — ver
# evolution_option.gd) de CADA EvolutionOption em data.evolution_options e
# devolve só as que estão satisfeitas AGORA. Pode devolver 0 (não evolui
# ainda, ou não evolui nunca — evolution_options vazio), 1 (evolução
# normal, direto — ver _try_evolve) ou 2+ (evolução COM ESCOLHA, abre
# evolution_choice_screen.tscn). min_level <= 0 e requires_action == null
# contam como "sem exigência", igual sempre.
func _get_available_evolutions(data: UnitData) -> Array[EvolutionOption]:
	var available: Array[EvolutionOption] = []
	if data == null:
		return available
	for option in data.evolution_options:
		if option == null or option.target == null:
			continue
		if option.min_level > 0 and data.level < option.min_level:
			continue
		if option.requires_action != null and not data.slots.has(option.requires_action):
			continue
		available.append(option)
	return available

# Ponto de entrada de "Evolve" no popup de slot (ver
# _on_slot_action_menu_closed) — decide sozinho entre evoluir DIRETO (1
# opção disponível, mesmo comportamento de sempre) ou abrir a tela de
# escolha (2+ disponíveis ao mesmo tempo). Pedido do usuário: "a unit might
# be able to evolve into different options. when able to evolve, show a
# selection screen with the evolution options" — a tela só existe quando há
# de fato uma escolha a fazer, não pra toda evolução.
func _try_evolve(index: int) -> void:
	var data: UnitData = GameState.get_roster_slot(index)
	if data == null:
		return
	var options := _get_available_evolutions(data)
	if options.is_empty():
		return
	if options.size() == 1:
		_attempt_evolution(index, options[0].target)
		return
	_open_evolution_choice(index, data, options)

func _open_evolution_choice(index: int, data: UnitData, options: Array[EvolutionOption]) -> void:
	var names: Array[String] = []
	for option in options:
		names.append(option.target.unit_name)
	var screen = EVOLUTION_CHOICE_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(data.unit_name, names)
	active_submenu = screen
	screen.closed.connect(_on_evolution_choice_closed.bind(index, options))

func _on_evolution_choice_closed(chosen_index: int, index: int, options: Array[EvolutionOption]) -> void:
	active_submenu = null
	if chosen_index < 0 or chosen_index >= options.size():
		return   # Z/cancelado — nenhuma opção escolhida, nada acontece.
	_attempt_evolution(index, options[chosen_index].target)

# Última checagem antes de evoluir de verdade (ver _perform_evolution) —
# pedido do usuário: "show an error message and stop the player from
# evolving if it would exceed the weight limit". get_roster_weight() JÁ
# inclui o peso ATUAL da unidade evoluindo (ela está no roster agora), por
# isso a conta é "peso total - peso antigo + peso novo" (a DIFERENÇA), não
# "peso total + peso novo" — senão toda evolução pareceria estar somando um
# peso extra inteiro em vez de só a diferença entre as duas espécies.
func _attempt_evolution(index: int, target: UnitData) -> void:
	var data: UnitData = GameState.get_roster_slot(index)
	if data == null or target == null:
		return
	var projected_weight = GameState.get_roster_weight() - data.weight + target.weight
	if projected_weight > GameState.MAX_TEAM_WEIGHT:
		_show_evolution_error("%s is too heavy to evolve into %s right now!" % [data.unit_name, target.unit_name])
		return
	_perform_evolution(index, target)

# Reaproveita trainer_message_box.tscn (ver MESSAGE_BOX_SCENE) — o sinal
# "closed" dele não tem argumento nenhum, mesma assinatura de
# _on_child_screen_closed() (usado por Summary/Loadout), então dá pra
# conectar direto sem bind nenhum.
func _show_evolution_error(text: String) -> void:
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(text)
	active_submenu = box
	box.closed.connect(_on_child_screen_closed)

# Evolui a unidade do slot `index` de verdade — chamado só depois que
# _attempt_evolution() já aprovou o peso (ver acima), com `target` já
# resolvido por quem chamou (_try_evolve, direto ou via
# _on_evolution_choice_closed). Troca a ESPÉCIE (stats base, sprite,
# learnset, tipos, a própria evolution_options pra permitir uma CADEIA de
# evoluções, ex: Swinub -> Piloswine -> Mamoswine) preservando o que é da
# UNIDADE, não da espécie:
# nível, xp, loadout equipado (slots) e quantas cargas de item empilhável
# cada slot ainda tem (slot_quantities). HP máximo é recalculado com as
# stats da NOVA espécie, e o HP atual ganha a MESMA diferença (new_max -
# old_max) somada ao que já tinha — é assim que evolução funciona nos jogos
# originais: dano sofrido continua contando, mas o aumento de HP máximo
# vira HP disponível na hora, sem curar tudo de graça nem perder o dano já
# levado.
#
# Duas correções que vieram junto (pedidas explicitamente pelo usuário,
# valem pra QUALQUER cadeia de evolução, não só uma espécie específica):
#
# 1) hidden_ability_revealed é da UNIDADE (progresso de Ability Patch), não
#    da espécie — precisa sobreviver à evolução mesmo se a NOVA espécie não
#    tiver Habilidade Hidden nenhuma pra mostrar agora (ex: Metapod não tem,
#    mas Caterpie tinha e Butterfree também tem — sem isso, evoluir pra
#    Metapod "esqueceria" que o Ability Patch já foi usado, e Butterfree
#    nasceria bloqueado de novo).
#
# 2) slots (loadout equipado) é copiado da unidade antiga, mas só HABILIDADE
#    (AbilityData) equipada é limpa se a NOVA espécie não souber ela (mesmo
#    critério de LearnsetEntry.action, comparado por instância — ver
#    is_ability_hidden()/get_available_actions() em unit_data.gd). Ex:
#    Caterpie com Run Away (Habilidade Hidden) equipado evolui pra Metapod,
#    que nem aprende Run Away — sem essa limpeza, Metapod ficaria com uma
#    Habilidade que não é dele.
#    ATAQUES (AttackData) e ITENS (ItemData) equipados NUNCA são removidos
#    aqui, mesmo que a nova espécie não os tenha no learnset — um ataque
#    aprendido por uma pré-evolução treinada continua equipado depois de
#    evoluir (é essa persistência que recompensa treinar uma unidade em vez
#    de simplesmente capturá-la já evoluída: ela pode chegar com movimentos
#    que a espécie evoluída não aprenderia sozinha). Só Habilidade troca de
#    espécie pra espécie.
func _perform_evolution(index: int, target: UnitData) -> void:
	var data: UnitData = GameState.get_roster_slot(index)
	if data == null or target == null:
		return
	var old_hp_max = _hp_max(data)
	var evolved: UnitData = target.duplicate()
	evolved.level = data.level
	evolved.xp = data.xp
	evolved.slots = data.slots.duplicate()
	evolved.slot_quantities = data.slot_quantities.duplicate()
	evolved.hidden_ability_revealed = data.hidden_ability_revealed
	for i in evolved.slots.size():
		var action: ActionData = evolved.slots[i]
		if action == null or not (action is AbilityData):
			continue
		var still_learnable = false
		for entry in evolved.learnset:
			if entry.action == action:
				still_learnable = true
				break
		if not still_learnable:
			evolved.slots[i] = null
	var new_hp_max = _hp_max(evolved)
	evolved.current_hp = clamp(data.current_hp + (new_hp_max - old_hp_max), 1, new_hp_max)
	# party_screen.gd não tem um log de mensagens igual battle.gd — o nome
	# novo já aparece sozinho na linha do slot (_refresh_slot lê
	# data.unit_name), isso aqui é só reforço pra quem estiver testando pelo
	# editor/console.
	print("%s evoluiu para %s!" % [data.unit_name, evolved.unit_name])
	GameState.set_roster_slot(index, evolved)
	_refresh_all()

func _open_summary(index: int) -> void:
	var data = GameState.get_roster_slot(index)
	if data == null:
		return
	var screen = UNIT_SUMMARY_SCENE.instantiate()
	add_child(screen)
	screen.setup(data)
	active_submenu = screen
	screen.closed.connect(_on_child_screen_closed)

func _open_loadout(index: int) -> void:
	var data = GameState.get_roster_slot(index)
	if data == null:
		return
	var screen = UNIT_LOADOUT_SCENE.instantiate()
	add_child(screen)
	screen.setup(data)
	active_submenu = screen
	screen.closed.connect(_on_child_screen_closed)

func _on_child_screen_closed() -> void:
	active_submenu = null
	_refresh_all()

# Monta os 6 nodes de linha uma vez só (chamado em _ready). slot_nodes[i]
# sempre corresponde ao slot i do roster, independente da ordem em que os
# nodes entram no GridContainer (ver BUILD_ORDER). O conteúdo (texto, cor
# da barra, destaque da linha...) é preenchido depois, em _refresh_slot() —
# trocar seleção não recria node nenhum, só atualiza.
func _build_slots() -> void:
	slot_nodes.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slot_nodes[i] = _build_row(i)
	for i in BUILD_ORDER:
		rows_container.add_child(slot_nodes[i])

func _build_row(index: int) -> PanelContainer:
	var row = PanelContainer.new()
	row.name = "Slot%d" % index
	var style = StyleBoxFlat.new()
	style.bg_color = ROW_STYLE_NORMAL
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", style)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(_on_slot_mouse_entered.bind(index))
	row.gui_input.connect(_on_slot_gui_input.bind(index))

	var hbox = HBoxContainer.new()
	hbox.name = "Row"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var portrait_box = Control.new()
	portrait_box.name = "PortraitBox"
	portrait_box.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(portrait_box)

	var portrait = AnimatedSprite2D.new()
	portrait.name = "Portrait"
	portrait.position = Vector2(PORTRAIT_SIZE / 2.0, PORTRAIT_SIZE / 2.0)
	portrait_box.add_child(portrait)

	var info = VBoxContainer.new()
	info.name = "Info"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(info)

	var top_row = HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(top_row)

	var name_label = Label.new()
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(name_label)

	var lv_label = Label.new()
	lv_label.name = "Level"
	lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(lv_label)

	info.add_child(_build_bar_row("HpRow", "HpBack", "HpFill", HP_BAR_SIZE, true))
	info.add_child(_build_bar_row("XpRow", "XpBack", "XpFill", XP_BAR_SIZE, false))

	return row

# Uma "linha de barra" (fundo escuro + preenchimento colorido por cima) —
# usado tanto pra HP quanto pra XP, só muda o tamanho e se tem número do
# lado (HP mostra "atual/máximo", XP não mostra número nenhum por enquanto).
# size_flags_vertical = SIZE_SHRINK_CENTER no fundo é o que evita ele esticar
# pra altura da linha inteira do HBoxContainer (sem isso, ficava mais alto
# que o preenchimento por cima, sobrando uma tarja escura embaixo do verde).
func _build_bar_row(row_name: String, back_name: String, fill_name: String, size: Vector2, with_numbers: bool) -> HBoxContainer:
	var bar_row = HBoxContainer.new()
	bar_row.name = row_name
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_theme_constant_override("separation", 8)

	var back = ColorRect.new()
	back.name = back_name
	back.custom_minimum_size = size
	back.color = BAR_COLOR_BACK
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(back)

	var fill = ColorRect.new()
	fill.name = fill_name
	fill.position = Vector2.ZERO
	fill.size = size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)

	if with_numbers:
		var numbers = Label.new()
		numbers.name = "Numbers"
		numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_row.add_child(numbers)

	return bar_row

func _on_slot_mouse_entered(index: int) -> void:
	selected_index = index
	_refresh_all()

func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_activate_selected()

func _refresh_all() -> void:
	for i in slot_nodes.size():
		_refresh_slot(i)
	if picker_mode:
		prompt_label.text = picker_prompt
	elif picked_index == -1:
		prompt_label.text = "Escolha um Pokémon.   (X: opções   Z: fechar)"
	else:
		prompt_label.text = "Escolha o slot pra trocar.   (X: trocar/cancelar   Z: cancelar)"

func _refresh_slot(index: int) -> void:
	var row = slot_nodes[index]
	var data: UnitData = GameState.get_roster_slot(index)
	row.modulate.a = 1.0

	var style = row.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = _row_color(index)

	var name_label = row.get_node("Row/Info/TopRow/Name") as Label
	var lv_label = row.get_node("Row/Info/TopRow/Level") as Label
	var hp_back = row.get_node("Row/Info/HpRow/HpBack") as ColorRect
	var hp_fill = row.get_node("Row/Info/HpRow/HpBack/HpFill") as ColorRect
	var hp_numbers = row.get_node("Row/Info/HpRow/Numbers") as Label
	var xp_back = row.get_node("Row/Info/XpRow/XpBack") as ColorRect
	var xp_fill = row.get_node("Row/Info/XpRow/XpBack/XpFill") as ColorRect
	var portrait = row.get_node("Row/PortraitBox/Portrait") as AnimatedSprite2D

	if data == null:
		name_label.text = "-- vazio --"
		lv_label.text = ""
		hp_back.visible = false
		hp_numbers.text = ""
		xp_back.visible = false
		portrait.visible = false
		return

	name_label.text = data.unit_name.to_upper()
	lv_label.text = "Lv.%d" % data.level

	# picker_mode com filtro (ver comentário no topo do arquivo): alvo
	# inválido pra este item continua visível, só meio apagado + com uma
	# dica no nome — não dá pra selecionar (ver _activate_selected), então
	# precisa ficar claro o porquê sem esconder a unidade da lista.
	if picker_mode and picker_filter.is_valid() and not picker_filter.call(data):
		row.modulate.a = 0.45
		if picker_filter_hint != "":
			name_label.text += " " + picker_filter_hint

	var hp_max = _hp_max(data)
	var hp_current = _hp_current(data)
	hp_numbers.text = "%d/%d" % [hp_current, hp_max]

	hp_back.visible = true
	var hp_ratio = clamp(float(hp_current) / float(max(hp_max, 1)), 0.0, 1.0)
	hp_fill.size = Vector2(HP_BAR_SIZE.x * hp_ratio, HP_BAR_SIZE.y)
	hp_fill.color = _health_color(hp_ratio)

	xp_back.visible = true
	var xp_ratio = ExpGroups.level_progress_ratio(data.level, data.xp, data.growth_group)
	xp_fill.size = Vector2(XP_BAR_SIZE.x * xp_ratio, XP_BAR_SIZE.y)
	xp_fill.color = XP_COLOR

	_refresh_portrait(portrait, data)

func _refresh_portrait(portrait: AnimatedSprite2D, data: UnitData) -> void:
	if data.sprite_frames == null or not data.sprite_frames.has_animation("idle_down"):
		portrait.visible = false
		return
	# Desmaiada (current_hp <= 0) usa a animação Sleep em vez de Idle — mesmo
	# fallback de sempre se a espécie não tiver "sleep_down" (ainda não
	# adicionamos Sleep-Anim.png a todo mundo).
	var anim_name = "idle_down"
	if data.current_hp <= 0 and data.sprite_frames.has_animation("sleep_down"):
		anim_name = "sleep_down"
	portrait.visible = true
	if portrait.sprite_frames != data.sprite_frames or portrait.animation != anim_name:
		portrait.sprite_frames = data.sprite_frames
		portrait.play(anim_name)
	elif not portrait.is_playing():
		portrait.play(anim_name)

	var frame_tex = data.sprite_frames.get_frame_texture("idle_down", 0)
	if frame_tex != null:
		var src_size = frame_tex.get_size()
		if src_size.x > 0 and src_size.y > 0:
			var scale_factor = min(PORTRAIT_SIZE / src_size.x, PORTRAIT_SIZE / src_size.y)
			portrait.scale = Vector2(scale_factor, scale_factor)

func _row_color(index: int) -> Color:
	var is_selected = selected_index == index
	var is_picked = picked_index == index
	var is_swap_target = picked_index != -1 and picked_index != index and is_selected
	if is_picked:
		return ROW_STYLE_PICKED
	if is_swap_target:
		return ROW_STYLE_SWAP_TARGET
	if is_selected:
		return ROW_STYLE_SELECTED
	return ROW_STYLE_NORMAL

# Mesmas faixas de unit.gd::update_health_bar(): >50% verde, 26-50%
# amarelo, <=25% vermelho.
func _health_color(ratio: float) -> Color:
	if ratio < 0.25:
		return HEALTH_COLOR_LOW
	if ratio < 0.5:
		return HEALTH_COLOR_MID
	return HEALTH_COLOR_HIGH

# HP máximo no NÍVEL ATUAL da unidade (data.level, persistido — ver
# UnitData.ensure_initialized), mesma fórmula usada de verdade em batalha
# (ver Unit.calc_hp_static).
func _hp_max(data: UnitData) -> int:
	return UnitScript.calc_hp_static(data.hp_base, data.level, data.weight)

# HP atual persistido (ver Unit.sync_to_data, chamado a cada dano/level up
# durante a batalha — como data é a mesma instância guardada em
# GameState.roster, esse valor já reflete o fim da última batalha sem
# precisar de nenhum passo extra de "salvar").
func _hp_current(data: UnitData) -> int:
	return max(data.current_hp, 0)
