class_name PcSlot
extends PanelContainer

# Um slot "quadrado" — usado tanto pelas 6 linhas do time quanto pelos
# slots da reserva na tela do PC (ver pc_screen.gd). Só sabe duas coisas:
# mostrar a unidade que carrega (idle_down, ou sleep_down se desmaiada) e
# participar do drag-and-drop NATIVO do Godot (Control._get_drag_data /
# _can_drop_data / _drop_data) — arrastar um slot e soltar em cima de outro
# troca as duas unidades (ou só desloca, se o destino estiver vazio).
#
# Este script não decide o que fazer com uma troca — só avisa via o sinal
# `dropped(source_column, source_index)`; pc_screen.gd é quem escuta isso
# (uma conexão por slot, com bind do PRÓPRIO column/index como destino) e
# chama a função certa em GameState.

# clicked (novo) — pedido do usuário: "When a unit is clicked, some options
# should pop up: Summary, Switch, Release". Emitido só no SOLTAR do botão
# esquerdo (não no pressionar) — de propósito, pra não competir com o drag-
# and-drop nativo já existente logo abaixo: um arrasto de verdade nunca
# entrega o evento de soltar aqui (Godot desvia pra _drop_data() de quem
# recebeu o solto assim que o arrasto realmente começa), então só um CLIQUE
# simples (pressionar e soltar sem mover) chega a emitir isto. pc_screen.gd
# escuta isso e chama a MESMA _activate_cursor() que o teclado (X) já usa —
# o mouse só precisa sincronizar o cursor primeiro (ver `hovered`, que já
# roda antes de qualquer clique chegar aqui).
signal clicked
signal dropped(source_column: String, source_index: int)
signal hovered

const SIZE = 48.0
const MARGIN = 4.0

# custom_minimum_size PRECISA já incluir as margens do StyleBox (MARGIN dos
# 2 lados) — se fosse só Vector2(SIZE, SIZE), um slot VAZIO (sem filho
# nenhum) ficaria 48x48, mas um slot CHEIO (com o portrait_box de 48x48
# dentro, mais 4px de margem de cada lado) precisaria de 56x56 pra caber —
# o PanelContainer cresce automaticamente pra isso quando tem conteúdo.
# Resultado: cada slot mudava de tamanho ao ganhar/perder unidade, e isso
# se propagava pra grade inteira e esticava/achatava a janela do PC. Usar
# SIZE + MARGIN*2 sempre garante que o "vazio" já nasce do tamanho que o
# "cheio" ia precisar de qualquer jeito — nunca cresce, nunca encolhe.
const PANEL_SIZE = SIZE + MARGIN * 2

const STYLE_NORMAL = Color(0, 0, 0, 0)
const STYLE_HOVER = Color(1, 1, 0.3, 0.25)
# Azul — "na mão" (Switch), mesma cor de party_screen.gd::ROW_STYLE_PICKED
# (pedido do usuário: "While a unit is selected with switch, it should be
# blue highlighted") — reaproveitada aqui pra ficar consistente com a MESMA
# cor já usada pra "picked" na tela de Party.
const STYLE_PICKED = Color(0.3, 0.6, 1, 0.35)

# Pedido do usuário: "Add thicker divisors to the PC screen, so each cell is
# clearly seen as different" — antes cada PcSlot só tinha bg_color (sem
# borda nenhuma), então dois slots vazios lado a lado se fundiam num bloco
# só, sem jeito de saber onde um terminava e o outro começava. BORDER_WIDTH/
# BORDER_COLOR desenham um contorno em TODO slot, cheio ou vazio, sempre —
# junto com STYLE_NORMAL/HOVER/PICKED continuando a colorir só o FUNDO por
# cima da borda.
const BORDER_WIDTH = 2
const BORDER_COLOR = Color(1, 1, 1, 0.4)

var column: String = ""
var index: int = -1
var unit_data: UnitData = null

var _style: StyleBoxFlat
# Dois estados independentes (ver set_highlighted/set_picked abaixo) — um
# slot pode estar com o CURSOR em cima (_is_highlighted, amarelo, mouse OU
# teclado) e SER o slot escolhido pra troca (_is_picked, azul) ao mesmo
# tempo (ex: escolheu "Switch" nele e o cursor nunca saiu de cima). _is_picked
# sempre GANHA da cor amarela quando os dois são true — ver _refresh_style.
var _is_highlighted: bool = false
var _is_picked: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_SIZE, PANEL_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style = StyleBoxFlat.new()
	_style.bg_color = STYLE_NORMAL
	_style.content_margin_left = MARGIN
	_style.content_margin_right = MARGIN
	_style.content_margin_top = MARGIN
	_style.content_margin_bottom = MARGIN
	_style.border_width_left = BORDER_WIDTH
	_style.border_width_right = BORDER_WIDTH
	_style.border_width_top = BORDER_WIDTH
	_style.border_width_bottom = BORDER_WIDTH
	_style.border_color = BORDER_COLOR
	add_theme_stylebox_override("panel", _style)
	mouse_entered.connect(func() -> void: hovered.emit())

# Só no SOLTAR do botão esquerdo — ver comentário grande do sinal `clicked`
# lá em cima pro motivo de não ser no pressionar.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()

# column/index identificam ONDE esse slot mora ("team"/i ou "reserve"/i) —
# é o que pc_screen.gd usa tanto pra saber quem é o destino de um drop
# quanto pra montar o payload quando ESTE slot é a origem de um drag.
func setup(column_: String, index_: int, data: UnitData) -> void:
	column = column_
	index = index_
	unit_data = data
	for child in get_children():
		child.queue_free()
	if data == null:
		return
	var portrait_box = Control.new()
	portrait_box.custom_minimum_size = Vector2(SIZE, SIZE)
	portrait_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait = AnimatedSprite2D.new()
	portrait.position = Vector2(SIZE / 2.0, SIZE / 2.0)
	portrait_box.add_child(portrait)
	add_child(portrait_box)
	_play_portrait(portrait, data, SIZE)

func set_highlighted(is_highlighted: bool) -> void:
	_is_highlighted = is_highlighted
	_refresh_style()

# Pedido do usuário: "While a unit is selected with switch, it should be
# blue highlighted" — ver pc_screen.gd::_refresh_switch_highlight, chamado
# toda vez que o modo Switch entra/sai ou o slot escolhido muda.
func set_picked(is_picked: bool) -> void:
	_is_picked = is_picked
	_refresh_style()

func _refresh_style() -> void:
	if _is_picked:
		_style.bg_color = STYLE_PICKED
	elif _is_highlighted:
		_style.bg_color = STYLE_HOVER
	else:
		_style.bg_color = STYLE_NORMAL

# Desmaiada (current_hp <= 0) toca Sleep em vez de Idle — mesmo critério de
# party_screen.gd::_refresh_portrait.
func _play_portrait(portrait: AnimatedSprite2D, data: UnitData, size: float) -> void:
	if data.sprite_frames == null:
		return
	# ver UnitData.portrait_anim_name() — mesmo fallback idle/hover/sleep de
	# party_screen.gd::_refresh_portrait (Beedrill etc. só têm hover_down).
	var anim_name = data.portrait_anim_name(data.current_hp <= 0)
	if anim_name == "":
		return
	portrait.sprite_frames = data.sprite_frames
	portrait.play(anim_name)
	var frame_tex = data.sprite_frames.get_frame_texture(anim_name, 0)
	if frame_tex != null:
		var src_size = frame_tex.get_size()
		if src_size.x > 0 and src_size.y > 0:
			var scale_factor = min(size / src_size.x, size / src_size.y)
			portrait.scale = Vector2(scale_factor, scale_factor)

# --- Drag and drop nativo do Godot (Control) ---

# Chamado quando o jogador começa a arrastar A PARTIR deste slot. Slot
# vazio não pode ser "pego" (retorna null — Godot entende isso como "não
# tem o que arrastar daqui"). set_drag_preview() é o ícone que segue o
# mouse durante o arrasto; o retorno da função é o "payload" que chega em
# _drop_data() de quem receber o solto.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if unit_data == null:
		return null
	set_drag_preview(_make_preview())
	return {"column": column, "index": index}

func _make_preview() -> Control:
	var box = Control.new()
	box.custom_minimum_size = Vector2(SIZE, SIZE)
	var portrait = AnimatedSprite2D.new()
	portrait.position = Vector2(SIZE / 2.0, SIZE / 2.0)
	portrait.modulate.a = 0.85
	box.add_child(portrait)
	_play_portrait(portrait, unit_data, SIZE)
	return box

# Qualquer slot aceita qualquer arrasto vindo de outro PcSlot — quem decide
# se a troca faz sentido é sempre GameState (que já lida com casos como
# "os dois lados estão vazios" sem problema nenhum).
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("column") and data.has("index")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.emit(data["column"], data["index"])
