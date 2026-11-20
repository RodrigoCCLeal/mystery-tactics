class_name MapLocation
extends Resource

# Um lugar do mapa de Tactica (ver data/map/locations/*.tres e
# TacticaMapData). Gerado lendo a imagem do mapa (2026-11-19): cada
# quadradinho do desenho é uma "célula" de 31x31 px, e cada lugar sabe
# quais células ocupa — é isso que o Town Map usa pra saber o que está
# embaixo do mouse e o que pintar de cinza.

# Cidades e vilarejos são "cidades-menu": não são mapas andáveis, estar
# neles é escolher uma opção num menu (ver is_menu_town). Só pontos
# especiais e rotas têm mapa de verdade (pedido do usuário, 2026-11-20).
enum Kind {
	CITY,     # quadrado vermelho — cidade-menu
	VILLAGE,  # quadrado azul — cidade-menu (menor: sem Pokémon Center/Mart por padrão)
	SPECIAL,  # quadrado verde — mapa andável
	ROUTE,    # caminho amarelo — mapa andável
}

# Identificador único, usado em save, neighbors, Door.town_map_location_id...
@export var id: String = ""
# Nome mostrado no balão. "" = "???" mesmo depois de visitado (pontos
# especiais que ainda não têm nome).
@export var display_name: String = ""
@export var kind: Kind = Kind.ROUTE
# Células do mapa ocupadas por este lugar (coordenada de célula, não pixel).
@export var cells: Array[Vector2i] = []
# ids dos lugares ligados a este por um caminho. É por aqui que o jogador
# anda no Town Map: estando numa cidade, só dá pra clicar nos vizinhos.
@export var neighbors: Array[String] = []
# Kano (vilarejo inicial) começa visitado.
@export var starts_visited: bool = false

@export_group("Lugar andável (ponto especial/rota)")
# Cena do mapa andável. "" = ainda não existe (o Town Map avisa o jogador).
@export_file("*.tscn") var scene_path: String = ""
# Um ponto de chegada por vizinho (ver MapEntryPoint).
@export var entry_points: Array[MapEntryPoint] = []

@export_group("Cidade-menu (cidade/vilarejo)")
@export var has_pokemon_center: bool = true
# Só cidades grandes (quadrado 2x2) têm Poké Mart.
@export var has_poke_mart: bool = false
@export var options: Array[CityOption] = []

@export_group("Saída (cidade-menu)")
# Mesmo espírito de Door.required_flag/blocked_message (ver door.gd), só que
# pra SAIR desta cidade/vilarejo pelo Town Map (rota vizinha ou Fly). "" =
# sempre pode sair. Preenchido = só sai com GameState.get_flag(...) == true;
# senão o Town Map mostra exit_blocked_message e o jogador continua aqui.
# Ex: Kano usa "STARTER1_CHOSEN" — não dá pra sair sem escolher o starter
# (substitui a antiga trava do Oak em world.gd, que foi apagado).
@export var exit_required_flag: String = ""
@export_multiline var exit_blocked_message: String = ""

func can_leave() -> bool:
	return exit_required_flag == "" or GameState.get_flag(exit_required_flag)

func get_display_name(visited: bool) -> String:
	if not visited or display_name == "":
		return "???"
	return display_name

func is_city() -> bool:
	return kind == Kind.CITY

# Cidade OU vilarejo — os dois viram menu no Town Map.
func is_menu_town() -> bool:
	return kind == Kind.CITY or kind == Kind.VILLAGE

# Ponto de chegada vindo de from_id; cai pro ponto "" (padrão) se não
# houver um específico. null = nenhum configurado ainda.
func get_entry_from(from_id: String) -> MapEntryPoint:
	var fallback: MapEntryPoint = null
	for entry in entry_points:
		if entry == null:
			continue
		if entry.from_location_id == from_id:
			return entry
		if entry.from_location_id == "":
			fallback = entry
	return fallback

# Centro do lugar em coordenada de CÉLULA (ex: (6.5, 18.5) pra uma cidade
# 2x2 que começa em (6,18)) — o Town Map converte isso pra pixel na hora de
# desenhar o indicador do jogador.
func get_center_cell() -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for cell in cells:
		total += Vector2(cell) + Vector2(0.5, 0.5)
	return total / cells.size()
