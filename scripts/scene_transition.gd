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

# True do início ao fim de change_scene_with_fade() — bug reportado pelo
# usuário: "if the player presses A or ESC during scene transitions the
# game freezes". Causa: SceneTransition roda com PROCESS_MODE_ALWAYS (ver
# _ready() abaixo), então continua seu fade/await MESMO se a árvore for
# pausada nesse meio-tempo — e "A"/Esc no overworld (ver world.gd/
# house_interior.gd::_open_game_menu/_open_system_menu) fazem EXATAMENTE
# isso: pausam a árvore E entram como filho da cena antiga, que está prestes
# a ser destruída pelo change_scene_to_file() logo abaixo. Resultado: a cena
# nova nascia com a árvore ainda pausada pra sempre (ninguém nunca rodava
# _on_menu_closed() do menu que sumiu junto com a cena antiga) — parecia o
# jogo inteiro ter travado, já que só node com PROCESS_MODE_ALWAYS continua
# processando com paused=true. is_active é consultado por essas duas funções
# (guard "if SceneTransition.is_active: return", mesmo espírito do guard
# "if active_menu != null: return" que já existia) pra simplesmente recusar
# abrir menu nenhum enquanto o fade estiver rolando — e change_scene_with_fade
# ainda desliga get_tree().paused como segunda camada de defesa (ver abaixo),
# caso algum caminho futuro pause a árvore por outro motivo durante o fade.
var is_active: bool = false

func _ready() -> void:
	# layer alto = desenha por CIMA de qualquer CanvasLayer comum (HUD de
	# batalha, game_menu/system_menu...), que usam o layer padrão (1) — o
	# fade tem que cobrir a tela INTEIRA, inclusive menu aberto.
	layer = 100
	rect.color = Color(0, 0, 0, 0)
	# PROCESS_MODE_ALWAYS — fade_to() usa create_tween(), e um Tween ligado a
	# um node com PROCESS_MODE_INHERIT (o padrão) para de avançar junto com
	# QUALQUER pausa (get_tree().paused = true, usado por praticamente toda
	# tela do projeto). Até agora nunca importava (nenhum use_door() rodava
	# com a árvore pausada), mas bed.gd precisa pausar a árvore ENQUANTO
	# desmaia a tela pro "cochilo" (ver bed.gd::_on_answered) — sem isso, o
	# await fade_to() nunca terminaria e o jogo ficaria travado com a tela
	# preta pra sempre (mesma classe de bug já visto no relógio de
	# GameState).
	process_mode = Node.PROCESS_MODE_ALWAYS

# Escurece a tela, troca de cena (Door.target_scene_path, ver door.gd), e
# clareia de novo depois que a cena nova já montou. Chamado SEM "await" por
# quem usa (ver world.gd/house_interior.gd::use_door) — roda
# sozinho em segundo plano, ninguém precisa esperar ele terminar.
func change_scene_with_fade(scene_path: String, fade_duration: float = 0.25) -> void:
	is_active = true
	await fade_to(1.0, fade_duration)
	# Segunda camada de defesa (ver comentário grande em is_active acima) —
	# se por algum motivo a árvore ainda estiver pausada aqui (um menu que
	# conseguiu abrir antes do guard em world.gd/house_interior.gd, ou
	# qualquer outra fonte futura de pause), desliga ANTES de trocar de
	# cena. Mesma lição já aplicada em world.gd (linha perto de
	# is_trainer_battle)/house_interior.gd/system_menu.gd: SceneTree.paused
	# sobrevive a change_scene_to_file() sozinho, a cena nova nasceria
	# pausada por engano sem isso.
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)
	# process_frame garante que a cena nova já terminou de entrar na árvore
	# (change_scene_to_file troca no próximo idle frame, não na hora) antes
	# de começar a clarear — sem isso, o clareamento podia começar em cima
	# de um frame ainda com a cena antiga/vazia.
	await get_tree().process_frame
	await fade_to(0.0, fade_duration)
	is_active = false

func fade_to(target_alpha: float, duration: float) -> void:
	var tween = create_tween()
	tween.tween_property(rect, "color:a", target_alpha, duration)
	await tween.finished
