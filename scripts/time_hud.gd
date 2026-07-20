extends CanvasLayer

# HUD permanente no canto superior esquerdo — pedido do usuário: "we will
# add a hud on the top left corner of the screen at all times... it only
# shows time of day with a half-sun, sun or moon and the location where the
# player is (like the labels we were showing)". Diferente de
# area_notification.gd (aparece, espera 1s, some sozinho), este NUNCA some —
# fica sempre visível, lido/atualizado a cada frame direto de GameState
# (não precisa que world.gd chamem nada explicitamente, diferente
# de area_notification.show_area()).
#
# CanvasLayer (não Node2D) pelo mesmo motivo de area_notification.gd —
# desenha em espaço de TELA, ignorando a Camera2D do Player, sempre no
# mesmo canto não importa onde o personagem esteja no mapa.
#
# Ícone só troca de desenho quando o PERÍODO muda de verdade (ver
# _last_time_of_day) — chamar queue_redraw() todo frame seria desperdício,
# já que o desenho é sempre o mesmo enquanto o período não muda.
#
# Layout em duas linhas — pedido do usuário: "The HUD should be:
# Half-Sun/Sun/Moon - Hour:Minute / Location [two lines]". Linha 1 (HBox):
# ícone + "HH:MM". Linha 2 (embaixo, fora do HBox): nome da área.

@onready var icon: TimeOfDayIcon = $Panel/MarginContainer/VBox/HBox/Icon
@onready var time_label: Label = $Panel/MarginContainer/VBox/HBox/Time
@onready var location_label: Label = $Panel/MarginContainer/VBox/Location

var _last_time_of_day: String = ""

func _process(_delta: float) -> void:
	var current_time = GameState.get_time_of_day()
	if current_time != _last_time_of_day:
		_last_time_of_day = current_time
		icon.queue_redraw()

	time_label.text = "%02d:%02d" % [GameState.get_hour(), GameState.get_minute()]

	var area = GameState.current_area
	location_label.text = area.area_name if area != null else ""
