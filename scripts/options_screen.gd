extends CanvasLayer

# Tela de Configurações — a MESMA cena serve tanto pro "Options" da tela de
# título (title_screen.gd) quanto pro "Configurações" do menu do jogo
# (system_menu.gd, aberto com Esc), sem precisar saber quem abriu: mostra
# volume, tela cheia e agora também o atalho pra Key Mapping (ver
# key_mapping_screen.gd), fecha com o mesmo padrão de `closed` signal de
# sempre.
#
# Volume/tela cheia agora passam pelo autoload Settings (ver scripts/
# settings.gd) em vez de mexer direto em AudioServer/DisplayServer — pedido
# do usuário: "Make the fullscreen toggle work" (o toggle já MUDAVA a janela
# na hora, mas nada gravava a escolha em disco: fechar e abrir o jogo de
# novo sempre voltava pra janela normal e 100% de volume, o que na prática
# parecia "não funcionar"). Settings.set_fullscreen/set_master_volume já
# aplicam E gravam sozinhos.
#
# Só mouse + Z/Esc por enquanto (sem navegação por seta/X como os menus de
# lista) — Slider e CheckButton já respondem a clique/arrasto sozinhos, e
# adicionar navegação por teclado pra CADA control aqui exigiria tratar
# incremento/decremento de slider por seta, o que ainda não foi pedido;
# fácil de estender depois se fizer falta. O novo botão de Key Mapping é só
# mais um Label clicável, mesmo padrão do resto do menu.

signal closed

const KEY_MAPPING_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/key_mapping_screen.tscn")

@onready var volume_slider: HSlider = $Center/Panel/MarginContainer/Content/VolumeRow/VolumeSlider
@onready var fullscreen_check: CheckButton = $Center/Panel/MarginContainer/Content/FullscreenRow/FullscreenCheck
@onready var key_mapping_label: Label = $Center/Panel/MarginContainer/Content/KeyMapping
@onready var back_label: Label = $Center/Panel/MarginContainer/Content/Back

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Lido de Settings (não mais AudioServer/DisplayServer direto) — é o
	# valor que sobrevive entre sessões, então é ele que reflete o que o
	# jogador escolheu de verdade.
	volume_slider.value = Settings.master_volume
	fullscreen_check.button_pressed = Settings.fullscreen
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	key_mapping_label.mouse_filter = Control.MOUSE_FILTER_STOP
	key_mapping_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	key_mapping_label.gui_input.connect(_on_key_mapping_gui_input)
	back_label.mouse_filter = Control.MOUSE_FILTER_STOP
	back_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_label.gui_input.connect(_on_back_gui_input)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()

func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)

func _on_fullscreen_toggled(pressed: bool) -> void:
	Settings.set_fullscreen(pressed)

func _on_key_mapping_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_key_mapping()

func _open_key_mapping() -> void:
	hide()
	var screen = KEY_MAPPING_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(show)

func _on_back_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
