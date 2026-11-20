class_name CityOption
extends Resource

# Uma linha do menu de uma cidade vermelha (ver MapLocation.options e
# town_map_screen.gd). Cidades vermelhas não são mapas andáveis: "estar"
# numa cidade é escolher uma destas opções.
#
# Pokémon Center e Poké Mart NÃO entram aqui — toda cidade tem os dois
# (Poké Mart só nas grandes), e os dois são mapas únicos compartilhados por
# todas as cidades. Por isso eles vêm de MapLocation.has_pokemon_center/
# has_poke_mart + TacticaMapData (cena única), não de uma CityOption repetida
# em 11 arquivos.
#
# Ordem do que acontece ao escolher a opção (ver
# town_map_screen.gd::_run_city_option):
#   1. advances_time -> tela escurece e o tempo pula pro próximo período
#      (igual à cama, ver bed.gd), SEM curar o time;
#   2. message (se tiver) aparece numa caixa de texto;
#   3. action == ENTER_SCENE -> troca pra scene_path.

enum Action {
	ENTER_SCENE,   # entra num mapa (casa, ginásio, loja especial...)
	MESSAGE_ONLY,  # só mostra a mensagem / passa o tempo, fica na cidade
}

@export var label: String = ""
@export var action: Action = Action.ENTER_SCENE

@export_group("Entrar num mapa (action = ENTER_SCENE)")
@export_file("*.tscn") var scene_path: String = ""
@export var grid_pos: Vector2i = Vector2i.ZERO
@export_enum("down", "left", "right", "up") var facing: String = "up"

@export_group("Efeitos")
@export_multiline var message: String = ""
# Mostra o ícone de RELÓGIO: escolher esta opção avança o tempo pro
# próximo período do dia (Manhã -> Dia -> Noite -> Manhã).
@export var advances_time: bool = false

@export_group("Novidade (ícone de exclamação)")
# Mostra o ícone de EXCLAMAÇÃO até o jogador usar a opção pela primeira vez.
@export var is_news: bool = false
# Flag que guarda "já vi esta novidade". "" = gerada sozinha a partir da
# cidade + label (ver get_news_flag) — só preencha se quiser controlar a
# flag por fora (ex: reacender a novidade num evento).
@export var news_flag: String = ""

@export_group("Quando aparece")
# "" = sempre. Preenchido = só aparece se GameState.get_flag(...) for true.
@export var required_flag: String = ""
# Períodos do dia em que a opção aparece (eventos de tempo limitado).
# Nenhum marcado (0) = qualquer hora. Os bits batem com
# GameState.TIME_BIT_MORNING/DAY/NIGHT (1/2/4).
@export_flags("Morning", "Day", "Night") var available_times: int = 0

func get_news_flag(city_id: String) -> String:
	if news_flag != "":
		return news_flag
	return "news_seen:%s:%s" % [city_id, label]

func is_available() -> bool:
	if required_flag != "" and not GameState.get_flag(required_flag):
		return false
	if available_times != 0 and (available_times & GameState.get_time_of_day_bit()) == 0:
		return false
	return true

func shows_news(city_id: String) -> bool:
	return is_news and not GameState.get_flag(get_news_flag(city_id))
