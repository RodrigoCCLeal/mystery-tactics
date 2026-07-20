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

# De ONDE esse grupo pode ser sorteado — pedido do usuário: "We can add a
# tag to the encounter table, being 'Grass' or 'Water' or 'Fishing'". Ao
# contrário de min_badges/times_of_day (filtros "macios", com fallback pro
# conjunto mais amplo se ninguém passar — ver EncounterArea.pick_group()),
# este é um filtro RÍGIDO: surfar na água nunca pode sortear um grupo
# "Grass" por acaso só porque nenhum grupo "Water" existia ainda (ficaria
# um Rattata terrestre no meio do lago). "Fishing" já existe na lista pra
# quando a vara de pescar for implementada (pedido do usuário: "we will add
# fishing later"), sem precisar mexer neste campo de novo depois.
@export_enum("Grass", "Water", "Fishing") var source: String = "Grass"

# Trava de progressão: este grupo só pode ser sorteado se
# GameState.badges.size() >= min_badges — mesmo princípio de
# trainer.gd::teams (9 tiers indexados por número de badges), só que aqui é
# um LIMIAR (não um tier exato): 0 (padrão) = sempre disponível desde o
# início, 2 = só entra na roleta depois da 2ª badge. É assim que dá pra ter,
# por exemplo, uma espécie mais forte que só começa a aparecer numa rota já
# visitada antes, sem precisar de uma EncounterArea nova só pra isso. Ver
# EncounterArea.pick_group() pra onde isso é de fato checado.
@export var min_badges: int = 0

# Quais períodos do dia (ver GameState.get_time_of_day) este grupo pode ser
# sorteado — @export_flags dá 3 caixinhas no Inspector (Morning/Day/Night),
# cada uma virando 1 bit (1/2/4 nessa ordem — MESMA ordem que
# GameState.TIME_BIT_MORNING/DAY/NIGHT usam, os dois têm que ficar em
# sincronia). Padrão = 7 (as 3 marcadas) = sem gate nenhum, disponível a
# qualquer hora — mesmo espírito permissivo de min_badges=0 acima. Ex: uma
# espécie noturna marcaria só "Night" (valor 4) pra nunca aparecer de dia.
# Ver EncounterArea.pick_group() pra onde isso é de fato filtrado.
@export_flags("Morning", "Day", "Night") var times_of_day: int = 7
