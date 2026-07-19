extends CanvasLayer

# Tela de escolha de evolução — só abre quando uma unidade tem MAIS DE UMA
# UnitData.EvolutionOption disponível ao MESMO TEMPO (ver party_screen.gd::
# _try_evolve). Com uma opção só disponível, a evolução acontece direto,
# sem passar por aqui — pedido do usuário: "when able to evolve, show a
# selection screen with the evolution options" (implica que a tela só
# precisa existir quando há de fato uma ESCOLHA a fazer).
#
# Mesmo padrão de navegação/seleção de slot_action_menu.gd (setas + X
# confirma + Z cancela, mouse em paralelo) — a diferença é que a lista de
# opções é MONTADA EM RUNTIME (um Label por opção recebida em setup()), já
# que o número de opções varia por espécie, diferente do menu fixo de
# slot_action_menu.tscn (sempre as mesmas 4 entradas, só visibilidade
# muda).

signal closed(chosen_index: int)

@onready var header_label: Label = $Center/Panel/MarginContainer/Options/Header
@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
var selected_index: int = 0

# `names`: um texto por opção, na MESMA ordem do Array[EvolutionOption] que
# party_screen.gd já tem em mãos (ver _open_evolution_choice) — o índice
# escolhido (emitido em `closed`) é só a posição dentro dessa lista, quem
# chamou é responsável por mapear de volta pra EvolutionOption/UnitData.
func setup(unit_name: String, names: Array[String]) -> void:
	header_label.text = "%s: EVOLVE INTO?" % unit_name.to_upper()
	for option_name in names:
		var label = Label.new()
		label.text = option_name
		options_container.add_child(label)
		option_labels.append(label)
	_wire_options()
	_update_selection_visual()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _wire_options() -> void:
	for i in option_labels.size():
		var label := option_labels[i]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		label.mouse_entered.connect(_on_option_mouse_entered.bind(i))
		label.gui_input.connect(_on_option_gui_input.bind(i))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_move_selection(1)
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
	elif event.is_action_pressed("confirm"):
		_finish(selected_index)
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		# Cancelar não evolui pra NENHUMA opção — -1 é o sentinela que
		# party_screen.gd::_on_evolution_choice_closed() reconhece como
		# "desistiu, não faça nada" (mesmo espírito de slot_action_menu.gd
		# usar "" como "cancelado").
		_finish(-1)
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
		_finish(index)

func _finish(chosen_index: int) -> void:
	closed.emit(chosen_index)
	queue_free()

func _update_selection_visual() -> void:
	for i in option_labels.size():
		option_labels[i].modulate = Color.YELLOW if i == selected_index else Color.WHITE
