extends Node2D

# Efeito visual de "as folhas da grama alta se mexendo" — toca uma vez (sem
# loop) na célula onde o personagem acabou de pisar, e se destrói sozinho
# quando a animação termina. Instanciado por world.gd toda vez que o
# personagem entra numa célula de grama alta (mesmo gancho do contador de
# encontro aleatório, ver World._on_player_tile_entered()).
#
# A SpriteFrames (grass_rustle_frames.tres) ainda está VAZIA — falta a arte
# recortada quadro a quadro. Combinado: o Rodrigo recorta cada folha de
# D:\Assets\Graphics\Animations\Overworld dust and grass.png numa imagem
# separada (os quadros não ficam num grid limpo — foram posicionados à mão
# no editor de animação do RPG Maker XP, sem espaçamento uniforme) e me
# manda; aí eu monto os frames da animação "rustle" nesse .tres. Até lá,
# isso só instancia e se desfaz na hora, sem crashar nem vazar node.

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	if anim.sprite_frames == null or anim.sprite_frames.get_frame_count("rustle") <= 0:
		queue_free()   # ainda sem quadros configurados — nada pra tocar
		return
	anim.animation_finished.connect(queue_free)
	anim.play("rustle")
