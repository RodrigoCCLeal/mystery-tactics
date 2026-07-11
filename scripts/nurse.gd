extends "res://scripts/npc.gd"

# Nurse (assets/sprites/Human/NPC/NPC 16.png) — primeiro NPC do jogo.
# Herda toda a parte de aparência/posição no grid de npc.gd (ver comentário
# lá) e só sobrescreve interact(): falar com ela de frente (ver
# world.gd::_try_interact) abre uma pergunta Sim/Não (yes_no_prompt.gd)
# perguntando se o jogador quer curar o time; "Yes" cura na hora, com o
# MESMO efeito que o botão "Heal" do Computador tinha (ver GameState.
# heal_active_roster()) — aquele botão era só um atalho de debug e foi
# removido agora que existe este jeito "de verdade", dentro da ficção, de
# curar (ver computer_screen.gd).
#
# get_tree().paused = true/false ao redor do popup é o MESMO padrão que
# world.gd já usa pro menu de pausa (ver _open_pause_menu/
# _on_pause_menu_closed) — trava o Player (e o resto do overworld) enquanto
# a pergunta está na tela, sem precisar duplicar nenhuma lógica de "ignorar
# input do jogo enquanto um popup estiver aberto".

const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/yes_no_prompt.tscn")

func interact() -> void:
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("Would you like to heal your Pokémon?")
	prompt.answered.connect(_on_answered)
	get_tree().paused = true

func _on_answered(yes: bool) -> void:
	if yes:
		GameState.heal_active_roster()
	get_tree().paused = false
