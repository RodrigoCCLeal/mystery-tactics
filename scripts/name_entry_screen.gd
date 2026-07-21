extends CanvasLayer

# Escolha do nome do jogador — último passo de "New Game" antes de entrar no
# overworld pra valer (ver save_slot_screen.gd::_open_name_entry). Confirmar
# aqui chama GameState.start_new_game(), que já reseta TUDO pro estado de
# jogo novo (ver comentário grande naquela função) e grava o primeiro save
# do slot na hora.
#
# Navegação DIFERENTE do resto do projeto de propósito: um LineEdit com foco
# consome toda tecla "de texto" (letras, números) sozinho, ANTES de
# _unhandled_input sequer ver o evento — então "X" (confirm) e "Z" (cancel)
# aqui são só LETRAS DE VERDADE que o jogador pode querer digitar no nome,
# não atalhos de menu. Por isso: SEM checar "confirm" aqui (usar Enter,
# InputEventKey que o LineEdit NÃO consome como texto e emite via
# text_submitted, ou clicar em "Confirm"); "cancel"/"menu" (Z/Esc) também só
# funcionam pra FECHAR porque o LineEdit não consome Esc como texto (Esc não
# é um caractere imprimível), então ainda chega normalmente em
# _unhandled_input.

signal closed

const MAX_NAME_LENGTH = 12
const MODE_SELECT_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/mode_select_screen.tscn")

@onready var name_edit: LineEdit = $Center/Panel/MarginContainer/Content/NameEdit
@onready var confirm_label: Label = $Center/Panel/MarginContainer/Content/Confirm

var target_slot: int = -1

func setup(slot: int) -> void:
	target_slot = slot

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name_edit.max_length = MAX_NAME_LENGTH
	name_edit.text_submitted.connect(_on_name_submitted)
	confirm_label.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	confirm_label.gui_input.connect(_on_confirm_gui_input)
	name_edit.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()

func _on_name_submitted(_text: String) -> void:
	_try_confirm()

func _on_confirm_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_confirm()

# Nome vazio (só espaço, ou nada digitado) não confirma — precisa de ao
# menos 1 caractere de verdade, senão o slot/menu mostrariam um nome em
# branco pra sempre.
#
# Não cria mais o save diretamente — falta escolher o modo (ver
# mode_select_screen.gd/GameState.game_mode). Mesmo padrão de
# save_slot_screen.gd::_open_name_entry (hide() + add_child + closed.connect
# (show)): se o jogador voltar (Esc) da tela de modo, reaparece aqui com o
# nome já digitado, em vez de ter que digitar de novo.
func _try_confirm() -> void:
	var chosen = name_edit.text.strip_edges()
	if chosen.is_empty():
		return
	hide()
	var screen = MODE_SELECT_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.setup(target_slot, chosen)
	screen.closed.connect(show)

func _close() -> void:
	closed.emit()
	queue_free()
