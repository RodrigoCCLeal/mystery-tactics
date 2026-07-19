extends CanvasLayer

# Tela de Configurações — a MESMA cena serve tanto pro "Options" da tela de
# título (title_screen.gd) quanto pro "Configurações" do menu do jogo
# (system_menu.gd, aberto com Esc), sem precisar saber quem abriu: só mostra
# 2 ajustes reais (volume + tela cheia) e fecha com o mesmo padrão de
# `closed` signal de sempre.
#
# Só mouse + Z/Esc por enquanto (sem navegação por seta/X como os menus de
# lista) — Slider e CheckButton já respondem a clique/arrasto sozinhos, e
# adicionar navegação por teclado pra CADA control aqui exigiria tratar
# incremento/decremento de slider por seta, o que ainda não foi pedido;
# fácil de estender depois se fizer falta.

signal closed

@onready var volume_slider: HSlider = $Center/Panel/MarginContainer/Content/VolumeRow/VolumeSlider
@onready var fullscreen_check: CheckButton = $Center/Panel/MarginContainer/Content/FullscreenRow/FullscreenCheck
@onready var back_label: Label = $Center/Panel/MarginContainer/Content/Back

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var master_bus = AudioServer.get_bus_index("Master")
	# Volume real (dB, pode ser bem negativo ou -inf se mutado) convertido
	# pra uma escala 0-100 mais fácil de mostrar num slider comum.
	volume_slider.value = _db_to_slider_value(AudioServer.get_bus_volume_db(master_bus))
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_label.mouse_filter = Control.MOUSE_FILTER_STOP
	back_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_label.gui_input.connect(_on_back_gui_input)

# AudioServer trabalha em decibéis (escala logarítmica, 0 dB = volume
# "normal", negativos = mais baixo) — @export_range(0,100) num slider comum
# fica mais intuitivo que pedir pro jogador entender dB. linear_to_db()/
# db_to_linear() já existem como funções globais do Godot; só multiplicamos
# por 100 pra caber na escala do Slider.
func _db_to_slider_value(db: float) -> float:
	return clampf(db_to_linear(db) * 100.0, 0.0, 100.0)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()

func _on_volume_changed(value: float) -> void:
	var master_bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(value / 100.0))

func _on_fullscreen_toggled(pressed: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED)

func _on_back_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
