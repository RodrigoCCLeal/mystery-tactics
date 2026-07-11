extends Node2D

# Efeito visual "de impacto" — irmão do Projectile (scripts/projectile.gd),
# mas em vez de VIAJAR de A até B, toca UMA VEZ parado num ponto (o alvo que
# foi atingido) e avisa quando termina (sinal `finished`). Por isso não dá
# pra reaproveitar o Projectile aqui: se from==to nele, a checagem "cheguei
# no destino" já fecha tudo no primeiro frame, sem dar tempo da animação
# aparecer.
#
# Mesma lógica de fatiar frames do Projectile: assume uma tira horizontal de
# quadros QUADRADOS (largura de cada quadro = altura da imagem inteira),
# calculada em runtime a partir da textura — não precisa configurar nada além
# de arrastar a imagem.

signal finished

const FRAME_DURATION = 0.05  # segundos que cada quadro fica visível

@onready var sprite: Sprite2D = $Sprite2D

var frame_size: int = 24
var frame_count: int = 1
var frame_index: int = 0
var frame_timer: float = 0.0

# Guardado à parte pelo mesmo motivo do Projectile: sprite.texture é tipado
# Texture2D (sem campo "region"), só AtlasTexture tem.
var atlas_texture: AtlasTexture

func play(texture: Texture2D, at_position: Vector2) -> void:
	position = at_position
	frame_index = 0
	frame_timer = 0.0

	frame_size = int(texture.get_height())
	frame_count = max(1, int(texture.get_width()) / frame_size)

	atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = Rect2(0, 0, frame_size, frame_size)
	sprite.texture = atlas_texture

func _process(delta: float) -> void:
	frame_timer += delta
	if frame_timer >= FRAME_DURATION:
		frame_timer -= FRAME_DURATION
		frame_index += 1
		if frame_index >= frame_count:
			finished.emit()
			queue_free()
			return
		atlas_texture.region = Rect2(frame_index * frame_size, 0, frame_size, frame_size)
