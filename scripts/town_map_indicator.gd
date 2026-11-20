extends Control

# Indicador "você está aqui" do Town Map (ver town_map_screen.gd). O
# town_map_screen coloca este node exatamente no centro do lugar atual;
# daqui só desenhamos em volta do ponto (0,0).
#
# Enquanto a sprite de verdade não existe, desenha um marcador provisório
# (seta vermelha balançando + anel). Quando a sprite estiver pronta, é só
# arrastar ela pro campo `texture` no Inspector (node Indicator dentro de
# town_map_screen.tscn) — o placeholder some sozinho.

@export var texture: Texture2D
# Quanto (em pixels) a seta/sprite sobe e desce.
@export var bob_height: float = 3.0
@export var bob_speed: float = 4.0

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var bob := sin(_time * bob_speed) * bob_height
	if texture != null:
		var tex_size := texture.get_size()
		# Base da sprite encostada no ponto, centralizada na horizontal.
		draw_texture(texture, Vector2(-tex_size.x / 2.0, -tex_size.y + bob))
		return
	# Placeholder: anel pulsando no ponto + seta apontando pra baixo.
	var pulse := 0.5 + 0.5 * sin(_time * bob_speed)
	draw_arc(Vector2.ZERO, 9.0 + pulse * 3.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9 - pulse * 0.5), 2.0)
	var tip := Vector2(0, -10 + bob)
	var arrow := PackedVector2Array([tip, tip + Vector2(-8, -12), tip + Vector2(8, -12)])
	draw_colored_polygon(arrow, Color(0.9, 0.15, 0.15))
	draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), Color.WHITE, 2.0)
