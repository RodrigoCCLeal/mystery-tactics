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

var column: String = ""
var index: int = -1
var unit_data: UnitData = null

var _style: StyleBoxFlat

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
	add_theme_stylebox_override("panel", _style)
	mouse_entered.connect(func() -> void: hovered.emit())

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
	_style.bg_color = STYLE_HOVER if is_highlighted else STYLE_NORMAL

# Desmaiada (current_hp <= 0) toca Sleep em vez de Idle — mesmo critério de
# party_screen.gd::_refresh_portrait.
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
