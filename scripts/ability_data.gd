class_name AbilityData
extends ActionData

# Definição de UMA Habilidade passiva (ex: Blaze) — diferente de Ataque, uma
# Habilidade não é "usada" pelo jogador durante o turno: fica sempre ativa,
# checada automaticamente quando relevante (ex: no cálculo de dano). Por
# isso ela nunca aparece como opção clicável na barra de ações (ver
# battle.gd refresh_action_slots_hud) — só ocupa um dos 6 slots pra "estar
# equipada" na unidade. max_uses/range, herdados de ActionData, não fazem
# sentido aqui e ficam no padrão (-1 / 1) sem uso.
#
# O efeito de cada Habilidade é bem específico — Blaze, por exemplo, é só
# "multiplica dano de um tipo quando o HP está baixo". Pra não precisar de
# uma subclasse por Habilidade, os campos abaixo cobrem esse padrão
# específico. Habilidades com efeitos diferentes no futuro provavelmente vão
# precisar de campos novos (ou de subclasses, se ficar bagunçado demais ter
# tudo aqui num campo só).

# Tipo elemental que essa Habilidade favorece (mesmo vocabulário de
# UnitData.types / AttackData.element_type). Vazio = não afeta dano por tipo.
@export var element_type: String = ""

# A Habilidade só tem efeito quando hp_current/hp_max for MENOR que isso
# (ex: 0.25 = precisa estar abaixo de 25% de vida). 1.0 = sempre ativa.
@export var hp_threshold: float = 1.0

# Multiplicador aplicado ao dano de ataques do tipo element_type quando a
# condição de HP acima é satisfeita — entra na parte "Modificadores" da
# fórmula de dano (ver battle.gd calculate_damage_modifiers()).
@export var damage_multiplier: float = 1.0

# Imunidade TOTAL (dano x0) a um tipo de ataque, quando essa Habilidade está
# equipada em QUEM DEFENDE (diferente de element_type/hp_threshold/
# damage_multiplier acima, que boostam o dano de quem ATACA). Vazio = não
# concede imunidade nenhuma. Primeiro caso: Levitate, imune a Ground. Assim
# como a imunidade da TypeChart, bypassa o piso de dano mínimo de 1 — ver
# battle.gd calculate_damage()/has_type_immunity_ability().
@export var immune_type: String = ""

# Se true, essa Habilidade faz a unidade "flutuar" — ignora UnitData.grounded
# e passa a poder atravessar água (e no futuro, qualquer outra restrição de
# terreno) mesmo que o dado base da espécie tenha grounded=true. Levitate é a
# primeira. Ver battle.gd can_cross_fluid().
@export var grants_levitation: bool = false

# Se true, todo ataque QUE TENHA efeito secundário (AttackData.
# secondary_status/secondary_status_2 — ver comentário lá) usado por quem
# carrega essa Habilidade perde o efeito secundário por completo (nunca
# aplica Status Condition nenhuma, mesmo que o roll de chance "acertasse"),
# só que o dano sobe 30% (ver battle.gd::SHEER_FORCE_MULTIPLIER/
# calculate_damage_modifiers/has_sheer_force) — troca "chance de efeito
# extra" por "dano garantido maior". Sheer Force é a primeira. Ataques SEM
# efeito secundário nenhum (secondary_status == "") não ganham bônus algum,
# mesmo com essa Habilidade equipada — só o dano deles não muda.
@export var sheer_force: bool = false
