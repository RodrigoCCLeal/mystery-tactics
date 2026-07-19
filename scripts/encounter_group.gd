class_name EncounterGroup
extends Resource

# Um grupo FIXO de unidades selvagens que aparece junto na mesma batalha,
# cada uma com seu PRÓPRIO nível (ver encounter_entry.gd) — ex:
# <0473,54> + <0220,2> = sempre um Mamoswine nível 54 E um Swinub nível 2
# juntos, nunca só um dos dois. Repetir a mesma espécie (em entries
# diferentes) é o jeito de ter "N cópias dela nesse grupo" — battle.gd
# spawna exatamente entries.size() inimigos, um por entrada, na ordem em
# que estão aqui, cada um no nível daquela entrada específica.
#
# weight é um peso RELATIVO dentro da EncounterArea que contém este grupo,
# não precisa somar 100 entre os grupos — EncounterArea.pick_group()
# normaliza pelo total na hora de sortear (ver encounter_area.gd). Usamos
# porcentagens "redondas" (10/40/40/10) só porque ficou fácil de ler, não é
# uma exigência do sistema.

@export var entries: Array[EncounterEntry] = []
@export_range(0.0, 100.0) var weight: float = 1.0

# Trava de progressão: este grupo só pode ser sorteado se
# GameState.badges.size() >= min_badges — mesmo princípio de
# trainer.gd::teams (9 tiers indexados por número de badges), só que aqui é
# um LIMIAR (não um tier exato): 0 (padrão) = sempre disponível desde o
# início, 2 = só entra na roleta depois da 2ª badge. É assim que dá pra ter,
# por exemplo, uma espécie mais forte que só começa a aparecer numa rota já
# visitada antes, sem precisar de uma EncounterArea nova só pra isso. Ver
# EncounterArea.pick_group() pra onde isso é de fato checado.
@export var min_badges: int = 0
