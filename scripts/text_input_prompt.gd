extends CanvasLayer

# Popup genérico de entrada de texto — mesma ideia de yes_no_prompt.gd
# (reutilizável: quem abre passa a pergunta via setup() e escuta a resposta
# por sinal, em vez de ter um efeito fixo embutido aqui), só que devolve uma
# STRING digitada em vez de Sim/Não. Baseado em name_entry_screen.gd (mesma
# técnica de LineEdit consumindo teclas de texto ANTES de _unhandled_input
# sequer ver o evento, ver comentário grande lá sobre por que "confirm" não
# é checado em _unhandled_input), mas SEM o acoplamento com "New Game" —
# aqui só emite o texto (`submitted(text)`) ou avisa que foi cancelado
# (`cancelled`), quem chama decide o que fazer com a resposta.
#
# Primeiro uso: baldo.gd, pedindo a senha de Giovanni.
#
# Bottom-anchored ("Box", sem "Dim") igual yes_no_prompt.gd/
# trainer_message_box.gd — mesmo motivo: isto abre de dentro de uma
# conversa com NPC, não deve escurecer o mapa inteiro nem tampar a tela
# toda como name_entry_screen.gd (que é uma tela cheia própria, fora do
# overworld).

signal submitted(text: String)
signal cancelled

@onready var header_label: Label = $Box/Panel/MarginContainer/Content/Header
@onready var text_edit: LineEdit = $Box/Panel/MarginContainer/Content/TextEdit
@onready var confirm_label: Label = $Box/Panel/MarginContainer/Content/Confirm

func setup(prompt: String, placeholder: String = "") -> void:
	header_label.text = prompt
	text_edit.placeholder_text = placeholder

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	text_edit.text_submitted.connect(_on_text_submitted)
	confirm_label.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	confirm_label.gui_input.connect(_on_confirm_gui_input)
	text_edit.grab_focus()

# Mesmo motivo de name_entry_screen.gd: SEM checar "confirm" aqui — o
# LineEdit focado consome letras/números como texto antes de chegar até
# aqui. Enter (text_submitted) ou clicar em "Confirm" são os únicos jeitos
# de confirmar; "cancel"/"menu" (Z/Esc) continuam chegando normalmente
# porque não são caracteres imprimíveis que o LineEdit engula.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_cancel()
		var viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func _on_text_submitted(_text: String) -> void:
	_try_confirm()

func _on_confirm_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_confirm()

# Texto vazio (só espaço, ou nada digitado) não confirma — mesmo cuidado de
# name_entry_screen.gd::_try_confirm, senão quem escuta `submitted` recebia
# uma string em branco pra comparar contra a senha certa.
func _try_confirm() -> void:
	var text = text_edit.text.strip_edges()
	if text.is_empty():
		return
	submitted.emit(text)
	queue_free()

func _cancel() -> void:
	cancelled.emit()
	queue_free()
