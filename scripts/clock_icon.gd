extends Control

# Ícone de relógio desenhado em código (ainda não existe uma sprite de
# relógio no projeto). Usado no menu das cidades (town_map_screen.gd) pra
# marcar opções que avançam o tempo (CityOption.advances_time). Se um dia
# existir a sprite, dá pra trocar este node por um TextureRect.

@export var color: Color = Color.WHITE

func _ready() -> void:
	custom_minimum_size = Vector2(20, 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size / 2.0
	var radius: float = min(size.x, size.y) / 2.0 - 2.0
	draw_arc(center, radius, 0.0, TAU, 24, color, 2.0)
	draw_line(center, center + Vector2(0, -radius * 0.65), color, 2.0)   # ponteiro das horas
	draw_line(center, center + Vector2(radius * 0.5, 0), color, 2.0)     # ponteiro dos minutos
