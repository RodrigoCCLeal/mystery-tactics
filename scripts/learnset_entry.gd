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

# Só faz sentido quando action é AbilityData (ver comentário grande em
# AbilityData sobre Habilidade ser passiva) — marca essa Habilidade como
# "Hidden" (oculta) PRA ESSA ESPÉCIE especificamente, não pra Habilidade em
# si. É por isso que mora aqui (no par espécie+ação) e não em AbilityData:
# a MESMA Habilidade pode ser normal numa espécie e Hidden em outra — ex:
# Sheer Force é Hidden no Totodile (0158.tres) hoje, mas nada impede uma
# espécie futura ter Sheer Force como Habilidade normal (is_hidden_ability
# = false, o padrão). Ver UnitData.is_ability_hidden(), que consulta isso.
@export var is_hidden_ability: bool = false
