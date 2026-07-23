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

# Se true, a Speed desta unidade sobe automaticamente +1 estágio (ver
# Unit.modify_stat_stage) ao FINAL de cada turno que ela mesma jogar —
# diferente de Blaze/Sheer Force acima (que só reagem a algo: dano recebido,
# efeito secundário de um ataque), Speed Boost é a primeira Habilidade "de
# tempo": não depende de nada além do turno passar. Ver battle.gd::
# has_speed_boost/_on_end_turn_pressed, que chama apply_stat_change() —
# mesma função e mesmo efeito visual que Growl já usa pra baixar Attack, só
# que aqui é a própria unidade se buffando, não um ataque afetando inimigos.
@export var speed_boost: bool = false

# Tipos elementais dos quais essa Habilidade REDUZ o dano recebido, quando
# equipada em QUEM DEFENDE — ex: Thick Fat resiste Fire e Ice. Diferente de
# immune_type acima (imunidade TOTAL, x0, e um único tipo), aqui pode ter
# vários tipos e o dano só é reduzido por resist_multiplier (não zerado);
# diferente também de element_type/hp_threshold/damage_multiplier (que
# boostam o dano de quem ATACA), esse par funciona do lado de quem DEFENDE,
# sem depender de HP nenhum (sempre ativo). Vazio = não resiste tipo nenhum.
# Ver battle.gd calculate_damage_modifiers().
@export var resist_types: Array[String] = []

# Multiplicador aplicado ao dano recebido quando o tipo do ataque está em
# resist_types acima. 0.5 = metade do dano (Thick Fat). 1.0 = sem efeito
# (padrão, quando resist_types está vazio isso nem chega a ser checado).
@export var resist_multiplier: float = 1.0

# Nome de um clima (ver battle.gd::WEATHER_*) que esta Habilidade ativa
# SOZINHA, automaticamente, assim que a batalha começa — "" (padrão) = não
# ativa clima nenhum. Checado uma vez só por battle.gd::
# _trigger_start_of_battle_abilities(), logo depois que TODAS as unidades
# desta batalha já spawnaram (jogador E inimigo) — pedido do usuário: "When
# multiple units have Start of Battle abilities, they resolve in speed
# order, from highest to lowest". Cada unidade com isso preenchido chama
# battle.gd::try_set_weather() com ELA MESMA como `activator`, então um Heat
# Rock/Damp Rock/etc equipado JUNTO desta Habilidade ainda estende a duração
# normalmente (ver ItemData.extends_weather) — só não faz diferença nenhuma
# pras 3 formas extremas (ver battle.gd::EXTREME_WEATHERS), que já nascem
# permanentes de qualquer jeito, não importa o que try_set_weather receba
# como `permanent`. Desolate Land (Groudon, ver data/abilities/
# desolate_land.tres) é a primeira: "Harsh Sunlight".
@export var sets_weather_on_battle_start: String = ""

# Flash Fire: true = essa Habilidade tem o "cartucho de um uso" descrito na
# Status Condition "Charged" (ver Unit.status_conditions — antes era um bool
# à parte, Unit.flash_fire_armed, convertido pro sistema genérico de status
# empilhável a pedido do usuário: "Change Flash Fire charged to a status,
# this may unbloat attack logic") — aplica "Charged" quando quem carrega ela
# é atingida por um ataque Fire (ver battle.gd::execute_attack/
# execute_attack_burst), e o PRÓXIMO ataque Fire que ELA MESMA usar sai com
# x1.5 de dano (ver battle.gd::calculate_damage_modifiers/
# FLASH_FIRE_MULTIPLIER), consumindo o cartucho. Igual sheer_force/speed_boost
# acima: comportamento fixo demais pra valer a pena um campo configurável
# (multiplicador sempre 1.5, mesmo espírito de SHEER_FORCE_MULTIPLIER ser uma
# constante de regra, não um dado). A imunidade TOTAL a Fire que Flash Fire
# também concede não precisa de campo novo nenhum — já é o mesmíssimo
# immune_type="Fire" que Levitate usa pra Ground (ver comentário lá).
@export var flash_fire: bool = false

# Chlorophyll: true = enquanto o clima da batalha for Sunny OU Harsh
# Sunlight, esta unidade ganha +1 em Unit.attacks_remaining no início do
# próprio turno (ver battle.gd::has_chlorophyll/begin_current_turn) — pedido
# EXATO do usuário: "If the weather is Sun (either Sunny or Harsh
# Sunlight), this unit has an extra action point". Diferente da série
# principal (que dobra Speed), essa é a tradução do usuário pro grid tático:
# um "action point" extra em vez de mais velocidade, reaproveitando
# Unit.attacks_remaining já ser um int (não bool) de propósito, pensado
# desde o início pra um efeito assim (ver comentário grande do campo em
# unit.gd). Ivysaur/Venusaur é o primeiro caso.
@export var chlorophyll: bool = false
