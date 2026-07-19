extends CanvasLayer

# Menu do SISTEMA (Configurações/Exit) — abre com Esc (ver test.gd::
# _open_system_menu). Segundo menu do overworld, separado do game_menu.gd
# (aberto com "A") — "Exit" morava dentro do menu de "A" antes (era
# pause_menu.gd), mas o usuário pediu pra mover pra cá, indo pra tela de
# título em vez de fechar o jogo de vez (era get_tree().quit() antes, ver
# quit_confirm.gd removido).
#
# "Configurações" abre options_screen.tscn (MESMA cena usada pelo "Options"
# da tela de título, ver title_screen.gd) como sub-tela (hide()/show()),
# igual qualquer outro sub-menu do projeto. "Exit" pergunta antes (reusa
# yes_no_prompt.gd, genérico Sim/Não) porque troca de cena pra
# title_screen.tscn PERDE qualquer progresso feito desde o último Save de
# verdade (GameState não é limpo — só troca de tela; um "New Game"/
# "Load Game" seguinte é que de fato substitui os dados, ver GameState.
# start_new_game/load_game) — daí o aviso "Unsaved data will be lost".

signal closed

const OPTIONS = ["Configurações", "Exit"]
const OPTIONS_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/options_screen.tscn")
const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")
const TITLE_SCREEN_PATH = "res://scenes/ui/screens/title_screen.tscn"

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
	match OPTIONS[selected_index]:
		"Configurações":
			_open_options()
		"Exit":
			_open_exit_confirm()

func _open_options() -> void:
	hide()
	var screen = OPTIONS_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)

func _open_exit_confirm() -> void:
	hide()
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("Are you sure? Unsaved data will be lost")
	prompt.answered.connect(_on_exit_answered)

func _on_exit_answered(yes: bool) -> void:
	if yes:
		# get_tree().paused foi ligado por test.gd ao abrir este menu (ver
		# _open_system_menu) — precisa desligar ANTES de trocar de cena,
		# senão a árvore nova (title_screen) nasceria pausada também (Node
		# comum para de processar _process/_input com a árvore pausada; só
		# CanvasLayer com PROCESS_MODE_ALWAYS, como este e title_screen.gd,
		# escapa disso, mas não vale a pena depender só disso).
		get_tree().paused = false
		get_tree().change_scene_to_file(TITLE_SCREEN_PATH)
	else:
		show()

func _close() -> void:
	closed.emit()
	queue_free()
