extends CanvasLayer

# Popup genérico de pergunta Sim/Não — mesmo padrão de navegação de
# quit_confirm.gd (setas + X confirma + Z/Esc cancela = "No", mouse em
# paralelo), só que REUTILIZÁVEL: quem abre passa a pergunta (ver setup())
# e escuta a resposta pelo sinal `answered(yes)`, em vez de ter um efeito
# fixo embutido aqui. quit_confirm.gd continua existindo separado, só pra
# Sair do jogo (get_tree().quit()), que é uma ação específica demais pra
# valer a pena generalizar.
#
# Primeiro uso: nurse.gd, perguntando "Would you like to heal your
# Pokémon?" — mas serve pra qualquer NPC/situação futura que só precise de
# uma pergunta Sim/Não simples.
#
# SEM "Dim" (o ColorRect que escurecia a tela inteira nos outros popups do
# projeto, ver quit_confirm.tscn) e ancorado embaixo (node "Box", não mais
# centralizado) — feedback do usuário: falar com um NPC não deve escurecer
# o mapa inteiro, e a caixa de texto não deve ficar no meio da tela tampando
# a visão. Vale pra qualquer popup de diálogo de NPC daqui pra frente, não
# só este.

signal answered(yes: bool)

const OPTIONS = ["Yes", "No"]

@onready var header_label: Label = $Box/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Box/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
# Começa em "No" (índice 1) — mesmo cuidado de quit_confirm.gd: a resposta
# tem um efeito de verdade (curar o time, ou o que for no futuro), então o
# cursor não deve começar em cima da opção que "faz alguma coisa".
var selected_index: int = 1

func setup(question: String) -> void:
	header_label.text = question

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in options_container.get_children():
		if child is Label and child != header_label:
			option_labels.append(child)
	for i in option_labels.size():
		var label := option_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_option_mouse_entered.bind(i))
		label.gui_input.connect(_on_option_gui_input.bind(i))
	_update_selection_visual()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_activate_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_finish(false)
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, OPTIONS.size())
	_update_selection_visual()

func _on_option_mouse_entered(index: int) -> void:
	selected_index = index
	_update_selection_visual()

func _on_option_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_activate_selected()

func _update_selection_visual() -> void:
	for i in option_labels.size():
		option_labels[i].modulate = Color.YELLOW if i == selected_index else Color.WHITE

func _activate_selected() -> void:
	_finish(OPTIONS[selected_index] == "Yes")

func _finish(yes: bool) -> void:
	answered.emit(yes)
	queue_free()
