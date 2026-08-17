extends CanvasLayer

# Tela do PC — aberta pela opção do computer_screen.gd. Três painéis:
# time ativo (esquerda, sempre 6 slots — GameState.roster, incl. vazios),
# reserva (meio — GameState.storage OU GameState.giovanni_storage, ver
# reserve_mode logo abaixo — grade larga de slots, a maioria vazia até
# existir alguma forma de conseguir mais unidades), e atributos da unidade
# sob o MOUSE (direita — prévia ao vivo, atualiza a cada hover).
#
# A reserva é grande demais (GameState.STORAGE_CAPACITY) pra mostrar de uma
# vez só — por isso vira BOX_COUNT "abas"/páginas de SLOTS_PER_BOX cada
# (ver comentário em GameState.storage), navegáveis pelos botões </> ao
# lado do rótulo "Box N". current_box aqui é só um índice de exibição —
# GameState.storage continua um array flat único; o índice ABSOLUTO de um
# slot da reserva (usado em setup()/dropped/GameState.get_storage_slot) é
# sempre current_box * GameState.SLOTS_PER_BOX + posição local na grade.
#
# Mover funciona tanto com o MOUSE (arrastar um PcSlot, ver pc_slot.gd, e
# soltar em cima de outro) quanto com TECLADO (setas movem um cursor único
# entre time e reserva, X "pega"/"solta" a unidade sob o cursor, Z cancela
# a seleção em andamento ou fecha a tela) — os dois métodos convergem pro
# mesmo _perform_move(), então trocar de posição dá exatamente no mesmo
# lugar (GameState.swap_roster_slots/swap_storage_slots/
# swap_active_with_storage) não importa como foi disparado.
#
# Só UM slot fica destacado por vez (cursor_column/cursor_index, via
# PcSlot.set_highlighted) — o mesmo destaque usado pelo hover do mouse
# (_on_slot_hovered só sincroniza cursor_column/cursor_index com o slot sob
# o ponteiro) E pela navegação por teclado (_move_cursor). Não existe uma
# cor separada pra "isso está selecionado pra mover" — só o texto do prompt
# muda (ver _update_prompt): já é suficiente pra confirmar a seleção sem
# precisar de um segundo estado visual.

signal closed

const UnitScript = preload("res://scripts/unit.gd")

const RESERVE_COLUMNS = 8
const ATTR_PORTRAIT_SIZE = 64.0

# Popup de opções ao CLICAR/confirmar num slot preenchido (pedido do
# usuário: "When a unit is clicked, some options should pop up: Summary,
# Switch... Release") — mesmo popup que party_screen.gd já usa, com
# Loadout/Evolve desligados e Release ligado (ver setup() em
# slot_action_menu.gd e _open_slot_action_menu abaixo).
const SLOT_ACTION_MENU_SCENE: PackedScene = preload("res://scenes/ui/popups/slot_action_menu.tscn")
const UNIT_SUMMARY_SCENE: PackedScene = preload("res://scenes/ui/screens/unit_summary.tscn")
const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")

# Qual reserva a coluna do meio mostra: "storage" (padrão, reserva normal do
# jogador, ver GameState.storage), "giovanni" (GameState.giovanni_storage —
# "Giovanni's Account", unidades roubadas por treinadores Rocket, ver
# battle.gd::resolve_capture), "baldo" (GameState.baldo_storage —
# "Baldo's Account", 1 de cada espécie nível 100, ver GameState.
# _seed_baldo_storage) ou "heaven" (GameState.heaven_storage — "Heaven
# Account", unidades que sofreram permadeath no modo Challenge, ver
# battle.gd::_apply_challenge_permadeath). Quem abre esta cena seta isso
# ANTES dela entrar na árvore (ver computer_screen.gd::_open_pc_screen) — o
# resto do arquivo nunca lê GameState.storage/giovanni_storage/
# baldo_storage/heaven_storage direto, só chama os 3 wrappers _reserve_*
# logo abaixo, que decidem qual reserva de verdade usar com base neste
# campo. Isso é o que deixa a MESMA cena/script servir as quatro contas,
# igual house_interior.gd serve qualquer interior.
@export_enum("storage", "giovanni", "baldo", "heaven") var reserve_mode: String = "storage"

func _reserve_get_slot(index: int) -> UnitData:
	match reserve_mode:
		"giovanni":
			return GameState.get_giovanni_slot(index)
		"baldo":
			return GameState.get_baldo_slot(index)
		"heaven":
			return GameState.get_heaven_slot(index)
		_:
			return GameState.get_storage_slot(index)

func _reserve_swap_slots(a: int, b: int) -> void:
	match reserve_mode:
		"giovanni":
			GameState.swap_giovanni_slots(a, b)
		"baldo":
			GameState.swap_baldo_slots(a, b)
		"heaven":
			GameState.swap_heaven_slots(a, b)
		_:
			GameState.swap_storage_slots(a, b)

func _reserve_swap_active(active_index: int, reserve_index: int) -> void:
	match reserve_mode:
		"giovanni":
			GameState.swap_active_with_giovanni(active_index, reserve_index)
		"baldo":
			GameState.swap_active_with_baldo(active_index, reserve_index)
		"heaven":
			GameState.swap_active_with_heaven(active_index, reserve_index)
		_:
			GameState.swap_active_with_storage(active_index, reserve_index)

@onready var team_rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Columns/TeamColumn/TeamRows
@onready var reserve_grid_container: GridContainer = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/ReserveGrid
@onready var box_label: Label = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/BoxNav/BoxLabel
@onready var prev_box_button: Button = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/BoxNav/PrevButton
@onready var next_box_button: Button = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/BoxNav/NextButton
@onready var attr_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Columns/AttributesPanel/AttrMargin/AttrContent
@onready var prompt_label: Label = $Center/Panel/MarginContainer/Content/Prompt

var highlighted_slot: PcSlot = null
var current_box: int = 0

# Posição do cursor (mouse OU teclado, os dois escrevem aqui — ver
# _on_slot_hovered/_move_cursor). "team" 0..5, "reserve" é sempre o índice
# ABSOLUTO dentro de GameState.storage, igual todo índice de reserva neste
# arquivo (ver comentário grande no topo).
var cursor_column: String = "team"
var cursor_index: int = 0

# "" / -1 = ninguém em modo Switch agora. Entra em modo Switch só através
# da opção "Switch" do popup (ver _on_slot_action_menu_closed) — DIFERENTE
# de antes (X direto num slot já "pegava" a unidade); agora X/clique num
# slot preenchido abre o popup primeiro (ver _activate_cursor). switching_*
# != "" faz X/clique num slot IR DIRETO pro _perform_move (ou cancelar, se
# for o mesmo slot já escolhido), sem abrir o popup de novo no meio da troca
# — mesma UX de party_screen.gd::picked_index.
var switching_column: String = ""
var switching_index: int = -1
# Nó atualmente pintado de azul (ver PcSlot.set_picked) — guardado à parte
# de highlighted_slot (cursor, amarelo) porque os dois podem apontar pra
# slots DIFERENTES ao mesmo tempo (escolheu Switch num slot e moveu o
# cursor pra outro lugar procurando o destino).
var switching_slot_node: PcSlot = null

# Só um popup/tela filha aberta por vez (Summary, o menu de ações, o
# Sim/Não de Release) — mesmo padrão de party_screen.gd::active_submenu:
# enquanto existir, _unhandled_input nem processa nada daqui, pra não
# competir com o input do filho.
var active_submenu: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reserve_grid_container.columns = RESERVE_COLUMNS
	prev_box_button.pressed.connect(_on_prev_box_pressed)
	next_box_button.pressed.connect(_on_next_box_pressed)
	_build_all()

func _unhandled_input(event: InputEvent) -> void:
	if active_submenu != null:
		return
	if event.is_action_pressed("ui_down"):
		_move_cursor_by(Vector2i(0, 1))
	elif event.is_action_pressed("ui_up"):
		_move_cursor_by(Vector2i(0, -1))
	elif event.is_action_pressed("ui_left"):
		_move_cursor_by(Vector2i(-1, 0))
	elif event.is_action_pressed("ui_right"):
		_move_cursor_by(Vector2i(1, 0))
	elif event.is_action_pressed("confirm"):
		_activate_cursor()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_on_cancel_pressed()
	else:
		return
	get_viewport().set_input_as_handled()

func _on_cancel_pressed() -> void:
	if switching_column != "":
		_exit_switch_mode()
	else:
		closed.emit()
		queue_free()

func _build_all() -> void:
	_build_team()
	_build_reserve()
	box_label.text = "Box %d" % (current_box + 1)
	_move_cursor(cursor_column, cursor_index)
	_update_prompt()
	# _build_team/_build_reserve acabaram de recriar TODOS os PcSlot do zero
	# (queue_free + new) — switching_slot_node (se algum) aponta pro node
	# ANTIGO, já sendo destruído, então precisa reencontrar e repintar o node
	# NOVO na mesma posição (switching_column/switching_index continuam
	# válidos, só o Node em si mudou).
	_refresh_switch_highlight()

func _build_team() -> void:
	for child in team_rows_container.get_children():
		child.queue_free()
	for i in GameState.MAX_TEAM_SIZE:
		var slot := PcSlot.new()
		team_rows_container.add_child(slot)
		slot.setup("team", i, GameState.get_roster_slot(i))
		slot.dropped.connect(_on_slot_dropped.bind("team", i))
		slot.hovered.connect(_on_slot_hovered.bind(slot))
		slot.clicked.connect(_on_slot_clicked)

# Só monta os SLOTS_PER_BOX slots da box ATUAL (não a reserva inteira) —
# "index" (usado em setup()/dropped) é sempre o índice ABSOLUTO dentro de
# GameState.storage (offset da box + posição local i), nunca a posição
# local sozinha, senão duas boxes diferentes colidiriam no mesmo índice.
func _build_reserve() -> void:
	for child in reserve_grid_container.get_children():
		child.queue_free()
	var box_offset = current_box * GameState.SLOTS_PER_BOX
	for i in GameState.SLOTS_PER_BOX:
		var absolute_index = box_offset + i
		var slot := PcSlot.new()
		reserve_grid_container.add_child(slot)
		slot.setup("reserve", absolute_index, _reserve_get_slot(absolute_index))
		slot.dropped.connect(_on_slot_dropped.bind("reserve", absolute_index))
		slot.hovered.connect(_on_slot_hovered.bind(slot))
		slot.clicked.connect(_on_slot_clicked)

# wrapi: passar de Box 6 pra frente volta pra Box 1, e vice-versa — mesmo
# estilo de navegação circular já usado em todo menu do projeto (ver
# _move_selection em pause_menu.gd/party_screen.gd etc.).
func _on_prev_box_pressed() -> void:
	_switch_box(current_box - 1)

func _on_next_box_pressed() -> void:
	_switch_box(current_box + 1)

# Se o cursor estava na reserva, precisa "acompanhar" a troca de box pra
# continuar na MESMA posição local da grade (só o offset absoluto muda) —
# sem isso, cursor_index continuava apontando pro índice absoluto da box
# ANTERIOR, e _get_slot_node/_get_data passavam a ler/destacar o slot
# errado (de outra box) depois de trocar de página.
func _switch_box(new_box: int) -> void:
	var local = cursor_index - current_box * GameState.SLOTS_PER_BOX
	current_box = wrapi(new_box, 0, GameState.BOX_COUNT)
	if cursor_column == "reserve":
		cursor_index = current_box * GameState.SLOTS_PER_BOX + local
	_build_all()

# source_column/source_index vêm de quem originou o movimento (drag do
# mouse OU switching_column/switching_index do modo Switch, ver
# _activate_cursor); target_column/target_index é o destino. Reúne a MESMA
# lógica de swap não importa como foi disparado — soltar/mover em cima de
# si mesmo não faz nada.
func _perform_move(source_column: String, source_index: int, target_column: String, target_index: int) -> void:
	if source_column == target_column and source_index == target_index:
		return
	if source_column == "team" and target_column == "team":
		GameState.swap_roster_slots(source_index, target_index)
	elif source_column == "reserve" and target_column == "reserve":
		_reserve_swap_slots(source_index, target_index)
	else:
		var team_idx = source_index if source_column == "team" else target_index
		var reserve_idx = source_index if source_column == "reserve" else target_index
		_reserve_swap_active(team_idx, reserve_idx)
	switching_column = ""
	switching_index = -1
	_build_all()

# target_column/target_index vêm do bind (ver _build_team/_build_reserve) —
# ESTE slot, quem recebeu o solto.
func _on_slot_dropped(source_column: String, source_index: int, target_column: String, target_index: int) -> void:
	_perform_move(source_column, source_index, target_column, target_index)

# Mouse passando por cima de um slot sincroniza o cursor com ele — teclado
# e mouse compartilham o mesmo estado (cursor_column/cursor_index), então
# alternar entre os dois no meio de uma seleção funciona sem problema.
func _on_slot_hovered(slot: PcSlot) -> void:
	_move_cursor(slot.column, slot.index)

# ---------- Cursor (teclado + mouse) ----------

func _move_cursor_by(dir: Vector2i) -> void:
	var pos = _neighbor(cursor_column, cursor_index, dir)
	_move_cursor(pos["column"], pos["index"])

# Time (coluna vertical, 6 linhas) <-> Reserva (grade RESERVE_COLUMNS x N
# da box atual) — as duas colunas têm o MESMO número de linhas de propósito
# (6), o que deixa ui_left/ui_right trocar de região "na mesma altura" sem
# nenhum caso especial. ui_left no time e ui_right na última coluna da
# reserva simplesmente não fazem nada (já estão na ponta).
func _neighbor(column: String, index: int, dir: Vector2i) -> Dictionary:
	if column == "team":
		if dir.y != 0:
			return {"column": "team", "index": wrapi(index + dir.y, 0, GameState.MAX_TEAM_SIZE)}
		if dir.x > 0:
			var absolute = current_box * GameState.SLOTS_PER_BOX + index * RESERVE_COLUMNS
			return {"column": "reserve", "index": absolute}
		return {"column": "team", "index": index}

	@warning_ignore("integer_division")
	var reserve_rows = GameState.SLOTS_PER_BOX / RESERVE_COLUMNS
	var local = index - current_box * GameState.SLOTS_PER_BOX
	@warning_ignore("integer_division")
	var row = local / RESERVE_COLUMNS
	var col = local % RESERVE_COLUMNS

	if dir.y != 0:
		row = wrapi(row + dir.y, 0, reserve_rows)
	elif dir.x < 0:
		if col == 0:
			return {"column": "team", "index": row}
		col -= 1
	elif dir.x > 0:
		col = wrapi(col + 1, 0, RESERVE_COLUMNS)

	var new_local = row * RESERVE_COLUMNS + col
	return {"column": "reserve", "index": current_box * GameState.SLOTS_PER_BOX + new_local}

func _move_cursor(column: String, index: int) -> void:
	cursor_column = column
	cursor_index = index
	if highlighted_slot != null and is_instance_valid(highlighted_slot):
		highlighted_slot.set_highlighted(false)
	highlighted_slot = _get_slot_node(column, index)
	if highlighted_slot != null:
		highlighted_slot.set_highlighted(true)
	_refresh_attributes(_get_data(column, index))

# Clique do mouse (ver PcSlot.clicked) — `hovered` já sincronizou
# cursor_column/cursor_index pra ESTE slot antes do clique chegar (ver
# mouse_entered em pc_slot.gd), então só precisa chamar a MESMA ativação
# que X (teclado) já usa — mesma reutilização que party_screen.gd faz entre
# _on_slot_gui_input e _activate_selected.
func _on_slot_clicked() -> void:
	_activate_cursor()

# Em modo Switch (switching_column != "", ver _enter_switch_mode): X/clique
# no MESMO slot escolhido cancela a troca; em qualquer OUTRO slot (vazio ou
# não — trocar com um vazio já é um "mover pra lá" válido) completa a troca
# de verdade (ver _perform_move). Fora de modo Switch: X/clique num slot
# VAZIO não faz nada; num slot preenchido abre o popup de ações (Summary/
# Switch/Release) em vez de "pegar" a unidade na hora — pedido do usuário:
# "When a unit is clicked, some options should pop up". Só "Switch" no
# popup é que entra em modo Switch de verdade agora (ver
# _on_slot_action_menu_closed) — X sozinho não pega mais nada direto, essa
# é a mudança de comportamento em relação a como isto funcionava antes.
func _activate_cursor() -> void:
	if switching_column != "":
		if switching_column == cursor_column and switching_index == cursor_index:
			_exit_switch_mode()
			return
		_perform_move(switching_column, switching_index, cursor_column, cursor_index)
		return

	var data = _get_data(cursor_column, cursor_index)
	if data == null:
		return
	_open_slot_action_menu(cursor_column, cursor_index, data)

# ---------- Popup de ações (Summary / Switch / Release) ----------

# can_release: pedido do usuário (resposta à pergunta de esclarecimento) —
# Release só aparece no TIME (column == "team", independente de qual conta
# a coluna da reserva está mostrando agora) e na reserva NORMAL do jogador
# (reserve_mode == "storage") — Giovanni's/Baldo's/Heaven Account ficam só
# arrastar-pra-trocar, sem Release, por serem contas especiais/não
# totalmente "suas" (ver comentário grande de reserve_mode lá em cima).
func _open_slot_action_menu(column: String, index: int, data: UnitData) -> void:
	var menu = SLOT_ACTION_MENU_SCENE.instantiate()
	add_child(menu)
	var can_release = column == "team" or reserve_mode == "storage"
	menu.setup(data.unit_name, false, false, can_release)   # can_evolve=false, can_loadout=false — só Summary/Switch/Release fazem sentido aqui
	active_submenu = menu
	menu.closed.connect(_on_slot_action_menu_closed.bind(column, index))

func _on_slot_action_menu_closed(option: String, column: String, index: int) -> void:
	active_submenu = null
	match option:
		"Switch":
			_enter_switch_mode(column, index)
		"Summary":
			_open_summary(column, index)
		"Release":
			_try_release(column, index)

func _enter_switch_mode(column: String, index: int) -> void:
	switching_column = column
	switching_index = index
	_update_prompt()
	_refresh_switch_highlight()

func _exit_switch_mode() -> void:
	switching_column = ""
	switching_index = -1
	_update_prompt()
	_refresh_switch_highlight()

# Repinta de azul (ver PcSlot.set_picked) o slot em switching_column/
# switching_index AGORA — chamado sempre que o modo Switch muda de estado
# (entra/sai/completa) e de novo depois de QUALQUER _build_all() (que
# recria todos os PcSlot do zero — ver comentário lá, switching_slot_node
# guardado antes sempre fica apontando pro node ANTIGO nesse caso).
# switching_slot_node antigo (se ainda válido) sempre perde o azul primeiro,
# pra nunca deixar dois slots pintados ao mesmo tempo se a posição mudar.
func _refresh_switch_highlight() -> void:
	if switching_slot_node != null and is_instance_valid(switching_slot_node):
		switching_slot_node.set_picked(false)
	switching_slot_node = null
	if switching_column == "":
		return
	switching_slot_node = _get_slot_node(switching_column, switching_index)
	if switching_slot_node != null:
		switching_slot_node.set_picked(true)

# "Summary" do popup — mesma cena/setup que party_screen.gd::_open_summary
# usa, só que a UnitData pode vir do TIME ou de QUALQUER reserva mostrada
# agora (ver _get_data), não só do roster.
func _open_summary(column: String, index: int) -> void:
	var data = _get_data(column, index)
	if data == null:
		return
	var screen = UNIT_SUMMARY_SCENE.instantiate()
	add_child(screen)
	screen.setup(data)
	active_submenu = screen
	screen.closed.connect(_on_summary_closed)

func _on_summary_closed() -> void:
	active_submenu = null

# "Release" do popup — pedido do usuário: "Release (deletes the unit,
# prompts Are you sure? Yes/No first)". yes_no_prompt.gd já cuida do
# próprio process_mode/pause; aqui só precisamos guardar QUAL slot está
# sendo perguntado (bind column/index) pra saber o que apagar se a resposta
# for "Yes".
func _try_release(column: String, index: int) -> void:
	var data = _get_data(column, index)
	if data == null:
		return
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("Release %s? This cannot be undone." % data.unit_name.to_upper())
	active_submenu = prompt
	prompt.answered.connect(_on_release_answered.bind(column, index))

# "Yes" apaga de verdade (vira null no slot — GameState.set_roster_slot/
# set_storage_slot, ver comentário grande de set_storage_slot lá em
# game_state.gd) e reconstrói a tela inteira (_build_all, mesmo caminho de
# depois de qualquer _perform_move). "No" só fecha o popup, sem mexer em
# nada — mesmo espírito "cancelar não muda estado nenhum" do resto do
# arquivo.
func _on_release_answered(yes: bool, column: String, index: int) -> void:
	active_submenu = null
	if not yes:
		return
	if column == "team":
		GameState.set_roster_slot(index, null)
	else:
		GameState.set_storage_slot(index, null)
	_build_all()

# Antes mostrava um texto de dica de tecla ("Setas: mover cursor. X:
# selecionar Z: fechar" / variante "mover/cancelar") — removido a pedido do
# usuário (2026-07-23): "Remove 'Key: What it does' from all menus, it
# bloats everything". prompt_label continua existindo (é @onready, outras
# telas/estados podem voltar a usá-lo pra uma mensagem de verdade no
# futuro), só não recebe mais dica de tecla nenhuma.
func _update_prompt() -> void:
	prompt_label.text = ""

func _get_data(column: String, index: int) -> UnitData:
	if column == "team":
		return GameState.get_roster_slot(index)
	return _reserve_get_slot(index)

func _get_slot_node(column: String, index: int) -> PcSlot:
	if column == "team":
		if index < 0 or index >= team_rows_container.get_child_count():
			return null
		return team_rows_container.get_child(index)
	var local = index - current_box * GameState.SLOTS_PER_BOX
	if local < 0 or local >= reserve_grid_container.get_child_count():
		return null
	return reserve_grid_container.get_child(local)

func _refresh_attributes(data: UnitData) -> void:
	for child in attr_container.get_children():
		child.queue_free()

	if data == null:
		var hint_label = Label.new()
		hint_label.text = "Passe o mouse sobre uma unidade."
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		attr_container.add_child(hint_label)
		return

	var portrait_box = Control.new()
	portrait_box.custom_minimum_size = Vector2(ATTR_PORTRAIT_SIZE, ATTR_PORTRAIT_SIZE)
	portrait_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var portrait = AnimatedSprite2D.new()
	portrait.position = Vector2(ATTR_PORTRAIT_SIZE / 2.0, ATTR_PORTRAIT_SIZE / 2.0)
	portrait_box.add_child(portrait)
	attr_container.add_child(portrait_box)
	_play_portrait(portrait, data, ATTR_PORTRAIT_SIZE)

	var status = "  (desmaiado)" if data.current_hp <= 0 else ""
	var name_label = Label.new()
	name_label.text = "%s   Lv.%d%s" % [data.unit_name.to_upper(), data.level, status]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attr_container.add_child(name_label)

	var types_label = Label.new()
	types_label.text = " / ".join(data.types) if not data.types.is_empty() else "--"
	types_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attr_container.add_child(types_label)

	attr_container.add_child(HSeparator.new())

	var hp_max = UnitScript.calc_hp_static(data.hp_base, data.level, data.weight)
	_add_stat_row("HP", "%d/%d" % [max(data.current_hp, 0), hp_max])
	_add_stat_row("Attack", UnitScript.calc_stat_static(data.attack_base, data.level))
	_add_stat_row("Defense", UnitScript.calc_stat_static(data.defense_base, data.level))
	_add_stat_row("Sp. Attack", UnitScript.calc_stat_static(data.special_attack_base, data.level))
	_add_stat_row("Sp. Defense", UnitScript.calc_stat_static(data.special_defense_base, data.level))
	_add_stat_row("Speed", UnitScript.calc_stat_static(data.speed_base, data.level))

func _add_stat_row(label_text: String, value) -> void:
	var row = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label = Label.new()
	value_label.text = str(value)
	row.add_child(name_label)
	row.add_child(value_label)
	attr_container.add_child(row)

# Mesmo critério de PcSlot._play_portrait — duplicado de propósito (mesmo
# padrão de sempre no projeto pra helpers pequenos de UI, ver comentário
# sobre a cor da barra de HP em party_screen.gd/unit.gd).
func _play_portrait(portrait: AnimatedSprite2D, data: UnitData, size: float) -> void:
	if data.sprite_frames == null:
		return
	var anim_name = "idle_down"
	if data.current_hp <= 0 and data.sprite_frames.has_animation("sleep_down"):
		anim_name = "sleep_down"
	if not data.sprite_frames.has_animation(anim_name):
		return
	portrait.sprite_frames = data.sprite_frames
	portrait.play(anim_name)
	var frame_tex = data.sprite_frames.get_frame_texture(anim_name, 0)
	if frame_tex != null:
		var src_size = frame_tex.get_size()
		if src_size.x > 0 and src_size.y > 0:
			var scale_factor = min(size / src_size.x, size / src_size.y)
			portrait.scale = Vector2(scale_factor, scale_factor)
