extends CanvasLayer

# Autoload (ver project.godot [autoload]) — sobrevive à troca de cena, ao
# contrário de QUALQUER node dentro de Test/World/HouseInterior (que
# change_scene_to_file() destrói inteiro). É exatamente isso que permite um
# fade-to-black que começa ANTES da troca de cena e termina DEPOIS dela: um
# node comum na cena antiga sumiria junto com o resto no meio do fade.
#
# ColorRect preto cobrindo a tela inteira, com a transparência (alpha)
# animada por Tween — 0 = invisível (cena normal), 1 = tela toda preta.

@onready var rect: ColorRect = $ColorRect

func _ready() -> void:
	# layer alto = desenha por CIMA de qualquer CanvasLayer comum (HUD de
	# batalha, game_menu/system_menu...), que usam o layer padrão (1) — o
	# fade tem que cobrir a tela INTEIRA, inclusive menu aberto.
	layer = 100
	rect.color = Color(0, 0, 0, 0)

# Escurece a tela, troca de cena (Door.target_scene_path, ver door.gd), e
# clareia de novo depois que a cena nova já montou. Chamado SEM "await" por
# quem usa (ver test.gd/world.gd/house_interior.gd::use_door) — roda
# sozinho em segundo plano, ninguém precisa esperar ele terminar.
func change_scene_with_fade(scene_path: String, fade_duration: float = 0.25) -> void:
	await fade_to(1.0, fade_duration)
	get_tree().change_scene_to_file(scene_path)
	# process_frame garante que a cena nova já terminou de entrar na árvore
	# (change_scene_to_file troca no próximo idle frame, não na hora) antes
	# de começar a clarear — sem isso, o clareamento podia começar em cima
	# de um frame ainda com a cena antiga/vazia.
	await get_tree().process_frame
	await fade_to(0.0, fade_duration)

func fade_to(target_alpha: float, duration: float) -> void:
	var tween = create_tween()
	tween.tween_property(rect, "color:a", target_alpha, duration)
	await tween.finished
