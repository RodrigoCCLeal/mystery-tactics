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
#
# Duas CAMADAS (ver AttackData.impact_texture/impact_texture_2), tocadas ao
# mesmo tempo, sobrepostas no mesmo ponto — ex: Ice Fang combina a "mordida"
# (Ice_Fang_Fang) com os cacos de gelo espalhando (Ice_Fang_Hit) num efeito
# só. Cada camada tem sua própria tira/contagem de quadros (podem ter
# tamanhos e durações diferentes) e para de tocar sozinha assim que chega no
# último quadro — `finished` (e o queue_free do nó inteiro) só dispara quando
# AS DUAS tiverem terminado, não a primeira que acabar. A camada 2 é
# totalmente opcional: sem ela (texture_2 == null), o comportamento é
# idêntico a antes (uma tira só).
#
# Camada 1 também aceita o formato "vários arquivos separados" (mesma ideia
# de Projectile.raw_frames — ver AttackData.impact_frames): quando `frames`
# não é vazio, cada Texture2D já É um quadro inteiro, sem AtlasTexture
# nenhum — troca sprite.texture direto entre eles. Ex: Confusion (13
# arquivos), um ataque à distância sem projétil, só o efeito de impacto.

signal finished

const FRAME_DURATION = 0.05  # segundos que cada quadro fica visível

@onready var sprite: Sprite2D = $Sprite2D
@onready var sprite_2: Sprite2D = $Sprite2D2

var frame_size: int = 24
var frame_count: int = 1
var frame_index: int = 0
var layer_1_done: bool = true

var frame_size_2: int = 24
var frame_count_2: int = 1
var frame_index_2: int = 0
var layer_2_done: bool = true

var frame_timer: float = 0.0

# Guardado à parte pelo mesmo motivo do Projectile: sprite.texture é tipado
# Texture2D (sem campo "region"), só AtlasTexture tem.
var atlas_texture: AtlasTexture
var atlas_texture_2: AtlasTexture

# Preenchido só no modo "vários arquivos" da camada 1 (ver
# AttackData.impact_frames) — cada elemento é um quadro pronto, trocado
# direto em sprite.texture. Vazio = modo de sempre (atlas_texture fatiado de
# uma textura só). Só a camada 1 precisa disso por enquanto (nenhum ataque
# ainda combina "vários arquivos" com camada 2).
var raw_frames: Array[Texture2D] = []

func play(texture: Texture2D, at_position: Vector2, texture_2: Texture2D = null, frames: Array[Texture2D] = []) -> void:
	position = at_position
	frame_timer = 0.0

	raw_frames = frames
	if not raw_frames.is_empty():
		sprite.visible = true
		layer_1_done = false
		frame_index = 0
		frame_count = raw_frames.size()
		atlas_texture = null
		sprite.texture = raw_frames[0]
	else:
		sprite.visible = texture != null
		layer_1_done = texture == null
		if texture != null:
			frame_index = 0
			frame_size = int(texture.get_height())
			frame_count = max(1, int(texture.get_width()) / frame_size)
			atlas_texture = AtlasTexture.new()
			atlas_texture.atlas = texture
			atlas_texture.region = Rect2(0, 0, frame_size, frame_size)
			sprite.texture = atlas_texture

	sprite_2.visible = texture_2 != null
	layer_2_done = texture_2 == null
	if texture_2 != null:
		frame_index_2 = 0
		frame_size_2 = int(texture_2.get_height())
		frame_count_2 = max(1, int(texture_2.get_width()) / frame_size_2)
		atlas_texture_2 = AtlasTexture.new()
		atlas_texture_2.atlas = texture_2
		atlas_texture_2.region = Rect2(0, 0, frame_size_2, frame_size_2)
		sprite_2.texture = atlas_texture_2

func _process(delta: float) -> void:
	frame_timer += delta
	if frame_timer < FRAME_DURATION:
		return
	frame_timer -= FRAME_DURATION

	if not layer_1_done:
		frame_index += 1
		if frame_index >= frame_count:
			layer_1_done = true
			sprite.visible = false   # essa camada já acabou — some, mas espera a outra pra fechar o nó
		elif not raw_frames.is_empty():
			sprite.texture = raw_frames[frame_index]
		else:
			atlas_texture.region = Rect2(frame_index * frame_size, 0, frame_size, frame_size)

	if not layer_2_done:
		frame_index_2 += 1
		if frame_index_2 >= frame_count_2:
			layer_2_done = true
			sprite_2.visible = false
		else:
			atlas_texture_2.region = Rect2(frame_index_2 * frame_size_2, 0, frame_size_2, frame_size_2)

	if layer_1_done and layer_2_done:
		finished.emit()
		queue_free()
