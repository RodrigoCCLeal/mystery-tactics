class_name EncounterArea
extends Resource

# Tabela de encontros selvagens de UMA área do overworld: uma lista de
# EncounterGroup, cada um com seu peso relativo de aparecer. Uma cena do
# overworld (ex: test.gd) aponta pra UM EncounterArea via @export — se no
# futuro tivermos várias áreas, cada uma terá seu próprio arquivo aqui em
# data/areas/ e sua própria cena (ou sub-região dentro da mesma cena).

@export var area_name: String = ""
@export var groups: Array[EncounterGroup] = []

# Sorteia UM grupo pelos pesos relativos (não precisam somar 100, é
# normalizado pelo total abaixo). Devolve null só se groups estiver vazio
# (área sem encontro nenhum configurado).
func pick_group() -> EncounterGroup:
	if groups.is_empty():
		return null

	var total_weight := 0.0
	for g in groups:
		total_weight += g.weight

	if total_weight <= 0.0:
		return groups.pick_random()  # pesos zerados/negativos por engano — fallback uniforme em vez de travar

	var roll := randf() * total_weight
	var cumulative := 0.0
	for g in groups:
		cumulative += g.weight
		if roll < cumulative:
			return g

	return groups[groups.size() - 1]  # folga de ponto flutuante — devolve o último em vez de null
