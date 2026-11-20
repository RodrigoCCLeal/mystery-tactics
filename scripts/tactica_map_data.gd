class_name TacticaMapData
extends Resource

# O mapa da região inteira (ver data/map/tactica_map.tres): a imagem, a
# grade de células por cima dela e a lista de todos os lugares.

@export var texture: Texture2D
# Tamanho de UMA célula na imagem, em pixels.
@export var cell_size: int = 31
# Onde a célula (0,0) começa dentro da imagem (a imagem tem 1px de borda).
@export var grid_origin: Vector2 = Vector2(1, 1)
# Quantas células a grade tem (colunas, linhas).
@export var grid_size: Vector2i = Vector2i(30, 25)
@export var locations: Array[MapLocation] = []

@export_group("Pokémon Center e Poké Mart (mapas únicos)")
# Todas as cidades usam o MESMO mapa de Pokémon Center (e de Poké Mart). A
# cidade de onde o jogador entrou fica guardada em
# GameState.current_location_id — a porta de saída desses mapas usa
# Door.opens_town_map com town_map_location_id vazio, que reabre o mapa
# justamente nessa cidade.
@export_file("*.tscn") var pokemon_center_scene: String = "res://scenes/overworld/pokemon_center_interior.tscn"
@export var pokemon_center_entry: Vector2i = Vector2i.ZERO
@export_enum("down", "left", "right", "up") var pokemon_center_facing: String = "up"
@export_file("*.tscn") var poke_mart_scene: String = "res://scenes/overworld/poke_mart_interior.tscn"
@export var poke_mart_entry: Vector2i = Vector2i.ZERO
@export_enum("down", "left", "right", "up") var poke_mart_facing: String = "up"

# Montado na primeira consulta: célula -> MapLocation, e id -> MapLocation.
var _by_cell: Dictionary = {}
var _by_id: Dictionary = {}

func _build_lookup() -> void:
	if not _by_id.is_empty():
		return
	for loc in locations:
		if loc == null:
			continue
		_by_id[loc.id] = loc
		for cell in loc.cells:
			_by_cell[cell] = loc

func get_location(id: String) -> MapLocation:
	_build_lookup()
	return _by_id.get(id, null)

func get_location_at_cell(cell: Vector2i) -> MapLocation:
	_build_lookup()
	return _by_cell.get(cell, null)

# Pixel da imagem -> célula da grade.
func pixel_to_cell(pixel: Vector2) -> Vector2i:
	var p := (pixel - grid_origin) / float(cell_size)
	return Vector2i(floori(p.x), floori(p.y))

# Célula (pode ser fracionária, ex: centro de uma cidade 2x2) -> pixel.
func cell_to_pixel(cell: Vector2) -> Vector2:
	return grid_origin + cell * cell_size
