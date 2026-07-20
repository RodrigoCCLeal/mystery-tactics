class_name EncounterArea
extends Resource

# Tabela de encontros selvagens de UMA área do overworld: uma lista de
# EncounterGroup, cada um com seu peso relativo de aparecer. Uma cena do
# overworld (ex: world.gd) aponta pra UM EncounterArea via @export — se no
# futuro tivermos várias áreas, cada uma terá seu próprio arquivo aqui em
# data/areas/ e sua própria cena (ou sub-região dentro da mesma cena).

@export var area_name: String = ""
@export var groups: Array[EncounterGroup] = []

# Sorteia UM grupo pelos pesos relativos (não precisam somar 100, é
# normalizado pelo total abaixo — regra do usuário: "encounter weight / sum
# of all POSSIBLE weights"). Devolve null se groups estiver vazio (área sem
# encontro nenhum configurado) OU se nenhum grupo bater com `source`.
#
# `source` ("Grass"/"Water"/"Fishing", ver EncounterGroup.source) é um
# filtro RÍGIDO, aplicado ANTES de qualquer coisa — diferente das duas
# filtragens seguintes, NÃO cai pro conjunto mais amplo se ficar vazio
# (surfando na água, "não existe grupo Water configurado ainda" tem que
# significar "sem encontro", nunca "sorteia um Grass por engano").
#
# DEPOIS do filtro de source, duas filtragens em sequência, cada uma com o
# MESMO fallback defensivo (mesmo espírito de trainer.gd::get_active_team()
# — cai pro conjunto mais amplo em vez de travar o jogo com ZERO grupos
# elegíveis):
#   1. EncounterGroup.min_badges ainda não atingido (GameState.badges.size()
#      < min_badges) — regra do usuário: "algumas encontros são limitados
#      por número de badges".
#   2. EncounterGroup.times_of_day não inclui o período ATUAL (ver
#      GameState.get_time_of_day_bit) — regra do usuário: "an encounter may
#      be exclusive to 1 or 2 times of day".
# A segunda filtragem roda EM CIMA do resultado da primeira (não do zero),
# então um grupo só entra na roleta final se passar nas DUAS ao mesmo
# tempo — badge insuficiente OU período errado, qualquer um dos dois já
# tira o grupo da vez.
func pick_group(source: String = "Grass") -> EncounterGroup:
	if groups.is_empty():
		return null

	var of_source: Array[EncounterGroup] = groups.filter(func(g): return g.source == source)
	if of_source.is_empty():
		return null

	var badge_count := GameState.badges.size()
	var eligible: Array[EncounterGroup] = of_source.filter(func(g): return badge_count >= g.min_badges)
	if eligible.is_empty():
		eligible = of_source

	var time_bit := GameState.get_time_of_day_bit()
	var time_eligible: Array[EncounterGroup] = eligible.filter(func(g): return (g.times_of_day & time_bit) != 0)
	if time_eligible.is_empty():
		time_eligible = eligible

	var total_weight := 0.0
	for g in time_eligible:
		total_weight += g.weight

	if total_weight <= 0.0:
		return time_eligible.pick_random()  # pesos zerados/negativos por engano — fallback uniforme em vez de travar

	var roll := randf() * total_weight
	var cumulative := 0.0
	for g in time_eligible:
		cumulative += g.weight
		if roll < cumulative:
			return g

	return time_eligible[time_eligible.size() - 1]  # folga de ponto flutuante — devolve o último em vez de null

# Pergunta rápida (sem sortear nada) — "existe ALGUM grupo desse source
# nesta área?" Usada por world.gd antes de sequer tentar disparar um
# encontro de água (steps_until_water_encounter chegando a 0 numa área sem
# NENHUM grupo "Water" configurado não devia abrir uma batalha vazia).
func has_source(source: String) -> bool:
	return groups.any(func(g): return g.source == source)
