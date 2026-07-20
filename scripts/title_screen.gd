extends CanvasLayer

# Tela inicial do jogo (run/main_scene, ver project.godot) — a PRIMEIRA coisa
# que aparece ao abrir o jogo, antes de qualquer overworld/batalha existir.
# "Load Game" só aparece se existir PELO MENOS um save em algum dos 3 slots
# (ver GameState.has_save) — escondido (não removido) se nenhum existir,
# mesma ideia de esconder um Label em vez de destruir ele, só que aqui a
# lista de opções realmente varia de tamanho em vez de ser sempre fixa como
# em game_menu.gd/system_menu.gd.
#
# Mesma navegação de sempre (setas + X confirma, mouse em paralelo) — SEM
# "Z/Esc fecha", diferente de todo popup do resto do jogo: esta é a tela
# RAIZ, não existe "voltar" daqui pra lugar nenhum.

const SAVE_SLOT_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/save_slot_screen.tscn")
const OPTIONS_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/options_screen.tscn")

@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options
@onready var title_label: Label = $Center/Panel/MarginContainer/Options/Title
@onready var load_game_label: Label = $Center/Panel/MarginContainer/Options/LoadGame

var option_labels: Array[Label] = []
var selected_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var any_save = false
	for slot in GameState.SAVE_SLOT_COUNT:
		if GameState.has_save(slot):
			any_save = true
			break
	load_game_label.visible = any_save
	# Só entra em option_labels quem estiver visible=true NESTE ponto (por
	# isso load_game_label.visible precisa ser decidido ANTES deste loop) E
	# não for o título "Mystery Tactics" (child != title_label, mesmo
	# critério de exclusão de header que bag_screen.gd/computer_screen.gd já
	# usam pros próprios Header).
	for child in options_container.get_children():
		if child is Label and child.visible and child != title_label:
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
	else:
		return
	# Guard, não chamada direta — mesmo crash de quit_confirm.gd (ver
	# comentário grande lá): _activate_selected() pode ter escolhido "Exit"
	# e chamado get_tree().quit(), e a Viewport pode já não existir mais
	# quando chega nesta linha.
	var viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()

func _move_selection(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, option_labels.size())
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

# Identifica a opção pelo NOME do node (ver title_screen.tscn) em vez de um
# array paralelo tipo OPTIONS — diferente do resto do projeto, aqui a lista
# de fato muda de tamanho (Load Game pode não existir), então casar por
# posição/índice seria frágil.
func _activate_selected() -> void:
	match option_labels[selected_index].name:
		"NewGame":
			_open_slot_screen("new")
		"LoadGame":
			_open_slot_screen("load")
		"OptionsItem":
			_open_options()
		"Exit":
			get_tree().quit()

func _open_slot_screen(mode: String) -> void:
	hide()
	var screen = SAVE_SLOT_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(mode)
	screen.closed.connect(show)

func _open_options() -> void:
	hide()
	var screen = OPTIONS_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)
