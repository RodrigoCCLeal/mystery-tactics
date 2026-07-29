extends CanvasLayer

# Tela de fim de jogo do modo Challenge — pedido do usuário: "Updating
# Challenge mode... When all Units from the team are defeated, display Game
# Over screen with the prompt Load Save or Delete Save". Instanciada só por
# battle.gd::end_battle(), no lugar do fluxo normal de vitória/derrota,
# quando GameState.game_mode == "challenge" e GameState.get_active_roster()
# fica TOTALMENTE vazia — permadeath (ver battle.gd::
# _apply_challenge_permadeath) já tira cada unidade do roster conforme
# desmaia; chegar aqui com o roster vazio significa não sobrar NENHUMA
# unidade pra continuar jogando.
#
# "Dim" (ColorRect escurecendo a tela inteira) porque, diferente de
# title_screen.gd (que É a cena raiz, sem nada "atrás"), esta tela nasce por
# CIMA da batalha ainda visível (campo, unidades desmaiadas, HUD) — sem o
# Dim, esse cenário de derrota ficaria comicamente visível atrás da caixa.
#
# Duas opções, SEM "voltar" (Z/Esc não faz nada aqui, mesmo espírito de
# title_screen.gd — não existe cena nenhuma "por baixo" pra onde cancelar
# de volta; a batalha já está em Phase.ENDED e as duas opções acabam com
# ela de um jeito ou de outro):
#   - "Load Save": recarrega o ÚLTIMO save de verdade (GameState.
#     current_save_slot) — NÃO o checkpoint de cura (last_heal_*) que a
#     derrota comum usa nos outros dois modos. O jogador volta pra onde
#     estava da ÚLTIMA VEZ que deu Save de propósito (ver game_menu.gd),
#     podendo perder progresso feito depois disso — mesmo aviso que já
#     existe no menu de pausa ao sair pro título.
#   - "Delete Save": apaga o arquivo do slot pra sempre (GameState.
#     delete_save) e manda o jogador de volta pro Título — a run inteira de
#     Challenge acaba aqui, sem chance de tentar carregar de novo.

const TITLE_SCREEN_PATH = "res://scenes/ui/screens/title_screen.tscn"
# Reaproveitada só pro caso raro de "Load Save" falhar (save corrompido/
# dependência faltando, ver GameState.peek_save) — mesmo componente usado
# por save_slot_screen.gd pro mesmo aviso.
const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")

@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options
@onready var title_label: Label = $Center/Panel/MarginContainer/Options/Title

var option_labels: Array[Label] = []
var selected_index: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in options_container.get_children():
		if child is Label and child != title_label:
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
	else:
		return
	# Guard, não chamada direta — mesmo crash de quit_confirm.gd/
	# title_screen.gd (bug reportado antes: "exiting the game also causes
	# the same crash as creating a new file"). _activate_selected() (linha
	# de cima) pode ter trocado de cena SINCRONAMENTE (Load ou Delete, os
	# dois únicos ramos possíveis), o que já tira este nó da árvore antes
	# desta linha rodar — get_viewport() vira null nesse caso.
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

func _activate_selected() -> void:
	match option_labels[selected_index].name:
		"LoadSave":
			_load_save()
		"DeleteSave":
			_delete_save()

# Mesma checagem defensiva de save_slot_screen.gd::_activate_selected_slot
# (bug já visto lá: "Game crashed" ao dar Load num save com dependência
# quebrada) — GameState.current_save_slot deveria SEMPRE apontar pra um
# save válido neste ponto (toda partida de Challenge nasce de
# start_new_game(), que já salva na hora), mas o guard custa barato e evita
# a mesma classe de crash caso isso mude no futuro.
func _load_save() -> void:
	if not GameState.load_game(GameState.current_save_slot):
		_show_message("This save can't be loaded — its data is missing.")
		return
	get_tree().change_scene_to_file(GameState.overworld_scene_path)

func _delete_save() -> void:
	GameState.delete_save(GameState.current_save_slot)
	get_tree().change_scene_to_file(TITLE_SCREEN_PATH)

func _show_message(text: String) -> void:
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(text)
