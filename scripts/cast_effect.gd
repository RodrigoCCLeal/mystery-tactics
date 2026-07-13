extends Node2D

# Efeito de "cast" — irmão do Projectile (scripts/projectile.gd): VIAJA de
# `from` até `to` (mesma mecânica de movimento, ver _process abaixo), em vez
# de ficar parado como o ImpactEffect. A diferença é só a ORIGEM/arte: aqui
# sai de QUEM ATACA (não do alvo), e a arte é orientada por direção — ex: a
# onda sonora do Growl, que sai de 1 tile à frente do atacante e viaja até o
# alcance do golpe (ver battle.gd::play_cast_effect, que calcula `from`/`to`
# a partir de attacker.grid_pos + dir e attacker.grid_pos + dir*range).
#
# Formato da arte (ver AttackData.cast_frames_by_direction): diferente de
# Projectile/ImpactEffect (uma tira HORIZONTAL, 1 direção só), essa vem como
# uma grade 2D — 8 COLUNAS (uma por direção) x 6 LINHAS (os quadros da
# animação dentro de cada direção). A ordem das colunas é sentido HORÁRIO a
# partir de "down" (ver DIRECTION_COLUMNS) — REPARE que é o sentido
# CONTRÁRIO da ordem usada nas sprites de personagem/Pokémon (ver comentário
# grande em Unit.get_direction_suffix, que é anti-horário a partir de
# "down"). A COLUNA fica fixa (a direção não muda no meio do voo); só a
# LINHA avança conforme a animação toca, em LOOP (igual Projectile.gd:
# frame_index % ROW_COUNT), já que aqui o que decide quando o efeito acaba é
# CHEGAR no destino, não a animação se esgotar.

signal finished

const MOVE_SPEED = 300.0     # pixels por segundo, mesma velocidade de Projectile.MOVE_SPEED
const FRAME_DURATION = 0.05  # segundos que cada quadro fica visível
const ROW_COUNT = 6

# Índice = coluna na imagem (0..7), sentido horário a partir de "down".
const DIRECTION_COLUMNS = ["down", "down_left", "left", "up_left", "up", "up_right", "right", "down_right"]

@onready var sprite: Sprite2D = $Sprite2D

var atlas_texture: AtlasTexture
var frame_width: int = 24
var frame_height: int = 24
var column_x: int = 0
var frame_index: int = 0
var frame_timer: float = 0.0
var target_position: Vector2 = Vector2.ZERO

# facing: mesma string de Unit.facing ("down", "down_right", etc. — ver
# Unit.get_direction_suffix), só usada pra escolher a COLUNA certa — o
# movimento de verdade (from -> to) é independente disso. Se a direção não
# existir em DIRECTION_COLUMNS (não deveria acontecer, mas por segurança) ou
# texture vier null, o efeito só fecha sozinho sem mostrar nada.
func play(texture: Texture2D, from: Vector2, to: Vector2, facing: String) -> void:
	position = from
	target_position = to
	frame_timer = 0.0
	frame_index = 0

	var column = DIRECTION_COLUMNS.find(facing)
	if texture == null or column == -1:
		finished.emit()
		queue_free()
		return

	frame_width = int(texture.get_width()) / DIRECTION_COLUMNS.size()
	frame_height = int(texture.get_height()) / ROW_COUNT
	column_x = column * frame_width

	atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = Rect2(column_x, 0, frame_width, frame_height)
	sprite.texture = atlas_texture

func _process(delta: float) -> void:
	if atlas_texture == null:
		return

	frame_timer += delta
	if frame_timer >= FRAME_DURATION:
		frame_timer -= FRAME_DURATION
		frame_index = (frame_index + 1) % ROW_COUNT
		atlas_texture.region = Rect2(column_x, frame_index * frame_height, frame_width, frame_height)

	position = position.move_toward(target_position, MOVE_SPEED * delta)
	if position == target_position:
		finished.emit()
		queue_free()
