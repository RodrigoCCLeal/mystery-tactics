extends Node2D

# Projétil visual genérico (Ember é o primeiro, mas serve pra qualquer ataque
# com is_projectile=true) — viaja em linha reta de um ponto A até B na tela,
# tocando uma animação simples de "quadros em tira horizontal", e avisa quem
# o disparou quando chega no destino (ver sinal `arrived`).
#
# Diferente dos personagens (que têm AnimData.xml + frames.tres com o
# tamanho exato de cada quadro), esse asset de "move" não tem metadado
# nenhum — só a imagem. Por padrão (known_frame_count = 0 em launch(), ver
# abaixo) o tamanho/quantidade de quadros é ADIVINHADO em runtime a partir
# da própria textura, assumindo o formato mais comum desses sprites de
# projétil: uma tira horizontal de quadros QUADRADOS (largura de cada
# quadro = altura da imagem inteira, quantidade = largura total / altura).
#
# Isso QUEBRA pra sprite sheets com quadros NÃO quadrados (ex: a animação
# de Ball, ball_NOMEITEM.png — 8 quadros numa única linha, mas cada quadro
# não é um quadrado perfeito): a adivinhação por proporção cortava a região
# errada, mostrando pedaços de mais de um quadro ao mesmo tempo ("2 bolas"
# na tela em vez de 1). Pra esses casos, launch() aceita um
# known_frame_count explícito — quando > 0, usa esse número EXATO em vez de
# adivinhar, e calcula a largura de quadro certa (largura total / count,
# não mais igual à altura).
#
# Terceiro formato (ver `frames` abaixo): quando a arte vem em VÁRIOS
# ARQUIVOS separados (um por quadro) em vez de uma tira dentro de uma imagem
# só — ex: Water Gun (waterGun0.png, waterGun1.png) — não tem atlas nenhum
# pra fatiar, cada Texture2D já É um quadro inteiro; nesse caso a gente troca
# sprite.texture direto entre eles, sem AtlasTexture.

signal arrived

const MOVE_SPEED = 300.0     # pixels por segundo que o projétil viaja na tela
const FRAME_DURATION = 0.05  # segundos que cada quadro da animação fica visível

@onready var sprite: Sprite2D = $Sprite2D

var frame_width: int = 24
var frame_height: int = 24
var frame_count: int = 1
var frame_index: int = 0
var frame_timer: float = 0.0
var target_position: Vector2 = Vector2.ZERO

# Guardado à parte (em vez de ler de volta via sprite.texture) porque
# sprite.texture é tipado como Texture2D — que não tem campo "region", só
# AtlasTexture tem. Com essa referência tipada certinho dá pra mexer no
# region sem GDScript reclamar. Fica vazio (null) no modo `frames`, ver
# comentário grande acima — nesse modo _process() nem olha pra essa var.
var atlas_texture: AtlasTexture

# Preenchido só no modo "vários arquivos" (ver AttackData.projectile_frames)
# — cada elemento é um quadro pronto, trocado direto em sprite.texture. Vazio
# = modo de sempre (atlas_texture fatiado de uma textura só).
var raw_frames: Array[Texture2D] = []

# known_frame_count = 0 (padrão): mantém o comportamento de sempre —
# adivinha quadros QUADRADOS pela proporção da imagem. Usado por todo
# ataque-projétil já existente (Mud-Slap, Powder Snow, etc), cujas sprite
# sheets realmente são quadradas — não precisa mudar nada nesses.
# known_frame_count > 0: usa esse número exato (ver comentário acima).
#
# frames (ver AttackData.projectile_frames): se não-vazio, ignora `texture`
# e known_frame_count por completo — usa esses quadros prontos em vez de
# fatiar atlas nenhum.
#
# rotate_to_direction (ver AttackData.projectile_faces_right): gira o nó
# inteiro pro ângulo de viagem (from -> to) — só faz sentido pra arte
# desenhada olhando pra DIREITA (ângulo 0 em Godot = Vector2.RIGHT), então
# rotacionar já aponta ela certo pra qualquer direção reta/diagonal.
func launch(texture: Texture2D, from: Vector2, to: Vector2, known_frame_count: int = 0, frames: Array[Texture2D] = [], rotate_to_direction: bool = false) -> void:
	position = from
	target_position = to

	if rotate_to_direction:
		rotation = (to - from).angle()

	if not frames.is_empty():
		raw_frames = frames
		frame_count = raw_frames.size()
		sprite.texture = raw_frames[0]
		return

	if known_frame_count > 0:
		frame_count = known_frame_count
		frame_height = int(texture.get_height())
		frame_width = int(texture.get_width()) / frame_count
	else:
		frame_height = int(texture.get_height())
		frame_width = frame_height
		frame_count = max(1, int(texture.get_width()) / frame_width)

	atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = texture
	atlas_texture.region = Rect2(0, 0, frame_width, frame_height)
	sprite.texture = atlas_texture

func _process(delta: float) -> void:
	frame_timer += delta
	if frame_timer >= FRAME_DURATION:
		frame_timer -= FRAME_DURATION
		frame_index = (frame_index + 1) % frame_count
		if not raw_frames.is_empty():
			sprite.texture = raw_frames[frame_index]
		else:
			atlas_texture.region = Rect2(frame_index * frame_width, 0, frame_width, frame_height)

	position = position.move_toward(target_position, MOVE_SPEED * delta)
	if position == target_position:
		arrived.emit()
		queue_free()
