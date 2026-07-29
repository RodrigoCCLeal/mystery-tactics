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
#     Account'") abre a reserva NORMAL do jogador (GameState.storage). Só
#     aparece depois de GameState.flags["PC_ACCOUNT_REGISTERED"] (ver
#     baldo.gd — registra na primeira conversa depois de escolher starter).
#   - "Giovanni" abre "Giovanni's Account" (GameState.giovanni_storage —
#     unidades roubadas por treinadores Rocket, ver battle.gd::
#     resolve_capture) — pedido do usuário: "just add it as an option when
#     I interact with the PC", depois de uma tentativa anterior (um SEGUNDO
#     terminal físico só pra essa conta) que ele preferiu reverter. Só
#     aparece depois de GameState.flags["GIOVANNI_PC_UNLOCKED"] (ver
#     baldo.gd — a senha R0K37B055). Antes as duas opções ficavam sempre
#     visíveis, sem gate nenhum (comentário antigo já previa isso: "fácil
#     de adicionar depois... quando existir uma história que justifique
#     esconder 'Giovanni'" — agora existe).
#   - "Baldo" abre "Baldo's Account" (GameState.baldo_storage — 1 de cada
#     espécie nível 100) — pedido do usuário: "make a third account called
#     Baldo's Account". Só aparece depois de
#     GameState.flags["BALDO_PC_UNLOCKED"] (ver baldo.gd — a senha
#     142857080500, SEGUNDA senha válida, diferente da de Giovanni).
#   - "Heaven" abre "Heaven Account" (GameState.heaven_storage — unidades
#     que sofreram permadeath no modo Challenge, ver battle.gd::
#     _apply_challenge_permadeath) — pedido do usuário: "Updating Challenge
#     mode... Dead units aren't deleted, they go to Heaven Account. (Like
#     Giovanni's account) Requires password H34V3N0RH377 to access". Só
#     aparece depois de GameState.flags["HEAVEN_PC_UNLOCKED"] (ver
#     baldo.gd — a senha H34V3N0RH377, TERCEIRA senha válida).
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

const PC_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/pc_screen.tscn")

@onready var header_label: Label = $Center/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options
@onready var pc_option_label: Label = $Center/Panel/MarginContainer/Options/PC
@onready var giovanni_option_label: Label = $Center/Panel/MarginContainer/Options/Giovanni
@onready var baldo_option_label: Label = $Center/Panel/MarginContainer/Options/Baldo
@onready var heaven_option_label: Label = $Center/Panel/MarginContainer/Options/Heaven

var option_labels: Array[Label] = []
var selected_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_pc_option_label()
	# Esconde (não remove) quem ainda não foi desbloqueado — mesmo padrão de
	# title_screen.gd::load_game_label.visible (ver lá), e pelo MESMO motivo:
	# só entra em option_labels quem estiver visible=true NESTE ponto, então
	# visible precisa ser decidido ANTES do loop de baixo. open_pc.gd já
	# barra a interação inteira se NENHUM dos dois estiver desbloqueado (ver
	# lá), então "os dois escondidos ao mesmo tempo" não deveria acontecer
	# de verdade — mas nada aqui QUEBRARIA se acontecesse, só mostraria uma
	# lista vazia.
	pc_option_label.visible = GameState.get_flag("PC_ACCOUNT_REGISTERED")
	giovanni_option_label.visible = GameState.get_flag("GIOVANNI_PC_UNLOCKED")
	baldo_option_label.visible = GameState.get_flag("BALDO_PC_UNLOCKED")
	heaven_option_label.visible = GameState.get_flag("HEAVEN_PC_UNLOCKED")
	for child in options_container.get_children():
		if child is Label and child.visible and child != header_label:
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
	if option_labels.is_empty():
		return
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

func _activate_selected() -> void:
	if option_labels.is_empty():
		return
	# Nome do NODE (não mais um array OPTIONS paralelo indexado junto) —
	# mesmo motivo de title_screen.gd::_activate_selected: agora que
	# option_labels pode ter 1 ou 2 itens dependendo dos flags (ver _ready),
	# um array fixo separado ficaria dessincronizado do índice de verdade
	# assim que "PC" estivesse escondido e "Giovanni" fosse o único visível.
	match option_labels[selected_index].name:
		"PC":
			_open_pc_screen("storage")
		"Giovanni":
			_open_pc_screen("giovanni")
		"Baldo":
			_open_pc_screen("baldo")
		"Heaven":
			_open_pc_screen("heaven")

# mode repassado direto pra pc_screen.gd::reserve_mode — "storage" (reserva
# normal), "giovanni" (GameState.giovanni_storage), "baldo" ou "heaven"
# (GameState.heaven_storage), ver comentário grande
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
