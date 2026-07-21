extends Node

# Autoload (ver project.godot [autoload]) — configurações do jogador que
# precisam SOBREVIVER a fechar e abrir o jogo de novo: tela cheia, volume,
# e agora também o mapeamento de teclas (ver key_mapping_screen.gd).
# Antes disso, options_screen.gd mexia direto em DisplayServer/AudioServer
# sem gravar em disco nenhum lugar — funcionava DURANTE a sessão, mas
# "resetava" (tela cheia desligava, volume voltava a 100%) toda vez que o
# jogo era reaberto, o que na prática parecia "não funcionar" pro jogador.
# Pedido do usuário: "Make the fullscreen toggle work and add a Key Mapping
# feature. Will be important for controller support later".
#
# Persistido em user://settings.cfg via ConfigFile — mesma pasta gravável
# de sempre (ver comentário grande em SaveData sobre user:// vs res://),
# só que este arquivo é ÚNICO por instalação (não por save slot): tela
# cheia/volume/teclas são preferência da MÁQUINA, não do personagem.

const SETTINGS_PATH = "user://settings.cfg"

# Só as ações que o jogo de fato LÊ em algum _unhandled_input/_process (ver
# levantamento feito em todo scripts/*.gd) — "bike" existe em
# project.godot mas nunca é lida por nenhum Input.is_action_*, a Bicicleta
# liga/desliga pelo item Tool (ver GameState.use_tool), não por tecla
# direta; deixar ela de fora evita uma linha "morta" confusa na tela de
# Key Mapping.
#
# ui_up/down/left/right são ações EMBUTIDAS do Godot (não aparecem em
# project.godot [input], o motor já nasce com elas) — já vêm com bind de
# D-pad/analógico de fábrica ALÉM do teclado, o que significa que mover o
# personagem já funciona parcialmente com controle hoje. rebind_action()
# abaixo tira isso em conta: só mexe no evento de TECLADO de cada ação,
# nunca apaga o bind de joystick que já exista — é exatamente esse cuidado
# que deixa esta feature já "pronta" pro suporte a controle completo
# (remapear botão de joystick) chegar depois sem precisar desfazer nada
# daqui.
const REMAPPABLE_ACTIONS: Array[String] = [
	"ui_up", "ui_down", "ui_left", "ui_right",
	"confirm", "cancel", "menu", "game_menu",
	"run", "pass",
	"action_slot_1", "action_slot_2", "action_slot_3",
	"action_slot_4", "action_slot_5", "action_slot_6",
]

const ACTION_LABELS: Dictionary = {
	"ui_up": "Move Up",
	"ui_down": "Move Down",
	"ui_left": "Move Left",
	"ui_right": "Move Right",
	"confirm": "Confirm",
	"cancel": "Cancel",
	"menu": "System Menu",
	"game_menu": "Game Menu",
	"run": "Run",
	"pass": "Pass Turn",
	"action_slot_1": "Action Slot 1",
	"action_slot_2": "Action Slot 2",
	"action_slot_3": "Action Slot 3",
	"action_slot_4": "Action Slot 4",
	"action_slot_5": "Action Slot 5",
	"action_slot_6": "Action Slot 6",
}

var fullscreen: bool = false
# Mesma escala 0-100 que options_screen.gd::VolumeSlider já usava — guardado
# assim (não em dB) pra bater direto com o Slider sem converter duas vezes.
var master_volume: float = 100.0

# Bind de TECLADO original de cada ação (o que já vinha de project.godot,
# capturado ANTES de qualquer load_settings() aplicar um save antigo por
# cima) — usado só por reset_action_to_default()/reset_all_to_default().
var _default_key_events: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_defaults()
	load_settings()
	apply_settings()

func _capture_defaults() -> void:
	for action in REMAPPABLE_ACTIONS:
		var keys: Array = []
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				keys.append(e.duplicate())
		_default_key_events[action] = keys

func apply_settings() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	var master_bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(master_volume / 100.0))

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	# Confirmado com o usuário: "Embedded window only supports Windowed
	# mode" (aviso do próprio Godot) — quando o jogo roda dentro da janela
	# do EDITOR ("Embed Game", padrão desde a 4.3), DisplayServer.
	# window_set_mode(FULLSCREEN) é ignorado de propósito pelo motor, não é
	# bug daqui. Funciona normalmente rodando fora do editor (jogo
	# exportado) ou com Embed Game desligado (ícone de janela ao lado do
	# botão Play). Nada a mudar neste código.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
	save_settings()

func set_master_volume(value: float) -> void:
	master_volume = value
	var master_bus = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus, linear_to_db(value / 100.0))
	save_settings()

# Troca só o(s) evento(s) de TECLADO de `action` por `new_event` — ver
# comentário grande em REMAPPABLE_ACTIONS sobre por que não usar
# action_erase_events (apagaria TUDO, incluindo o bind de joystick padrão
# de ui_up/down/left/right).
func rebind_action(action: String, new_event: InputEventKey) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, new_event)
	save_settings()

func reset_action_to_default(action: String, persist: bool = true) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	for e in _default_key_events.get(action, []):
		InputMap.action_add_event(action, e.duplicate())
	if persist:
		save_settings()

func reset_all_to_default() -> void:
	for action in REMAPPABLE_ACTIONS:
		reset_action_to_default(action, false)
	save_settings()

# physical_keycode do primeiro InputEventKey de `action` (ignora eventos de
# joystick, ver comentário grande em REMAPPABLE_ACTIONS) — -1 no caso
# teórico de uma ação sem tecla nenhuma. Usado por get_action_key_label()
# logo abaixo E por key_mapping_screen.gd pra detectar/trocar duas ações
# que acabaram de ficar na MESMA tecla (ver _finish_rebind lá).
func get_action_physical_keycode(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e.physical_keycode
	return -1

# Nome pronto pra mostrar na UI ("A", "Space", "Escape"...) — "—" se a ação
# não tiver tecla nenhuma. OS.get_keycode_string() é independente de layout
# de teclado porque lemos physical_keycode (posição física), não keycode
# (que dependeria do layout ativo).
func get_action_key_label(action: String) -> String:
	var keycode = get_action_physical_keycode(action)
	return OS.get_keycode_string(keycode) if keycode != -1 else "—"

func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "master_volume", master_volume)
	for action in REMAPPABLE_ACTIONS:
		var keycodes: Array = []
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				keycodes.append(e.physical_keycode)
		cfg.set_value("keybinds", action, keycodes)
	var err = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("Falha ao salvar settings.cfg: erro %d" % err)

func load_settings() -> void:
	var cfg = ConfigFile.new()
	# Erro esperado (ERR_FILE_NOT_FOUND) na primeiríssima vez que o jogo
	# roda numa máquina — sem save nenhum ainda, fica tudo nos defaults
	# (fullscreen=false, master_volume=100, teclas de project.godot).
	if cfg.load(SETTINGS_PATH) != OK:
		return
	fullscreen = cfg.get_value("display", "fullscreen", false)
	master_volume = cfg.get_value("audio", "master_volume", 100.0)
	for action in REMAPPABLE_ACTIONS:
		var keycodes = cfg.get_value("keybinds", action, null)
		if keycodes == null:
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		for kc in keycodes:
			var ev = InputEventKey.new()
			ev.physical_keycode = kc
			InputMap.action_add_event(action, ev)
