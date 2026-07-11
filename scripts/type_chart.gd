class_name TypeChart
extends RefCounted

# Utilitário estático (nunca instanciado — igual ExpGroups) com a tabela de
# efetividade de tipo padrão dos jogos (Geração 6 em diante — a mesma usada
# desde Pokémon X/Y, inclui o tipo Fairy). Fonte: pokemondb.net/type.
#
# Só lista as combinações que NÃO são neutras (x1) — qualquer combinação
# ausente do dicionário do tipo atacante vale 1.0 (dano normal). É o mesmo
# truque de "só guardar as exceções" que já usamos no FLUID_DETAIL/wall_detail
# do battle.gd.
const CHART = {
	"Normal": {"Rock": 0.5, "Ghost": 0.0, "Steel": 0.5},
	"Fire": {"Fire": 0.5, "Water": 0.5, "Grass": 2.0, "Ice": 2.0, "Bug": 2.0, "Rock": 0.5, "Dragon": 0.5, "Steel": 2.0},
	"Water": {"Fire": 2.0, "Water": 0.5, "Grass": 0.5, "Ground": 2.0, "Rock": 2.0, "Dragon": 0.5},
	"Electric": {"Water": 2.0, "Electric": 0.5, "Grass": 0.5, "Ground": 0.0, "Flying": 2.0, "Dragon": 0.5},
	"Grass": {"Fire": 0.5, "Water": 2.0, "Grass": 0.5, "Poison": 0.5, "Ground": 2.0, "Flying": 0.5, "Bug": 0.5, "Rock": 2.0, "Dragon": 0.5, "Steel": 0.5},
	"Ice": {"Fire": 0.5, "Water": 0.5, "Grass": 2.0, "Ice": 0.5, "Ground": 2.0, "Flying": 2.0, "Dragon": 2.0, "Steel": 0.5},
	"Fighting": {"Normal": 2.0, "Ice": 2.0, "Poison": 0.5, "Flying": 0.5, "Psychic": 0.5, "Bug": 0.5, "Rock": 2.0, "Ghost": 0.0, "Dark": 2.0, "Steel": 2.0, "Fairy": 0.5},
	"Poison": {"Grass": 2.0, "Poison": 0.5, "Ground": 0.5, "Rock": 0.5, "Ghost": 0.5, "Steel": 0.0, "Fairy": 2.0},
	"Ground": {"Fire": 2.0, "Electric": 2.0, "Grass": 0.5, "Poison": 2.0, "Flying": 0.0, "Bug": 0.5, "Rock": 2.0, "Steel": 2.0},
	"Flying": {"Electric": 0.5, "Grass": 2.0, "Fighting": 2.0, "Bug": 2.0, "Rock": 0.5, "Steel": 0.5},
	"Psychic": {"Fighting": 2.0, "Poison": 2.0, "Psychic": 0.5, "Dark": 0.0, "Steel": 0.5},
	"Bug": {"Fire": 0.5, "Grass": 2.0, "Fighting": 0.5, "Poison": 0.5, "Flying": 0.5, "Psychic": 2.0, "Ghost": 0.5, "Dark": 2.0, "Steel": 0.5, "Fairy": 0.5},
	"Rock": {"Fire": 2.0, "Ice": 2.0, "Fighting": 0.5, "Ground": 0.5, "Flying": 2.0, "Bug": 2.0, "Steel": 0.5},
	"Ghost": {"Normal": 0.0, "Psychic": 2.0, "Ghost": 2.0, "Dark": 0.5},
	"Dragon": {"Dragon": 2.0, "Steel": 0.5, "Fairy": 0.0},
	"Dark": {"Fighting": 0.5, "Psychic": 2.0, "Ghost": 2.0, "Dark": 0.5, "Fairy": 0.5},
	"Steel": {"Fire": 0.5, "Water": 0.5, "Electric": 0.5, "Ice": 2.0, "Rock": 2.0, "Steel": 0.5, "Fairy": 2.0},
	"Fairy": {"Fire": 0.5, "Fighting": 2.0, "Poison": 0.5, "Dragon": 2.0, "Dark": 2.0, "Steel": 0.5},
}

# Multiplicador de UM tipo atacante contra UM tipo defensor. 1.0 (neutro) se
# a combinação não estiver na tabela (incluindo tipo desconhecido/vazio).
static func get_multiplier(attacking_type: String, defending_type: String) -> float:
	var row: Dictionary = CHART.get(attacking_type, {})
	return row.get(defending_type, 1.0)

# Efetividade total contra uma unidade que pode ter 1 ou 2 tipos — multiplica
# o matchup de cada tipo defensor, igual o jogo original (é assim que surgem
# os x0.25 e x4: dois tipos fracos/fortes ao mesmo do mesmo jeito se somam).
static func get_effectiveness(attacking_type: String, defending_types: Array) -> float:
	var multiplier = 1.0
	for defending_type in defending_types:
		multiplier *= get_multiplier(attacking_type, defending_type)
	return multiplier
