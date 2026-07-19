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
#
# Antes de sortear, filtra fora todo grupo cujo EncounterGroup.min_badges
# ainda não foi atingido (GameState.badges.size() < min_badges) — regra do
# usuário: "algumas encontros são limitados por número de badges". Se essa
# filtragem deixar a lista VAZIA (ex: área mal configurada, com todo grupo
# trancado atrás de badge e o jogador ainda com zero), caímos de volta pra
# lista original SEM filtro em vez de devolver null — mesmo espírito
# defensivo de trainer.gd::get_active_team() (cai pro tier mais alto
# preenchido em vez de travar o jogo): é preferível um encontro "adiantado
# demais" a uma batalha selvagem com ZERO inimigos.
func pick_group() -> EncounterGroup:
	if groups.is_empty():
		return null

	var badge_count := GameState.badges.size()
	var eligible: Array[EncounterGroup] = groups.filter(func(g): return badge_count >= g.min_badges)
	if eligible.is_empty():
		eligible = groups

	var total_weight := 0.0
	for g in eligible:
		total_weight += g.weight

	if total_weight <= 0.0:
		return eligible.pick_random()  # pesos zerados/negativos por engano — fallback uniforme em vez de travar

	var roll := randf() * total_weight
	var cumulative := 0.0
	for g in eligible:
		cumulative += g.weight
		if roll < cumulative:
			return g

	return eligible[eligible.size() - 1]  # folga de ponto flutuante — devolve o último em vez de null
