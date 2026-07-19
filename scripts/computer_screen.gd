extends CanvasLayer

# Tela do "Computador" — antes acessível pelo menu de pausa (opção "PC" do
# menu A, ver game_menu.gd), agora só abre interagindo com um terminal de
# verdade no overworld (ver open_pc.gd, pedido do usuário: "remove the PC
# option from the A menu... When this actor is interacted with, activate
# 'PC' menu"). DUAS opções, as duas abrindo pc_screen.tscn (troca de
# unidades entre time ativo e reserva) como sub-tela, escondendo-se por
# baixo — mesmo padrão de esconder/reaparecer usado em pause_menu.gd/
# party_screen.gd pra sub-menus:
#   - "PC" (Label renomeado em _ready(), ver _refresh_pc_option_label —
#     pedido do usuário: "Rename the 'PC' inside 'PC' to 'PLAYERNAME's
#     Account'") abre a reserva NORMAL do jogador (GameState.storage).
#   - "Giovanni" abre "Giovanni's Account" (GameState.giovanni_storage —
#     unidades roubadas por treinadores Rocket, ver battle.gd::
#     resolve_capture) — pedido do usuário: "just add it as an option when
#     I interact with the PC", depois de uma tentativa anterior (um SEGUNDO
#     terminal físico só pra essa conta) que ele preferiu reverter. As duas
#     opções ficam sempre visíveis, sem gate de flag nenhum por enquanto —
#     fácil de adicionar depois (mesmo padrão de loot_ball.gd::exclusive_flag)
#     quando existir uma história que justifique esconder "Giovanni" até o
#     jogador descobrir essa conta.
#
# "Heal" existia aqui só pra debug (curar o time sem precisar achar a Nurse)
# e foi removido agora que existe um jeito de verdade, dentro da ficção, de
# curar (ver nurse.gd — falar com o NPC "Nurse" no overworld). GameState.
# heal_active_roster() continua existindo, só que quem chama agora é
# nurse.gd, não mais esta tela.
#
# Mesma estrutura de navegação de pause_menu.gd/slot_action_menu.gd: setas
# trocam a opção, X confirma, Z ou Esc fecha; mouse funciona em paralelo.

signal closed

const OPTIONS = ["PC", "Giovanni"]
const PC_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/pc_screen.tscn")

@onready var header_label: Label = $Center/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options
@onready var pc_option_label: Label = $Center/Panel/MarginContainer/Options/PC
# "Giovanni" (ver Center/Panel/MarginContainer/Options/Giovanni no .tscn)
# não precisa de @onready próprio — texto fixo, sem nome de jogador pra
# interpolar (diferente de pc_option_label acima) — só entra na varredura
# genérica de option_labels em _ready() abaixo, igual qualquer opção nova
# que ganhe texto estático no futuro.

var option_labels: Array[Label] = []
var selected_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_pc_option_label()
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

# Texto do Label "PC" (a opção que abre a reserva NORMAL) vira "<nome do
# jogador>'s Account" em vez do literal "PC" — pedido do usuário. Chamado
# uma vez em _ready() (mesmo espírito de game_menu.gd::_refresh_header):
# player_name não muda enquanto esta tela está aberta. "Giovanni's Account"
# já vem certo direto do .tscn (nome fixo, não depende do jogador).
func _refresh_pc_option_label() -> void:
	pc_option_label.text = "%s's Account" % GameState.player_name

# Mesmo motivo do "if not visible: return" em pause_menu.gd — enquanto
# pc_screen está aberta por cima (this hide()-ado), não processa input.
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
		"PC":
			_open_pc_screen("storage")
		"Giovanni":
			_open_pc_screen("giovanni")

# mode repassado direto pra pc_screen.gd::reserve_mode — "storage" (reserva
# normal) ou "giovanni" (GameState.giovanni_storage), ver comentário grande
# no topo do arquivo.
func _open_pc_screen(mode: String) -> void:
	hide()
	var screen = PC_SCREEN_SCENE.instantiate()
	screen.reserve_mode = mode
	add_child(screen)
	# pc_screen.gd já faz queue_free() em si mesmo ao fechar — só precisamos
	# reaparecer (mesmo padrão de pause_menu.gd::_open_party_screen).
	screen.closed.connect(show)

func _close() -> void:
	closed.emit()
	queue_free()
