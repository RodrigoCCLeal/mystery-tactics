extends CanvasLayer

# Popup pequeno que abre ao selecionar um slot preenchido na tela de Party
# (ver party_screen.gd::_open_slot_action_menu). Mesmo padrão de navegação
# de pause_menu.gd (setas + X confirma + Z cancela, mouse em paralelo) —
# só que aqui só existe UM sinal, "closed(option)", em vez de dois
# (option_chosen + closed) separados: emitir os dois causaria uma ordem de
# eventos ruim (quem escuta abriria a próxima tela ANTES desse popup acabar
# de se fechar, e o "closed" reverteria esse estado por engano logo depois).
# "" como option significa "cancelado" (Z), sem opção nenhuma escolhida.
#
# "Evolve" (ver slot_action_menu.tscn) começa OCULTO na cena — só aparece
# quando setup() recebe can_evolve=true (party_screen.gd já checou se há
# pelo menos UMA opção de evolução disponível antes de abrir isso, ver
# _get_available_evolutions()). Por isso a lista de opções não é mais um
# const fixo: é montada em runtime a partir de QUAIS Labels estão visible
# no momento (ver _build_option_list), pra "Evolve" oculto nem entrar na
# navegação por seta.

signal closed(option: String)

@onready var header_label: Label = $Center/Panel/MarginContainer/Options/Header
@onready var evolve_label: Label = $Center/Panel/MarginContainer/Options/Evolve
@onready var options_container: VBoxContainer = $Center/Panel/MarginContainer/Options

var option_labels: Array[Label] = []
var selected_index: int = 0

# can_evolve precisa ser aplicado ANTES de montar option_labels — mas
# setup() só roda DEPOIS de _ready() (add_child() dispara _ready() na hora;
# party_screen.gd só chama setup() depois que add_child() retorna). Por
# isso _build_option_list() foi tirado de _ready() e só roda aqui, no fim
# de setup(), quando evolve_label.visible já está com o valor certo.
func setup(unit_name: String, can_evolve: bool = false) -> void:
	header_label.text = unit_name.to_upper()
	evolve_label.visible = can_evolve
	_build_option_list()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _build_option_list() -> void:
	option_labels.clear()
	for child in options_container.get_children():
		if child is Label and child != header_label and child.visible:
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
		_confirm_selected()
	elif event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_finish("")
	else:
		return
	get_viewport().set_input_as_handled()

func _move_selection(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, option_labels.size())
	_update_selection_visual()

func _on_option_mouse_entered(index: int) -> void:
	selected_index = index
	_update_selection_visual()

func _on_option_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_index = index
		_confirm_selected()

func _confirm_selected() -> void:
	_finish(option_labels[selected_index].text)

func _finish(option: String) -> void:
	closed.emit(option)
	queue_free()

func _update_selection_visual() -> void:
	for i in option_labels.size():
		option_labels[i].modulate = Color.YELLOW if i == selected_index else Color.WHITE
