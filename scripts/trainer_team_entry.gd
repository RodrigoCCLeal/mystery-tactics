class_name TrainerTeamEntry
extends Resource

# UMA unidade dentro de um TrainerTeam (ver trainer_team.gd) — mesmo
# espírito de EncounterEntry (ver encounter_entry.gd): espécie + nível,
# editável como elemento de array no Inspector.
#
# loadout é a diferença pro EncounterEntry: regra 3 do usuário — "se o
# loadout não for especificado, use as mesmas regras de unidades selvagens
# (as últimas 6 aprendidas)". Vazio (padrão) é exatamente esse caso: Unit.
# apply_fresh_data() cai pra fresh_data.get_recent_loadout(level) sozinho
# quando forced_loadout vem vazio (ver comentário lá). Só preencha loadout
# aqui quando um Trainer precisar de um time com golpes específicos,
# diferentes do que a espécie "aprenderia sozinha" até aquele nível.
@export var species: UnitData
@export var level: int = 1
@export var loadout: Array[ActionData] = []
