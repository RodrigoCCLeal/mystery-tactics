extends "res://scripts/npc.gd"

# Baldo (assets/sprites/Human/Important Character/trainer_BALDO.png) — o NPC
# tutorial do jogo. Falar com ele de frente (ver world.gd::_try_interact)
# abre tutorial_screen.tscn direto, sem pergunta Sim/Não nenhuma (diferente
# da Enfermeira) — não existe "recusar" um tutorial, é só informação.
#
# get_tree().paused = true/false ao redor do popup é o MESMO padrão de
# nurse.gd — trava o overworld inteiro enquanto o tutorial está na tela.

const TUTORIAL_SCREEN_SCENE: PackedScene = preload("res://scenes/tutorial_screen.tscn")

func interact() -> void:
	var screen = TUTORIAL_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(_on_closed)
	get_tree().paused = true

func _on_closed() -> void:
	get_tree().paused = false
