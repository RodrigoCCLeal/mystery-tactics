class_name TrainerTeam
extends Resource

# UM dos 9 times de um Trainer (ver trainer.gd::teams, índice = número de
# badges do jogador — regra 3 do usuário). Só existe pra poder ter um
# Array[Array[...]] via Inspector (Godot não deixa exportar array de array
# direto) — mesmo motivo de EncounterGroup existir ao lado de EncounterEntry
# (ver encounter_group.gd), só que aqui SEM peso/sorteio nenhum: o índice do
# tier é FIXO pelo número de badges, não sorteado.
@export var entries: Array[TrainerTeamEntry] = []
