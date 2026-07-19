extends CanvasLayer

# Caixa de texto de UMA linha, mesmo estilo visual de yes_no_prompt.tscn
# (Box ancorado embaixo, sem "Dim" — não escurece o mapa, ver comentário
# lá) — só a mensagem, sem opção nenhuma escrita na tela (pedido do
# usuário: "Remove the OK from the Spotted Message, leave just the
# message"). Fecha com X OU Z/Esc de qualquer jeito (ver _unhandled_input),
# só não tem mais um label "OK" pra clicar com o mouse.
#
# Usada por trainer.gd::_spot_player() pra dar tempo entre o Trainer
# avistar o jogador e a batalha realmente começar (pedido do usuário: "Only
# start the battle after the player pressed X to Ok").

signal closed

@onready var header_label: Label = $Box/Panel/MarginContainer/Options/Header

func setup(text: String) -> void:
	header_label.text = text

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm") or event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_finish()

func _finish() -> void:
	closed.emit()
	queue_free()
