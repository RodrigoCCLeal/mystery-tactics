extends Control
class_name TimeOfDayIcon

# Ícone do HUD permanente (ver time_hud.gd) — desenhado em código (_draw(),
# sem nenhum arquivo de imagem) porque ainda não existe arte de verdade pra
# "meio-sol/sol/lua" no projeto; fácil de trocar por um AnimatedSprite2D/
# TextureRect depois, bastando apagar este script e apontar pra uma sprite
# sheet de verdade — o resto do HUD (time_hud.gd) só chama queue_redraw()
# quando o período muda, não sabe COMO o ícone é desenhado.
#
# Um círculo cheio de raio = metade do menor lado do Control pra cada
# período: Sol inteiro (Day), Lua inteira — cor diferente (Night), ou só a
# METADE direita do disco (Morning, "meio-sol" — pedido do usuário: "it only
# shows time of day with a half-sun, sun or moon").

const SUN_COLOR := Color(1.0, 0.85, 0.2)
const MOON_COLOR := Color(0.75, 0.8, 0.95)

func _draw() -> void:
	var radius = min(size.x, size.y) / 2.0
	var center = size / 2.0
	match GameState.get_time_of_day():
		"Day":
			draw_circle(center, radius, SUN_COLOR)
		"Night":
			draw_circle(center, radius, MOON_COLOR)
		_:
			_draw_half_circle(center, radius, SUN_COLOR)

# Desenha só a METADE direita de um disco de raio `radius` centrado em
# `center` — um polígono "fatia de pizza" de exatamente 180°: o centro do
# círculo + pontos ao longo do arco de -90° (topo) a 90° (base), passando
# por 0° (direita). draw_arc() do Godot só desenha o CONTORNO (uma linha),
# não a área preenchida — por isso o polígono manual em vez dela.
func _draw_half_circle(center: Vector2, radius: float, color: Color) -> void:
	const SEGMENTS := 24
	var points := PackedVector2Array()
	points.append(center)
	for i in range(SEGMENTS + 1):
		var angle = deg_to_rad(-90.0 + 180.0 * i / float(SEGMENTS))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
