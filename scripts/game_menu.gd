extends CanvasLayer

# Menu do JOGO (Pokémon/Bag/Save/Pokédex) — abre com "A" (ver world.gd::
# _open_game_menu). Era o antigo pause_menu.gd (que tinha "PlayerName" fixo
# como Label clicável sem efeito e "Exit" dentro dele) — agora dividido em
# dois: "Exit" mudou pra system_menu.gd (aberto com Esc, ver aquele
# arquivo), e o antigo Label "PlayerName" virou um HEADER de verdade (não
# clicável, ver header_label abaixo), mostrando nome/dinheiro/badges do
# jogador atual em vez de um texto fixo sem função.
#
# A opção "PC" que existia aqui foi REMOVIDA a pedido do usuário — agora o
# PC só abre interagindo com um terminal de verdade no overworld (ver
# open_pc.gd/computer_screen.tscn), não mais pelo menu A.
#
# Mesma navegação/mouse/sub-menu (hide()/show()) de sempre — ver
# comentários originais em pause_menu.gd (removido) se quiser comparar.

signal closed

const OPTIONS = ["Pokémon", "Bag", "Save", "Pokédex"]
const PARTY_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/party_screen.tscn")
const BAG_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/bag_screen.tscn")

@onready var header_label: Label = $Center/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
var selected_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_header()
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

# Nome do jogador + dinheiro (sempre inteiro, pedido do usuário) + quantas
# badges já tem — substitui o antigo texto fixo "PlayerName". Chamado só
# uma vez em _ready() porque nenhum desses 3 valores muda enquanto este
# menu está aberto (nenhuma das opções altera dinheiro/badges ainda).
func _refresh_header() -> void:
	header_label.text = "%s     $%d     Badges: %d" % [GameState.player_name, GameState.money, GameState.badges.size()]

# Mesmo motivo do "if not visible: return" no antigo pause_menu.gd — enquanto
# um sub-menu (Party/PC/Bag) está aberto por cima, este continua hide()-ado
# mas processando input sozinho se não fosse por esta checagem.
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
		"Pokémon":
			_open_party_screen()
		"Bag":
			_open_bag_screen()
		"Save":
			_save_game()
		"Pokédex":
			# TODO: ainda não existe tela de Pokédex — só a opção no menu por
			# enquanto, mesmo padrão de placeholder que "PlayerName"/"Save" já
			# usaram aqui antes de terem uma tela/efeito de verdade.
			print("TODO: tela de Pokédex")

func _open_party_screen() -> void:
	hide()
	var screen = PARTY_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)

func _open_bag_screen() -> void:
	hide()
	var screen = BAG_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)

# Sobrescreve o save do slot atual (ver GameState.current_save_slot/
# save_game) com o estado de AGORA — sem tela de confirmação nem "Salvo!"
# por enquanto (feedback visual futuro, se fizer falta); fechar o menu
# sozinho depois de Save já funciona como uma confirmação simples de que
# aconteceu.
func _save_game() -> void:
	GameState.save_game(GameState.current_save_slot)
	_close()

func _close() -> void:
	closed.emit()
	queue_free()
