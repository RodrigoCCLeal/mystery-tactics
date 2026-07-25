class_name EvolutionOption
extends Resource

# Uma OPÇÃO de evolução — UnitData.evolution_options é um Array destas, em
# vez de um evolves_into/evolve_min_level/evolve_requires_action únicos que
# existiam antes soltos em UnitData. Motivo da mudança: pedido do usuário
# "a unit might be able to evolve into different options. when able to
# evolve, show a selection screen with the evolution options" — uma espécie
# pode ter MAIS de uma opção de evolução ao mesmo tempo (ex: cada uma
# exigindo uma condição diferente), então não dá mais pra guardar só UM
# alvo por espécie.
#
# Os pré-requisitos são os MESMOS dois campos que já existiam soltos em
# UnitData, só que agora por OPÇÃO em vez de por espécie inteira — cada
# opção pode exigir nível, ação equipada, os dois, ou nenhum dos dois (0 /
# null = sem exigência, mesmo critério de antes). Ver party_screen.gd::
# _get_available_evolutions() pra como isso é checado, e _try_evolve() pra
# como o jogo decide entre evoluir direto (1 opção disponível) ou abrir a
# tela de escolha (2+ disponíveis ao mesmo tempo).

# Espécie que esta unidade vira ao escolher esta opção — a instância aqui é
# o MESMO Resource compartilhado de GameState.ALL_SPECIES (sem duplicate()
# nenhum, igual LearnsetEntry.action); party_screen.gd::_perform_evolution()
# é quem faz .duplicate() na hora de aplicar de verdade.
@export var target: UnitData = null

# Nível mínimo pra esta opção ficar disponível (0 = sem exigência de
# nível). Ex: Swinub -> Piloswine no nível 33.
@export var min_level: int = 0

# Ação que precisa estar EQUIPADA (UnitData.slots, não só no learnset) pra
# esta opção ficar disponível (null = sem exigência de ação). Ex: Piloswine
# só evolui pra Mamoswine se estiver carregando Ancient Power no loadout.
@export var requires_action: ActionData = null

# true = `requires_action` acima é CONSUMIDO (removido do loadout, vira null
# naquele slot) no instante em que a evolução acontece de verdade — false
# (padrão, comportamento de sempre) = a ação continua equipada depois de
# evoluir, igual Piloswine/Ancient Power. Pedido do usuário, Pikachu ->
# Raichu: "Thunder Stone in loadout, consumed when evolving" — diferente de
# Pichu -> Pikachu (Soothe Bell), que NÃO é consumido, mesmo os dois sendo
# "precisa carregar um item" (ver party_screen.gd::_perform_evolution).
@export var consumes_required_action: bool = false

# true = esta opção também exige que UnitData.has_dropped_below_critical_hp
# esteja true (ver comentário grande do campo lá) — Primeape -> Annihilape é
# o primeiro caso, pedido do usuário: "having <5% HP left". Diferente de
# min_level/requires_action (checados só por número/loadout ATUAL), essa
# exigência é setada em COMBATE de verdade (Unit.take_damage()) e nunca é
# resetada sozinha depois — uma vez satisfeita, fica disponível pra sempre
# (confirmado com o usuário: checagem pós-batalha, não instantânea em
# batalha). false (padrão) = sem essa exigência, comportamento de sempre.
@export var requires_survived_critical_hp: bool = false
