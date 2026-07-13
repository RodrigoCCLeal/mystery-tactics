extends CanvasLayer

# Aviso de "você entrou em [nome da área]" no overworld — CanvasLayer (igual
# pause_menu.gd) pra desenhar em espaço de TELA, ignorando a Camera2D do
# Player, e ficar sempre no mesmo lugar da tela independente de onde o
# personagem estiver no mapa.
#
# test.gd é quem decide QUANDO chamar show_area() (só quando a área
# realmente muda, ver test.gd::_enter_area) — este script só sabe mostrar
# o texto e sumir sozinho depois de 1 segundo, não sabe nada sobre áreas.

@onready var label: Label = $Label

var _tween: Tween = null

func _ready() -> void:
	label.visible = false

func show_area(area_name: String) -> void:
	label.text = area_name
	label.visible = true
	label.modulate.a = 1.0

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(1.0)
	_tween.tween_callback(func(): label.visible = false)
