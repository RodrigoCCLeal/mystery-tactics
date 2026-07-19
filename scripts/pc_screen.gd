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

# Qual reserva a coluna do meio mostra: "storage" (padrão, reserva normal do
# jogador, ver GameState.storage) ou "giovanni" (GameState.giovanni_storage —
# "Giovanni's Account", unidades roubadas por treinadores Rocket, ver
# battle.gd::resolve_capture). Quem abre esta cena seta isso ANTES dela
# entrar na árvore (ver computer_screen.gd::_open_pc_screen) — o resto do
# arquivo nunca lê GameState.storage/giovanni_storage direto, só chama os 3
# wrappers _reserve_* logo abaixo, que decidem qual reserva de verdade usar
# com base neste campo. Isso é o que deixa a MESMA cena/script servir as
# duas contas, igual house_interior.gd serve qualquer interior.
@export_enum("storage", "giovanni") var reserve_mode: String = "storage"

func _reserve_get_slot(index: int) -> UnitData:
	if reserve_mode == "giovanni":
		return GameState.get_giovanni_slot(index)
	return GameState.get_storage_slot(index)

func _reserve_swap_slots(a: int, b: int) -> void:
	if reserve_mode == "giovanni":
		GameState.swap_giovanni_slots(a, b)
	else:
		GameState.swap_storage_slots(a, b)

func _reserve_swap_active(active_index: int, reserve_index: int) -> void:
	if reserve_mode == "giovanni":
		GameState.swap_active_with_giovanni(active_index, reserve_index)
	else:
		GameState.swap_active_with_storage(active_index, reserve_index)

@onready var team_rows_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Columns/TeamColumn/TeamRows
@onready var reserve_grid_container: GridContainer = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/ReserveGrid
@onready var box_label: Label = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/BoxNav/BoxLabel
@onready var prev_box_button: Button = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/BoxNav/PrevButton
@onready var next_box_button: Button = $Center/Panel/MarginContainer/Content/Columns/ReserveColumn/BoxNav/NextButton
@onready var attr_container: VBoxContainer = $Center/Panel/MarginContainer/Content/Columns/AttributesPanel/AttrMargin/AttrContent
@onready var team_weight_label: Label = $Center/Panel/MarginContainer/Content/Columns/TeamColumn/TeamWeightLabel
@onready var weight_warning_label: Label = $Center/Panel/MarginContainer/Content/WeightWarning
@onready var prompt_label: Label = $Center/Panel/MarginContainer/Content/Prompt

var highlighted_slot: PcSlot = null
var current_box: int = 0

# Posição do cursor (mouse OU teclado, os dois escrevem aqui — ver
# _on_slot_hovered/_move_cursor). "team" 0..5, "reserve" é sempre o índice
# ABSOLUTO dentro de GameState.storage, igual todo índice de reserva neste
# arquivo (ver comentário grande no topo).
var cursor_column: String = "team"
var cursor_index: int = 0

# "" / -1 = nada selecionado ainda. Quando picked_column != "", X de novo
# em outro slot MOVE a unidade de picked_* pro cursor atual (ver
# _activate_cursor) — X de novo NO MESMO slot picked cancela a seleção sem
# mover nada.
var picked_column: String = ""
var picked_index: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reserve_grid_container.columns = RESERVE_COLUMNS
	prev_box_button.pressed.connect(_on_prev_box_pressed)
	next_box_button.pressed.connect(_on_next_box_pressed)
	_build_all()

func _unhandled_input(event: InputEvent) -> void:
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
	if picked_column != "":
		picked_column = ""
		picked_index = -1
		_update_prompt()
	elif _is_over_weight_limit():
		# Time acima do limite de peso: trava a saída do PC até o jogador
		# corrigir (tirar unidade(s) pra reserva) — o aviso vermelho
		# (weight_warning_label, ver _refresh_weight_warning) já está visível
		# nesse momento, então só ignorar o Z aqui é suficiente pra deixar
		# claro que "fechar" não vai funcionar enquanto isso não for resolvido.
		return
	else:
		closed.emit()
		queue_free()

func _build_all() -> void:
	_build_team()
	_build_reserve()
	box_label.text = "Box %d" % (current_box + 1)
	_move_cursor(cursor_column, cursor_index)
	_update_prompt()
	_refresh_weight_warning()

# Peso total do time (ver GameState.get_roster_weight/MAX_TEAM_WEIGHT) —
# label persistente ("Peso: X/6") sempre visível, mais o aviso vermelho
# "Limite de peso excedido" que só aparece acima do limite. Chamado depois
# de QUALQUER troca (_build_all já roda isso a cada _perform_move), então o
# aviso aparece/some na hora, sem precisar fechar e reabrir o PC.
func _is_over_weight_limit() -> bool:
	return GameState.get_roster_weight() > GameState.MAX_TEAM_WEIGHT

func _refresh_weight_warning() -> void:
	var weight = GameState.get_roster_weight()
	team_weight_label.text = "Peso: %d/%d" % [weight, GameState.MAX_TEAM_WEIGHT]
	weight_warning_label.visible = _is_over_weight_limit()

func _build_team() -> void:
	for child in team_rows_container.get_children():
		child.queue_free()
	for i in GameState.MAX_TEAM_SIZE:
		var slot := PcSlot.new()
		team_rows_container.add_child(slot)
		slot.setup("team", i, GameState.get_roster_slot(i))
		slot.dropped.connect(_on_slot_dropped.bind("team", i))
		slot.hovered.connect(_on_slot_hovered.bind(slot))

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
# mouse OU picked_column/picked_index do teclado, ver _activate_cursor);
# target_column/target_index é o destino. Reúne a MESMA lógica de swap não
# importa como foi disparado — soltar/mover em cima de si mesmo não faz
# nada.
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
	picked_column = ""
	picked_index = -1
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

# X: sem nada selecionado ainda, "pega" a unidade sob o cursor (só se tiver
# unidade — slot vazio não dá pra pegar, mesma trava de PcSlot._get_drag_data
# pro mouse). Já com algo selecionado: X no mesmo slot cancela, X em
# qualquer outro slot move de verdade (ver _perform_move).
func _activate_cursor() -> void:
	if picked_column == "":
		var data = _get_data(cursor_column, cursor_index)
		if data == null:
			return
		picked_column = cursor_column
		picked_index = cursor_index
		_update_prompt()
		return

	if picked_column == cursor_column and picked_index == cursor_index:
		picked_column = ""
		picked_index = -1
		_update_prompt()
		return

	_perform_move(picked_column, picked_index, cursor_column, cursor_index)
	_update_prompt()

func _update_prompt() -> void:
	if picked_column == "":
		prompt_label.text = "Setas: mover cursor.   X: selecionar   Z: fechar"
	else:
		prompt_label.text = "Setas: mover cursor.   X: mover/cancelar   Z: cancelar"

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
