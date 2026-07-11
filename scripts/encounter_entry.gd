class_name EncounterEntry
extends Resource

# UMA unidade dentro de um EncounterGroup: qual espécie E em qual nível ela
# aparece (ex: <0473, 54> = Mamoswine nível 54). Isso é o que faltava em
# EncounterGroup.species antes — todo inimigo selvagem nascia no mesmo
# GameState.STARTING_LEVEL fixo, sem jeito de um grupo ter, por exemplo, um
# Mamoswine forte (nível alto) ao lado de um Swinub fraco (nível baixo) na
# MESMA batalha, como <0473,54> + <0220,2> pede.

@export var species: UnitData
@export var level: int = 1
