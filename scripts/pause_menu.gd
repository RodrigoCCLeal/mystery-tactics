extends CanvasLayer

# Menu de pausa do overworld (abre com Esc, ver test.gd::_open_pause_menu).
# CanvasLayer em vez de Node2D comum porque CanvasLayer desenha em espaço de
# TELA, ignorando a Camera2D do Player — senão o menu se moveria/escalaria
# junto com o mundo, que não é o que queremos pra uma UI.
#
# Navegação usa as MESMAS ações do resto do jogo (ver [input] em
# project.godot): "confirm" (X) escolhe a opção selecionada, "cancel" (Z)
# fecha o menu a qualquer momento — igual "menu" (Esc), que também fecha se
# apertado de novo com o menu já aberto. ui_up/ui_down (setas) trocam a
# opção. "Exit" é a única opção que NÃO só fecha este menu — abre um popup
# de confirmação (ver quit_confirm.gd) e só fecha o jogo de vez (get_tree().
# quit()) se a resposta for "Sim".
#
# Mouse funciona em paralelo ao teclado, não em vez dele: passar o mouse em
# cima de uma opção move a seleção pra ela (mesmo destaque amarelo de
# quando se navega com as setas) e clicar equivale a apertar "confirm". Os
# Labels não recebem eventos de mouse por padrão (mouse_filter começa como
# IGNORE) — por isso _ready() liga mouse_filter = STOP em cada um.
#
# process_mode = ALWAYS é essencial: sem isso, esse node também para de
# processar input assim que a árvore pausa (get_tree().paused = true, feito
# por test.gd ao abrir o menu) e o jogador ficaria travado sem conseguir
# fechar o menu.

signal closed

const OPTIONS = ["PlayerName", "Pokémon", "Computador", "Bag", "Save", "Exit"]
const PARTY_SCREEN_SCENE: PackedScene = preload("res://scenes/party_screen.tscn")
const COMPUTER_SCREEN_SCENE: PackedScene = preload("res://scenes/computer_screen.tscn")
const BAG_SCREEN_SCENE: PackedScene = preload("res://scenes/bag_screen.tscn")
const QUIT_CONFIRM_SCENE: PackedScene = preload("res://scenes/quit_confirm.tscn")

@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
var selected_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in options_container.get_children():
		if child is Label:
			option_labels.append(child)
	for i in option_labels.size():
		var label := option_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_option_mouse_entered.bind(i))
		label.gui_input.connect(_on_option_gui_input.bind(i))
	_update_selection_visual()

func _unhandled_input(event: InputEvent) -> void:
	# Enquanto a Party (ou outro sub-menu futuro) está aberta por cima,
	# este menu fica hide()-ado mas NÃO para de existir/processar input
	# sozinho — sem essa checagem, X/Z/setas seriam lidos duas vezes (uma
	# vez pelo sub-menu, outra por este _unhandled_input ainda ativo por
	# baixo). visible já é exatamente o que _open_party_screen()/show()
	# alternam, então é a checagem mais simples que já reflete isso.
	if not visible:
		return
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_activate_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, OPTIONS.size())
	_update_selection_visual()

# Passar o mouse em cima de uma opção seleciona ela, igual as setas — não
# ativa sozinho (isso só acontece com clique, ver _on_option_gui_input).
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

# Cada opção só imprime um TODO por enquanto — as telas de verdade
# (time/mochila/nome/save) ainda não existem. Trocar o print() pelo que
# for abrir cada uma quando chegar a hora, sem mexer no resto do menu.
func _activate_selected() -> void:
	match OPTIONS[selected_index]:
		"Exit":
			_open_quit_confirm()
		"PlayerName":
			print("TODO: tela de nome do jogador")
		"Pokémon":
			_open_party_screen()
		"Computador":
			_open_computer_screen()
		"Bag":
			_open_bag_screen()
		"Save":
			print("TODO: salvar jogo")

# A tela de Party entra como sub-menu: esconde (sem fechar) o menu de
# pausa por baixo — a árvore continua pausada o tempo todo, test.gd só
# despausa quando O MENU DE PAUSA fecha de vez, não quando um submenu dele
# fecha. Fechar a Party (Z lá sem nada selecionado pra trocar) só volta a
# mostrar este menu de novo.
func _open_party_screen() -> void:
	hide()
	var screen = PARTY_SCREEN_SCENE.instantiate()
	add_child(screen)
	# party_screen.gd já faz queue_free() em si mesmo ao fechar (mesmo
	# padrão de _close() aqui embaixo) — só precisamos reaparecer.
	screen.closed.connect(show)

# Mesmo padrão de _open_party_screen() acima — ver computer_screen.gd.
func _open_computer_screen() -> void:
	hide()
	var screen = COMPUTER_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)

# Mesmo padrão de _open_party_screen()/_open_computer_screen() acima — ver
# bag_screen.gd.
func _open_bag_screen() -> void:
	hide()
	var screen = BAG_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)

# Mesmo padrão de esconder/reaparecer de novo — se a resposta for "Não" (ou
# Z), quit_confirm.gd só fecha a si mesmo e este menu volta a aparecer,
# como se "Exit" nunca tivesse sido escolhido. Se for "Sim", o jogo fecha
# antes disso importar (get_tree().quit() dentro de quit_confirm.gd).
func _open_quit_confirm() -> void:
	hide()
	var screen = QUIT_CONFIRM_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)

func _close() -> void:
	closed.emit()
	queue_free()
