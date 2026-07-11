class_name Npc
extends Node2D

# Base de qualquer NPC ESTÁTICO do overworld (não anda sozinho, só fica
# parado numa célula do grid olhando pra uma direção fixa) — mesma técnica
# de spritesheet do Player (ver player.gd::build_sprite_frames), reaproveitada
# aqui porque os sprites de assets/sprites/Human/NPC seguem o MESMO layout de
# charset (4 colunas de ciclo x 4 linhas de direção, na ordem baixo/esquerda/
# direita/cima) — só que como o NPC nunca anda, só precisamos de UM quadro
# parado por direção (idle), não o ciclo inteiro de passos.
#
# Comportamento específico de cada NPC (o que acontece ao falar com ele) NÃO
# mora aqui — isso é o método interact() logo no fim do arquivo, pensado pra
# ser SOBRESCRITO por uma subclasse (ver nurse.gd, "extends
# res://scripts/npc.gd"). Esta classe cuida só de aparência + posição no
# grid, que é igual pra qualquer NPC.

@export var sheet: Texture2D
@export_enum("down", "left", "right", "up") var facing: String = "down"

const SHEET_DIRECTIONS = ["down", "left", "right", "up"]
const FRAMES_PER_CYCLE = 4
const IDLE_FRAME_INDEX = 0

# Vetor de célula -> facing, o inverso do que world.gd::FACING_TO_DIR faz
# pro Player — usado só por face_towards() logo abaixo.
const DIR_TO_FACING = {
	Vector2i(0, 1): "down",
	Vector2i(0, -1): "up",
	Vector2i(-1, 0): "left",
	Vector2i(1, 0): "right",
}

# Mesmo motivo do get_node() em player.gd (em vez de @export com NodePath
# escrito à mão no .tscn): um NPC sempre mora dentro de "Actors" (Node2D com
# y_sort_enabled = true — ver world.tscn/world.gd, é o que resolve o NPC e o
# Player desenharem na ordem certa perto um do outro, por posição Y em vez
# de ordem fixa na árvore), que por sua vez é filho direto de World, o mesmo
# Node2D que tem o TileMapLayer chamado "TileMapLayer". Daí o "../..".
@onready var tile_map: TileMapLayer = get_node("../../TileMapLayer")
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# Célula do grid onde este NPC está — calculada a partir da posição em pixel
# que o Inspector/editor já tiver (arrastar o node na cena é o suficiente,
# não precisa digitar coordenada de grid nenhuma). Outros sistemas (ver
# world.gd::_get_npc_at/_try_interact, player.gd::can_move_to) leem isso pra
# saber "tem alguém aqui" sem precisar de física (Area2D/CollisionShape2D) —
# mesmo espírito de grid puro que o resto do projeto já usa (wall_cells em
# battle.gd, walkable custom data em player.gd).
var grid_pos: Vector2i = Vector2i.ZERO

# Mesmo ajuste de "encostar o pé no chão" que player.gd faz (ver
# _align_sprite_to_tile/_find_foot_row lá) — duplicado aqui de propósito
# (helper pequeno e autocontido, mesmo padrão de duplicação já usado em
# pc_screen.gd/pc_slot.gd para _play_portrait) em vez de generalizar os dois
# num terceiro arquivo só por isso.
@export_range(0.0, 0.5, 0.01) var foot_offset_ratio: float = 0.15

func _ready() -> void:
	add_to_group("npc")
	grid_pos = tile_map.local_to_map(position)
	position = tile_map.map_to_local(grid_pos)   # encaixa exatamente no centro do tile, não importa onde foi arrastado no editor
	anim.sprite_frames = _build_sprite_frames()
	anim.play("idle_" + facing)
	_align_sprite_to_tile()

# Monta só as 4 poses idle (uma por direção) a partir da spritesheet crua —
# mesma ideia de player.gd::build_sprite_frames, só que sem walk/run (este
# NPC nunca anda) e sem precisar de duas texturas (só uma sheet aqui).
func _build_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	if sheet == null:
		return frames
	@warning_ignore("integer_division")
	var frame_w = sheet.get_width() / FRAMES_PER_CYCLE
	@warning_ignore("integer_division")
	var frame_h = sheet.get_height() / SHEET_DIRECTIONS.size()
	for row in SHEET_DIRECTIONS.size():
		var dir = SHEET_DIRECTIONS[row]
		var anim_name = "idle_" + dir
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, 5.0)
		var atlas = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(IDLE_FRAME_INDEX * frame_w, row * frame_h, frame_w, frame_h)
		frames.add_frame(anim_name, atlas)
	return frames

func _align_sprite_to_tile() -> void:
	if sheet == null:
		return
	@warning_ignore("integer_division")
	var frame_w = sheet.get_width() / FRAMES_PER_CYCLE
	@warning_ignore("integer_division")
	var frame_h = sheet.get_height() / SHEET_DIRECTIONS.size()
	var tile_h = tile_map.tile_set.tile_size.y

	var foot_row = _find_foot_row(frame_w, frame_h)
	if foot_row < 0:
		anim.offset = Vector2(0, -frame_h / 2.0 + frame_h * foot_offset_ratio)
		return
	var offset_y = (tile_h / 2.0) - foot_row + (frame_h / 2.0)
	anim.offset = Vector2(0, offset_y)

# Varre de baixo pra cima o quadro parado (sempre linha "down", coluna
# IDLE_FRAME_INDEX) procurando a primeira linha com pixel visível — mesma
# técnica de player.gd::_find_foot_row, incluindo o mesmo motivo de sempre
# usar a linha "down" (índice 0) mesmo quando facing != "down": todo quadro
# tem o mesmo frame_h, então o pé cai na mesma linha em qualquer direção, e
# calcular uma vez só aqui (em vez de recalcular sempre que facing mudar,
# ver face_towards() logo abaixo) evita ter que rechamar isso a cada giro.
func _find_foot_row(frame_w: int, frame_h: int) -> int:
	var image = sheet.get_image()
	if image == null:
		return -1
	image.decompress()

	var origin_x = IDLE_FRAME_INDEX * frame_w
	var origin_y = 0   # linha "down" é sempre a primeira do atlas (ver SHEET_DIRECTIONS)
	const ALPHA_THRESHOLD = 0.05

	for y in range(frame_h - 1, -1, -1):
		for x in frame_w:
			if image.get_pixel(origin_x + x, origin_y + y).a > ALPHA_THRESHOLD:
				return y
	return frame_h - 1

# Chamado por world.gd::_try_interact quando o jogador está de frente pra
# este NPC e aperta "confirm" (X). Não faz nada por padrão — cada NPC de
# verdade sobrescreve isso na própria subclasse (ver nurse.gd).
func interact() -> void:
	pass

# Vira o NPC pra encarar `cell` (sempre a célula do jogador — ver
# world.gd::_try_interact, que chama isso ANTES de interact(), pra todo NPC
# automaticamente) — feedback do usuário: "quando falado, o NPC deve virar
# pro jogador", vale pra qualquer NPC futuro, não só a Nurse, por isso mora
# na base em vez de em cada subclasse. cell e grid_pos são sempre adjacentes
# (o jogador só interage com quem está bem na sua frente, 1 célula de
# distância — ver world.gd), então a diferença cai direto num dos 4 vetores
# de DIR_TO_FACING; qualquer outro valor (não deveria acontecer) simplesmente
# não vira o NPC (get() com default = facing atual).
func face_towards(cell: Vector2i) -> void:
	var new_facing = DIR_TO_FACING.get(cell - grid_pos, facing)
	if new_facing == facing:
		return
	facing = new_facing
	anim.play("idle_" + facing)
