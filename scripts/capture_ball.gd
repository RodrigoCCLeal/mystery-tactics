extends Node2D

# Sequência visual de UMA tentativa de captura (ver battle.gd::resolve_
# capture, único chamador). Mesmo espírito "dumb visual node" de Projectile/
# ImpactEffect (battle.gd decide TUDO — quem é o alvo, se a captura teve
# sucesso, quantos balanços — este script só sabe tocar essa sequência e
# avisar quando termina); a diferença é que aqui tem VÁRIAS etapas em
# sequência (abrir, balançar, sucesso/fracasso) em vez de uma animação só,
# por isso vira uma função async só (play()) que battle.gd dá await direto,
# em vez de um sinal solto que precisaria de _process() pra avançar de
# etapa sozinho.

signal finished

@onready var sprite: Sprite2D = $Sprite2D

const OPEN_DISPLAY_DURATION = 0.5     # quanto tempo a bola ABERTA fica visível (no acerto E no fracasso)
const WOBBLE_ANGLE_DEG = 18.0
const WOBBLE_STEP_DURATION = 0.12
const WOBBLE_PAUSE_DURATION = 0.25    # "stop" parada entre um balanço e o próximo (ou entre o último e o desfecho)
const SUCCESS_MASK_DURATION = 0.25    # tempo pra escurecer a bola até preto
const SUCCESS_FADE_DURATION = 0.5     # tempo pra sumir depois de escura

# closed_texture é a sprite sheet (ver ItemData.ball_closed_texture) — só
# usamos o PRIMEIRO quadro dela aqui (a bola fechada, parada); o voo em si
# (todos os quadros, animado) já foi tocado ANTES desta função ser chamada,
# via battle.gd::fire_projectile() reaproveitando Projectile normalmente.
# closed_frame_count precisa ser o MESMO número passado pro fire_projectile
# daquele voo (ver ItemData.ball_frame_count) — os quadros dessa sprite
# sheet não são necessariamente quadrados, então _first_frame() precisa
# saber a quantidade exata pra cortar a região certa (ver comentário lá).
#
# Nada de z_index aqui: um valor negativo colocaria a bola atrás do MAPA
# inteiro (TileMapLayer é irmã desta cena, no mesmo z_index 0 — z_index
# negativo perde pra ela também, não só pra unidade), ficando invisível
# debaixo do chão. Quem garante "atrás da unidade, na frente do mapa" é
# battle.gd::resolve_capture, reordenando este nó na árvore (move_child)
# pra ficar logo ANTES do defensor na lista de filhos — mesmo z_index 0,
# só que desenhado antes (atrás) dele.
func play(open_texture: Texture2D, closed_texture: Texture2D, closed_frame_count: int, at_position: Vector2, success: bool, shake_count: int) -> void:
	position = at_position

	sprite.texture = open_texture
	sprite.rotation_degrees = 0.0
	sprite.self_modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(OPEN_DISPLAY_DURATION).timeout

	sprite.texture = _first_frame(closed_texture, closed_frame_count)
	# "Balança, para, balança, para, balança, para..." — uma pausa de
	# verdade (parada, sem rotação nenhuma) depois de CADA balanço, inclusive
	# o último, antes do desfecho (sucesso = máscara+fade; fracasso = abre
	# de novo). Sem essa pausa os balanços ficavam encadeados sem parar entre
	# um e outro, o que não é o efeito clássico de bola de Pokémon.
	for i in shake_count:
		await _wobble()
		await get_tree().create_timer(WOBBLE_PAUSE_DURATION).timeout

	if success:
		await _play_success()
	else:
		sprite.texture = open_texture
		await get_tree().create_timer(OPEN_DISPLAY_DURATION).timeout

	finished.emit()
	queue_free()

# Recorta só o primeiro quadro de uma sprite sheet horizontal — a bola
# "parada" durante o balanço usa só isso, não a animação inteira. Quadro
# largura = largura total / frame_count (NÃO assume quadrado, diferente da
# adivinhação padrão de Projectile — ver ItemData.ball_frame_count).
func _first_frame(strip_texture: Texture2D, frame_count: int) -> Texture2D:
	var frame_width = int(strip_texture.get_width()) / frame_count
	var frame_height = int(strip_texture.get_height())
	var atlas = AtlasTexture.new()
	atlas.atlas = strip_texture
	atlas.region = Rect2(0, 0, frame_width, frame_height)
	return atlas

# Um "balanço": gira pra um lado, volta bem além pro outro lado, volta pro
# centro — igual o clássico shake de bola dos jogos Pokémon.
func _wobble() -> void:
	var tween = create_tween()
	tween.tween_property(sprite, "rotation_degrees", WOBBLE_ANGLE_DEG, WOBBLE_STEP_DURATION)
	tween.tween_property(sprite, "rotation_degrees", -WOBBLE_ANGLE_DEG, WOBBLE_STEP_DURATION * 2)
	tween.tween_property(sprite, "rotation_degrees", 0.0, WOBBLE_STEP_DURATION)
	await tween.finished

# Sucesso: "máscara preta" (self_modulate pra preto, sem mexer no alpha —
# ainda visível, só ficou escura) e DEPOIS um fade de verdade (modulate.a
# até 0) — dois passos separados de propósito, pra a silhueta preta da bola
# fechada aparecer por um instante antes de sumir, em vez de escurecer e
# sumir ao mesmo tempo.
func _play_success() -> void:
	var tween = create_tween()
	tween.tween_property(sprite, "self_modulate", Color(0, 0, 0, 1), SUCCESS_MASK_DURATION)
	tween.tween_property(sprite, "modulate:a", 0.0, SUCCESS_FADE_DURATION)
	await tween.finished
