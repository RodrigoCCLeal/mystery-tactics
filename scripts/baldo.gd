extends "res://scripts/npc.gd"

# Baldo (assets/sprites/Human/Important Character/trainer_BALDO.png) — mora
# na própria casa (baldo_house_interior.tscn). Antes era só o NPC de
# tutorial (abria tutorial_screen.tscn direto); pedido do usuário agora é
# um papel novo, com conversa de verdade em 3 estágios, decidido por dois
# flags em GameState.flags (mesmo sistema genérico que loot_ball.gd::
# exclusive_flag/Player.unlock_song já usam — string crua, sem registro
# central, ver comentário grande em GameState.flags):
#
#   1. Sem STARTER1_CHOSEN (jogador ainda não escolheu starter no
#      laboratório do Oak, ver oak_lab_interior.tscn) -> "I'm busy, come
#      back later", sempre, não importa quantas vezes o jogador volte.
#   2. Com STARTER1_CHOSEN mas SEM PC_ACCOUNT_REGISTERED -> registra a
#      conta (seta a flag, ver computer_screen.gd/open_pc.gd que agora
#      escondem a opção "PC" até isso acontecer) e mostra a mensagem UMA
#      VEZ só — pedido do usuário: "this... can only happen once".
#   3. Depois de registrado -> pergunta Sim/Não "Did you find a
#      password?". "Yes" pede a senha digitada (texto livre, ver
#      text_input_prompt.gd); certa (ver PASSWORDS abaixo — duas por
#      enquanto, cada uma desbloqueia uma conta diferente) seta a flag
#      correspondente e comemora; errada só desconversa sem punição
#      nenhuma (pode tentar de novo quantas vezes quiser, inclusive depois
#      de já ter acertado uma — sem essa trava, TODAS as flags aqui
#      seriam "só a primeira vez conta", o que não foi pedido pra este
#      caso). "No" também só desconversa.
#
# get_tree().paused fica true do INÍCIO ao FIM da conversa inteira, mesmo
# quando ela passa por várias caixas seguidas — só desliga em
# _end_conversation(), no fundo de TODA ramificação, mesmo padrão de
# trainer.gd::_pausing_for_battle (pausa uma vez só lá no início; quem
# desliga de novo é sempre o fim de verdade da sequência, nunca um popup
# individual no meio do caminho).

const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")
const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")
const TEXT_INPUT_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/text_input_prompt.tscn")

# Senha -> flag desbloqueada por ela. Pedido do usuário original: "the only
# working password is R0K37B055, that unlocks Giovanni's PC" — depois:
# "make a third account called Baldo's Account... To unlock it, must give
# password 142857080500" — e agora uma quarta: "Dead units aren't deleted,
# they go to Heaven Account. (Like Giovanni's account) Requires password
# H34V3N0RH377 to access". Tabela em vez de constantes soltas + um "if"
# repetido por senha, pra uma QUINTA senha futura ser só mais uma linha
# aqui (ver _on_password_submitted abaixo, já genérico pra N entradas).
const PASSWORDS = {
	"R0CK37B055": "GIOVANNI_PC_UNLOCKED",
	"142857080500": "BALDO_PC_UNLOCKED",
	"H34V3N0RH377": "HEAVEN_PC_UNLOCKED",
}

func interact() -> void:
	get_tree().paused = true
	if not GameState.get_flag("STARTER1_CHOSEN"):
		_say("I'm busy, come back later", _end_conversation)
		return
	if not GameState.get_flag("PC_ACCOUNT_REGISTERED"):
		GameState.set_flag("PC_ACCOUNT_REGISTERED")
		_say("Hey, you're a new trainer right? Let me register you on Pokémon Home", _end_conversation)
		return
	_ask_password()

func _ask_password() -> void:
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("Did you find a password?")
	prompt.answered.connect(_on_password_question_answered)

func _on_password_question_answered(yes: bool) -> void:
	if not yes:
		_end_conversation()
		return
	var input = TEXT_INPUT_PROMPT_SCENE.instantiate()
	add_child(input)
	input.setup("What's the password?")
	input.submitted.connect(_on_password_submitted)
	input.cancelled.connect(_end_conversation)

func _on_password_submitted(text: String) -> void:
	if PASSWORDS.has(text):
		GameState.set_flag(PASSWORDS[text])
		_say("Holy Moly, it works!", _end_conversation)
	else:
		_say("I don't think that works...", _end_conversation)

# Helper genérico pra abrir a caixa de texto de 1 linha (trainer_message_box,
# mesma reaproveitada em player.gd/save_slot_screen.gd) e encadear o que
# vem depois quando ela fechar — on_closed pode ser _end_conversation (fim
# de verdade) ou outra função no meio da sequência.
func _say(text: String, on_closed: Callable) -> void:
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(text)
	box.closed.connect(on_closed)

# Fim de QUALQUER ramo da conversa — pedido do usuário: "Baldo always faces
# up after finishing a conversation with the player" (diferente do resto
# do projeto: normalmente um NPC fica olhando pra direção de onde o
# jogador falou com ele, ver npc.gd::face_towards, chamado ANTES de
# interact() por world.gd/house_interior.gd::_try_interact — Baldo desfaz
# isso de propósito assim que a conversa termina, não importa qual ramo).
func _end_conversation() -> void:
	facing = "up"
	anim.play("idle_up")
	get_tree().paused = false
