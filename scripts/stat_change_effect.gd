extends Node2D

# Efeito visual de "stat alterado" — irmão mais simples do ImpactEffect
# (scripts/impact_effect.gd): toca UMA VEZ parado em cima de quem teve um
# stat mudado (Attack, Defense, etc.) e avisa quando termina (sinal
# `finished`). Só UMA camada (sem a ideia de "camada 2" do ImpactEffect —
# nenhum efeito de stat precisa combinar duas artes).
#
# A arte (ver assets/sprites/Status/statChangeUp|statChangeDown/*.png,
# battle.gd::STAT_CHANGE_UP_FRAMES/STAT_CHANGE_DOWN_FRAMES) sempre vem como
# VÁRIOS arquivos separados — mesmo formato "vários arquivos" de
# Projectile.raw_frames/ImpactEffect.raw_frames (ver comentário lá): cada
# Texture2D é um quadro inteiro, sem AtlasTexture, sem corte nenhum.
#
# A "máscara de cor" pedida pelo usuário (Speed=Azul, Defense=Verde,
# Sp.Def=Branco, Attack=Vermelho, Sp.Atk=Roxo — ver battle.gd::
# STAT_CHANGE_TINTS) é feita do mesmo jeito que Unit._refresh_tint() já tinge
# o sprite inteiro da unidade em Frozen/Poisoned: `modulate` no Sprite2D,
# multiplicando a cor de cada pixel da arte pela cor do tint. Branco
# (Color.WHITE, Sp.Def) não muda nada — é o modulate "neutro" padrão.

signal finished

const FRAME_DURATION = 0.05  # segundos que cada quadro fica visível

@onready var sprite: Sprite2D = $Sprite2D

var frames: Array[Texture2D] = []
var frame_index: int = 0
var frame_timer: float = 0.0

func play(new_frames: Array[Texture2D], at_position: Vector2, tint: Color = Color.WHITE) -> void:
	position = at_position
	frames = new_frames
	frame_index = 0
	frame_timer = 0.0
	sprite.modulate = tint
	sprite.visible = not frames.is_empty()
	if not frames.is_empty():
		sprite.texture = frames[0]
	else:
		finished.emit()
		queue_free()

func _process(delta: float) -> void:
	if frames.is_empty():
		return
	frame_timer += delta
	if frame_timer < FRAME_DURATION:
		return
	frame_timer -= FRAME_DURATION

	frame_index += 1
	if frame_index >= frames.size():
		finished.emit()
		queue_free()
		return
	sprite.texture = frames[frame_index]
