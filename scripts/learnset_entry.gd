class_name LearnsetEntry
extends Resource

# Um par (nível, ação) dentro de UnitData.learnset — "essa espécie aprende
# essa ação a partir desse nível". O nível de aprendizado é uma relação entre
# a ESPÉCIE e a ação (a mesma AttackData pode ser aprendida no nível 1 por uma
# espécie e no nível 20 por outra), então não faz sentido morar dentro de
# ActionData — fica aqui, num par dedicado.
#
# UnitData.slots (o loadout equipado, até 6) deve ser escolhido dentre as
# ações cujo level aqui é <= o nível atual da unidade — ver
# UnitData.get_available_actions().

@export var level: int = 1
@export var action: ActionData
