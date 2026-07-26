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

# Damp: pedido do usuário (2026-07-23) — "Damp prevents 'Explosion' moves and
# abilities from working". Groundwork puro por enquanto: nenhum golpe ou
# Habilidade de Explosão existe ainda no projeto (mesma ideia de
# AttackData.tags existir sem nada lendo ainda) — quando um golpe desse tipo
# for implementado, o ponto de checagem certo é perguntar "algum inimigo OU
# aliado no raio de explosão carrega Damp?" antes de deixar o golpe/
# Habilidade disparar, não checar só quem ATACA. Mudkip/Marshtomp/Swampert é
# o primeiro caso, Hidden Ability.
@export var damp: bool = false

# Shield Dust: pedido do usuário (2026-07-23, Caterpie) — "Immune to secondary
# effects of opponent's attacks". Quando quem DEFENDE carrega isso, todo
# secondary_status/secondary_status_2/secondary_stat_change de um golpe
# INIMIGO simplesmente não aplica (dano normal continua batendo igual sempre —
# só o efeito EXTRA que some). Ver battle.gd::has_shield_dust, checado bem no
# topo de _try_apply_secondary_status/_try_apply_secondary_stat_change (mesmo
# ponto único que os dois mecanismos já passam, então cobrir os dois ali cobre
# qualquer golpe futuro que use qualquer um dos dois, sem precisar mexer em
# cada golpe individualmente).
@export var shield_dust: bool = false

# Run Away: pedido do usuário (2026-07-23, Caterpie, Hidden) — "When damaged
# with an attack, the user moves 1 tile away from the enemy that damaged it".
# Diferente da série principal (só permite fugir de encontro selvagem), aqui
# virou um efeito TÁTICO de verdade: sempre que quem carrega isso é atingido
# por um ataque de DANO (não por tick de status/clima — mesma distinção que
# Asleep só cura "ao ser atacada de verdade", ver comentário em execute_attack)
# e sobrevive, anda 1 tile na direção OPOSTA a quem bateu, se a célula estiver
# livre (sem parede/borda/outra unidade — senão simplesmente não se move,
# sem erro). Ver battle.gd::has_run_away/_try_run_away, chamado logo depois de
# defender.take_damage() nos dois caminhos de dano (execute_attack de alvo
# único e execute_attack_burst).
@export var run_away: bool = false

# Compound Eyes: pedido do usuário (2026-07-23, Butterfree) — "Increases
# accuracy of moves by x1.3". Multiplica a Accuracy de QUEM ATACA (não do
# defensor) — mesmo x1.3 fixo de sempre, sem campo de multiplicador
# configurável (mesmo espírito de FLASH_FIRE_MULTIPLIER ser uma constante de
# regra, não um dado). Aproveitado dentro do MESMO cálculo que já existia pra
# Focus Band/Blind (ver Unit.get_accuracy_multiplier) — Compound Eyes só soma
# mais um fator ali, cobrindo golpe de dano E de Status ao mesmo tempo, já que
# os dois já leem esse multiplicador (ver battle.gd::execute_attack/
# execute_status_attack).
@export var compound_eyes: bool = false

# Tinted Lens: pedido do usuário (2026-07-23, Butterfree, Hidden) — "Doubles
# the damage on not very effective moves used". Só entra em jogo quando a
# efetividade de tipo do golpe (ver battle.gd::get_weather_adjusted_
# effectiveness) é MENOR que 1.0 e MAIOR que 0.0 (ou seja, "não muito eficaz"
# de verdade — imunidade total, x0, continua batendo 0 de dano mesmo com isso
# equipado, dobrar zero ainda é zero). x2 fixo, mesmo padrão de Compound Eyes
# acima. Ver battle.gd::has_tinted_lens/calculate_damage.
@export var tinted_lens: bool = false

# Shed Skin: pedido do usuário (2026-07-23, Metapod) — "at the end of each
# turn, recovers from Poison, Paralysis, Freeze and Sleep. Heals from poison
# before being damaged". A parte "antes de ser atingido" é o detalhe que
# importa: diferente de uma cura comum (que rodaria DEPOIS do tick de dano de
# Poisoned já ter acontecido), Shed Skin cura ESSAS QUATRO condições bem no
# INÍCIO de apply_end_of_turn_status, antes até de calcular tick_damage — então
# se a unidade estava Poisoned, ela já não está mais quando o dano seria
# calculado, e simplesmente não tosse o dano daquele turno. SEMPRE (sem chance
# nenhuma, diferente da série principal que usa 33%) — pedido do usuário não
# mencionou chance nenhuma. Confused/Blind/Flinched/etc. NÃO são curadas (só
# as 4 nomeadas). Ver battle.gd::has_shed_skin/apply_end_of_turn_status.
@export var shed_skin: bool = false

# Sniper: pedido do usuário (2026-07-24, Beedrill, Hidden) — "Critical hits
# landed are 2x multiplier instead of 1.5x (easier to just make crits x4/3)".
# Em vez de SUBSTITUIR CRITICAL_HIT_MULTIPLIER (1.5) por um valor fixo
# separado, multiplica o resultado por 4/3 (1.5 * 4/3 = 2.0 exato) — assim
# compõe corretamente com qualquer outro modificador de crítico que apareça
# no futuro, em vez de dois valores "mágicos" competindo. Ver battle.gd::
# has_sniper/calculate_damage/SNIPER_CRIT_MULTIPLIER.
@export var sniper: bool = false

# Swarm: pedido do usuário (2026-07-24, Beedrill) — "Same as overgrowth,
# torrent and blaze but for Bug type moves". Reaproveita o MESMO mecanismo
# genérico de element_type/hp_threshold/damage_multiplier que Blaze/Overgrow/
# Torrent já usam (ver comentários deles acima) — nenhum campo novo
# necessário, só um AbilityData novo com element_type="Bug", hp_threshold=0.25,
# damage_multiplier=1.3 (mesmos números dos outros três, ver data/abilities/
# swarm.tres).

# Wonder Skin: pedido do usuário (2026-07-24, Venomoth, Hidden) — "All enemy
# Status moves targeted at this unit have Accuracy x0.5". Diferente de
# Compound Eyes/Tinted Lens (que mexem no lado de quem ATACA), este é do lado
# de quem DEFENDE, e só afeta golpes de STATUS (is_status=true) — golpes que
# causam dano ignoram isso por completo. Ver battle.gd::has_wonder_skin/
# execute_status_attack (onde o roll de acerto é ajustado se QUALQUER alvo
# resolvido carregar esta Habilidade).
@export var wonder_skin: bool = false

# Effect Spore: pedido do usuário (2026-07-24, Shroomish) — "Counts as a
# Powder move, when taking contact attack, 30% chance to make target
# Paralyzed, Sleep or Poisoned. Status condition is chosen randomly". Quem
# DEFENDE carrega isso; dispara contra quem ATACA (inverso de Shield Dust/Run
# Away, que reagem a dano recebido só na PRÓPRIA unidade) — só se o golpe
# encostar de verdade (AttackData.makes_contact). "Counts as a Powder move"
# (pedido do usuário) = Grass é imune ao efeito, mesma regra que os golpes
# tagged "Powder" já seguem em execute_status_attack (ver AttackData.tags).
# Ver battle.gd::has_effect_spore/_try_effect_spore.
@export var effect_spore: bool = false

# Poison Heal: pedido do usuário (2026-07-24, Shroomish) — "When poisoned,
# user will Heal 1/8 of its HP instead of taking Poison damage each turn".
# Ver battle.gd::has_poison_heal/apply_end_of_turn_status (onde troca o
# bloco de dano por um de cura).
@export var poison_heal: bool = false

# Quick Feet: pedido do usuário (2026-07-24, Shroomish, Hidden) — "x1.5 speed
# if user is Poisoned, Paralyzed or Burned. Additionally, does not lose speed
# when paralyzed". Diferente da maioria das Habilidades daqui (checadas em
# battle.gd), esta é lida DIRETO em Unit.get_effective_stat()/_has_quick_feet
# (ver comentário lá) porque não faz sentido esse cálculo de Speed depender
# de uma referência a battle.gd.
@export var quick_feet: bool = false

# Technician: pedido do usuário (2026-07-24, Breloom) — "If the base power of
# a move is less than or equal 60, multiply it by x1,5". Usa get_effective_
# power() (não AttackData.power cru) na hora de comparar com 60, pra golpes
# que escalam (Rollout/Eruption/etc) serem julgados pelo poder REAL daquele
# uso, não o campo bruto. Ver battle.gd::has_technician/
# TECHNICIAN_MULTIPLIER/calculate_damage_modifiers.
@export var technician: bool = false

# Insomnia (e qualquer Habilidade futura de "imune a UMA Status Condition
# específica por nome, não por tipo"): "" (padrão) = nenhuma. Nome de uma
# Status Condition (vocabulário igual Unit.status_conditions) que esta
# Habilidade bloqueia por completo, mesmo espírito de Unit.
# STATUS_TYPE_IMMUNITIES (ver is_immune_to_status), só que por HABILIDADE em
# vez de TIPO. Worry Seed é o primeiro caso a CRIAR uma Habilidade assim em
# runtime (ver AttackData.replaces_target_ability) — Insomnia (data/abilities/
# insomnia.tres) seta immune_status="Asleep", pedido do usuário: "replace with
# Insomnia (Can't sleep)".
@export var immune_status: String = ""

# Guts: pedido do usuário (2026-07-24, Rattata) — "Multiply Attack stat by 1.5
# if the user is affected by Poison, Sleep, Paralysis or Burn. Additionally,
# Burn does not reduce the user's attack". A primeira parte mora em
# Unit.get_effective_stat() (mesmo padrão de Quick Feet, ver _has_guts lá) —
# x1.5 no Attack quando QUALQUER uma dessas 4 condições estiver ativa. A
# segunda parte ("Burn does not reduce attack") é o x0.5 de Burned em
# battle.gd::calculate_damage_modifiers deixando de se aplicar quando o
# atacante tem Guts (ver has_guts lá) — nos jogos de verdade Burn corta o
# Attack STAT; aqui Burn corta o MODIFICADOR de dano físico direto (ver
# comentário lá), então Guts cancela esse modificador em vez de "devolver" o
# stat, mesmo efeito final.
@export var guts: bool = false

# Hustle: pedido do usuário (2026-07-24, Rattata, Hidden) — "Multiply attack
# by 1.5 but multiply the accuracy of physical moves by 0.8". A parte do
# Attack mora em Unit.get_effective_stat() (incondicional, diferente de Guts
# acima que exige uma Status Condition) — a parte da Accuracy mora em
# battle.gd::execute_attack/execute_attack_burst (ver has_hustle), só quando
# attack.is_special == false (golpe FÍSICO — golpe de Status nunca passa por
# essas duas funções, então nem precisa checar is_status aqui).
@export var hustle: bool = false

# Keen Eye: pedido do usuário (2026-07-24, Spearow) — "Accuracy x1.1 and
# Immune to Blind". O x1.1 é hardcoded em Unit.get_accuracy_multiplier() (ver
# comentário lá), mesmo padrão de Compound Eyes (x1.3) — a imunidade a Blind
# reaproveita o campo genérico immune_status acima (ver AbilityData.
# immune_status/Insomnia): Keen Eye só precisa setar immune_status="Blind" no
# .tres, sem precisar de nenhum campo novo pra essa parte.
@export var keen_eye: bool = false

# Static: pedido do usuário (2026-07-24, Pichu) — "When hit by a contact
# move, 30% chance to Paralyzing the opponent". Nome "static" sozinho colide
# com a palavra reservada `static` do GDScript (usada em métodos estáticos),
# por isso o campo chama static_paralysis em vez disso. Mesmo mecanismo de
# Effect Spore (ver AbilityData.effect_spore/battle.gd::_try_static): dispara
# em QUEM ATACA quando um golpe de CONTATO (AttackData.makes_contact) acerta
# quem carrega esta Habilidade, sem exigir tipo nenhum de imunidade especial
# (diferente de Effect Spore, que poupa Grass por "contar como pó" — Static
# não tem essa ressalva no pedido do usuário).
@export var static_paralysis: bool = false

# Lightning Rod: pedido do usuário (2026-07-24, Pichu, Hidden) — "Immune to
# Electric attacks. When hit by one, ups self Sp.Atk by 1. Redirect single
# target Electric moves used on allies at range 2 distance to self". A
# imunidade reaproveita o campo genérico immune_type="Electric" (mesmo
# mecanismo de Levitate/Ground, ver AbilityData.immune_type/
# has_type_immunity_ability) — SEM precisar de campo novo pra essa parte. Este
# campo aqui (lightning_rod) só existe pra sinalizar as OUTRAS duas partes,
# que immune_type sozinho não cobre: o +1 Sp.Atk ao ser atingido por Electric
# (ver battle.gd::execute_attack/execute_attack_burst, mesmo ponto onde Flash
# Fire arma "Charged") e o redirecionamento de golpe elétrico de ALVO ÚNICO
# mirado num ALIADO pra quem carrega Lightning Rod (ver battle.gd::
# _redirect_lightning_rod), quando o PORTADOR estiver a até 2 tiles do ALIADO
# mirado (distância confirmada com o usuário: "Portador até o ALIADO
# mirado", não até quem ataca). Groundwork parcial documentado no ponto de
# chamada: o redirecionamento só cobre golpes QUE CAUSAM DANO (battle.gd::
# execute_attack), não golpes de Status de alvo único (ex: um futuro Thunder
# Wave usado num aliado) — mesmo espírito de outras features "cobrem o caso
# principal, resto é groundwork" já usado neste projeto (ver Damp/Brick
# Break).
@export var lightning_rod: bool = false

# Serene Grace: pedido do usuário (2026-07-25, Togepi) — "Secondary effects
# on moves have 2x chance of happening". Dobra (capado em 1.0) a chance de
# QUALQUER efeito secundário do golpe usado por quem carrega isso: secondary_
# status/_2 (ver _try_apply_secondary_status), secondary_stat_change (ver
# _try_apply_secondary_stat_change) e self_stat_boost (ver _try_apply_self_
# stat_boost) — os três mecanismos de "efeito extra com % de chance" que já
# existiam, cada um dobrado no mesmo ponto onde já lia attack.*_chance. Ver
# battle.gd::has_serene_grace/EFFECTIVE_CHANCE (função utilitária pra não
# repetir min(1.0, chance*2) em 3 lugares diferentes).
@export var serene_grace: bool = false

# Super Luck: pedido do usuário (2026-07-25, Togepi, Hidden) — "Doubles
# critical hit chance for moves used". Mesmo efeito multiplicativo que a
# Status Condition "Focus Energy" já dá (ver battle.gd::
# get_effective_crit_chance), só que como Habilidade PASSIVA (sempre ativa,
# sem precisar usar Focus Energy antes) — os dois compõem livremente se a
# mesma unidade tiver as duas coisas ao mesmo tempo (crit chance x4 nesse
# caso raro).
@export var super_luck: bool = false

# Swift Swim: pedido do usuário (2026-07-25, Horsea) — "If weather is Rain,
# has 1 extra action point (chlorophyl for rain)". Mesmíssimo mecanismo de
# AbilityData.chlorophyll (ver comentário grande lá) — só troca a condição de
# clima de Sunny/Harsh Sunlight pra Rain/Heavy Rain. Ver battle.gd::
# has_swift_swim/begin_current_turn (mesmo bloco que já confere Chlorophyll).
@export var swift_swim: bool = false

# Poison Point: pedido do usuário (2026-07-25, Seadra) — "When taking contact
# move, 30% to poison attacker". Mesmo formato de Static (ver AbilityData.
# static_paralysis) — dispara em QUEM ATACA quando um golpe de CONTATO acerta
# quem carrega esta Habilidade, status fixo "Poisoned" em vez de "Paralyzed".
# Ver battle.gd::has_poison_point/_try_poison_point.
@export var poison_point: bool = false

# Hyper Cutter: pedido do usuário (2026-07-25, Corphish) — "Attack can't be
# reduced. If a Sharp move is used, raises Atk +1 after the move is used".
# Duas partes independentes: a imunidade a QUEDA de Attack é checada em
# Unit.modify_stat_stage (bloqueia só deltas NEGATIVOS no stat "attack" de
# quem carrega isso, deltas positivos continuam normais); o auto-buff de
# golpe "Sharp" é checado em battle.gd::execute_attack/execute_attack_burst
# (ver has_hyper_cutter), depois que o golpe termina de causar dano.
@export var hyper_cutter: bool = false

# Shell Armor: pedido do usuário (2026-07-25, Corphish) — "Can't be hit by
# critical hits". Força is_critical=false no roll de battle.gd (ver
# has_shell_armor), checado em TODOS os pontos que rolam crítico contra um
# defensor (execute_attack, execute_attack_burst, _resolve_multi_hit_damage).
@export var shell_armor: bool = false

# Adaptability: pedido do usuário (2026-07-25, Corphish, Hidden) — "STAB
# attacks do x4/3 damage (replaces normal x1.5 multiplier to a x2
# multiplier)". Em vez de multiplicar por cima do x1.5 de STAB normal (que
# daria um número estranho), SUBSTITUI o x1.5 por x2.0 direto em
# calculate_damage_modifiers, mesmo espírito de crit_chance_override
# (substitui, não empilha).
@export var adaptability: bool = false

# Vital Spirit: pedido do usuário (2026-07-25, Mankey) — "Immune to Sleep".
# Reaproveita o campo genérico immune_status acima (mesmo mecanismo de
# Insomnia/Keen Eye) — Vital Spirit só precisa setar immune_status="Asleep"
# no .tres, sem campo novo pra essa parte. Ver AbilityData.immune_status.

# Anger Point: pedido do usuário (2026-07-25, Mankey) — "If hit with a
# critical hit, raises attack to +6 (not increasing by 6, it becomes
# maximized)". Diferente de qualquer stat_change normal (que soma um delta
# fixo), este PREENCHE o estágio de Attack direto no STAT_STAGE_MAX,
# não importa onde estava antes — ver battle.gd::_try_anger_point, chamado
# nos 3 pontos que já logam "A critical hit!" (execute_attack,
# execute_attack_burst, _resolve_multi_hit_damage), sempre que QUEM DEFENDE
# carrega esta Habilidade.
@export var anger_point: bool = false

# Defiant: pedido do usuário (2026-07-25, Mankey, Hidden) — "Whenever this
# unit has its stats dropped by an opponent's move, raises attack +2".
# Precisa distinguir queda de stat causada por INIMIGO (Growl, Toxic,
# secondary_stat_change, etc.) de queda AUTO-INFLIGIDA (Close Combat, Overheat
# etc. baixando o próprio stat do atacante) — por isso battle.gd::
# apply_stat_change ganhou um parâmetro `source` opcional (mesmo padrão de
# Unit.apply_status_condition), passado só nos golpes que miram um INIMIGO de
# verdade. Ver battle.gd::has_defiant/apply_stat_change.
@export var defiant: bool = false

# Sand Veil: pedido do usuário (2026-07-25, Larvitar, Hidden) — "Increases
# Speed x2 during Sand weather. Immune to Sand weather damage". A parte de
# Speed é lida direto em Unit.get_effective_stat() (mesmo padrão de Quick
# Feet, ver _has_sand_veil lá) porque esse cálculo não tem acesso a
# battle.gd; a imunidade ao tick de dano do Sandstorm é checada em
# battle.gd::get_weather_tick_damage (mesma lista de exceção que Ground/
# Steel/Rock já usam por TIPO, só que aqui é por Habilidade).
@export var sand_veil: bool = false

# Snow Cloak: pedido do usuário (2026-07-25, Swinub, Hidden) — "Same as Sand
# Veil, but for Snow. Increases speed during that weather". Mesmo mecanismo
# exato de Sand Veil acima, só que checando WEATHER_SNOW em vez de
# WEATHER_SANDSTORM nos dois pontos (Unit.get_effective_stat pro Speed x2,
# battle.gd::get_weather_tick_damage pra imunidade) — ver _has_snow_cloak/
# has_snow_cloak. Perguntado explicitamente se isso deveria vir junto com um
# novo dano de clima pra Snow (que até então não existia, diferente de
# Sandstorm): resposta "Add Snow chip damage + immunity", então Snow ganhou
# o mesmo tick de 1/16 que Sandstorm já tinha, com Ice-type imune (ver
# SNOW_IMMUNE_TYPES) em vez de Ground/Steel/Rock.
@export var snow_cloak: bool = false

# Unnerve: pedido do usuário (2026-07-25, Tyranitar) — "Opponents in range 3
# burst can't consume berries". Diferente de Damp (groundwork puro, nenhum
# golpe de Explosão existe ainda), Unnerve JÁ tem efeito de verdade: checado
# em battle.gd::_check_berry_auto_use (via has_unnerve_nearby), que agora
# procura, entre os INIMIGOS de quem tentaria comer a Berry, algum portador
# de Unnerve a até 3 tiles de distância (Chebyshev, mesmo critério de
# distância de Lightning Rod) antes de deixar a auto-consumação acontecer.
@export var unnerve: bool = false

# Pressure: pedido do usuário (2026-07-26, Suicune) — "Enemy units in burst
# range 2 gain Pressure status (Removed when out of range). Pressured units
# have their movement reduced by 2 (Minimum of 1)". Diferente de qualquer
# Habilidade anterior (todas reagem a um EVENTO discreto: dano recebido,
# clima, turno passar), Pressure é uma "aura" de posição, recalculada
# continuamente — ver battle.gd::_update_pressure_status(), chamado bem no
# início de begin_current_turn() de CADA unidade, ANTES de move_range ser
# lido pela primeira vez naquele turno (aproximação deliberada de "removed
# when out of range" nesse motor por turnos: reavaliado a cada início de
# turno, não frame a frame). O efeito de -2 movimento mora em Unit.
# move_range (checa has_status("Pressured") direto), a aplicação/remoção
# em si passa pelo pipeline normal de apply_status_condition/
# cure_status_condition (respeitando imunidade — ver immune_to_pressure
# abaixo — automaticamente, sem checagem manual nenhuma).
@export var pressure: bool = false

# Inner Focus: pedido do usuário (2026-07-26, Suicune) — "Immune to flinch,
# Intimidate and Pressure". A parte de Flinch reaproveita o campo genérico
# immune_status acima (ver Insomnia/Oblivious) — o .tres desta Habilidade
# simplesmente seta immune_status="Flinched", sem precisar deste bool aqui
# pra essa parte. Intimidate segue sem efeito nenhum (ainda não existe no
# motor — mesma nota de Oblivious sobre isso, "we still don't have the
# intimidate functionality"). Este bool cobre só a parte que immune_status
# sozinho não cobre: Pressure (ver immune_to_pressure abaixo, PARTILHADO
# entre Inner Focus e Oblivious — por isso é um campo à parte em vez de só
# reaproveitar immune_status, que já está ocupado por "Flinched" aqui).
@export var inner_focus: bool = false

# Imunidade a Pressure (ver AbilityData.pressure acima) — campo À PARTE de
# immune_status porque DUAS Habilidades precisam dela ao mesmo tempo que
# JÁ usam immune_status pra outra coisa: Inner Focus (immune_status=
# "Flinched") e Oblivious (immune_status="Taunted", ver oblivious.tres,
# atualizado 2026-07-26 — pedido do usuário: "Update to Oblivious: Add
# Immune to Pressure"). Checado dentro do MESMO laço genérico de
# is_immune_to_status() (ver unit.gd), então funciona automaticamente por
# apply_status_condition("Pressured") — battle.gd::_update_pressure_status
# não precisa checar isso na mão.
@export var immune_to_pressure: bool = false

# Water Absorb: pedido do usuário (2026-07-26, Suicune, Hidden) — "Immune
# to Water moves. Heals 25% of its HP if hit by a Water move". A imunidade
# reaproveita o campo genérico immune_type="Water" já existente (mesmo
# mecanismo de Levitate/Lightning Rod, ver AbilityData.immune_type) — SEM
# precisar de campo novo pra essa parte. Os dois campos abaixo cobrem só a
# cura, que nenhuma Habilidade anterior fazia: heals_on_type_hit guarda O
# TIPO que dispara a cura ("" = nenhum, padrão) e heal_on_type_hit_fraction
# guarda A FRAÇÃO do HP máximo curada (0.25 = 25%, valor exato do pedido).
# Ver battle.gd::_try_type_absorb_heal, chamado no MESMO ponto/espírito que
# já dispara o "Charged" de Flash Fire (golpe CONECTOU de verdade, mesmo
# que o dano real vá sair 0 pela imunidade de tipo).
@export var heals_on_type_hit: String = ""
@export var heal_on_type_hit_fraction: float = 0.25

# Updraft: pedido do usuário (2026-07-26, Suicune, Habilidade de CHEFE — ver
# LearnsetEntry.is_boss_ability) — "Uses Tailwind on Battle start. Wind
# attacks used by allied units (including this one) do 1.3x damage". A
# parte "Tailwind on Battle start" reaproveita sets_status_on_battle_start
# abaixo (campo genérico novo, mesmo espírito de sets_weather_on_battle_
# start, só que aplicando uma STATUS CONDITION na própria unidade em vez de
# um clima de batalha inteiro — ver battle.gd::_trigger_start_of_battle_
# abilities). Este bool aqui cobre só a OUTRA metade, que não é
# generalizável do mesmo jeito (dano de golpes marcados tag "Wind" usados
# por QUALQUER unidade do MESMO LADO de quem carrega isso, incluindo ela
# mesma) — ver battle.gd::calculate_damage_modifiers/UPDRAFT_WIND_
# MULTIPLIER. Mesmo padrão de outras Habilidades "pacote" (Hustle/Guts/
# Hyper Cutter) que bundlam mais de um efeito atrás de um bool só.
@export var updraft: bool = false

# Habilidade "de entrada" que aplica uma STATUS CONDITION na PRÓPRIA unidade
# assim que a batalha começa — irmã de sets_weather_on_battle_start (ver
# comentário grande dele acima), só que pra status em vez de clima. ""
# (padrão) = não aplica nada. Genérico de propósito (mesmo espírito de
# immune_status), mesmo que Updraft seja o único caso hoje — uma Habilidade
# futura de "X on Battle start" reaproveita isto sem precisar de campo
# novo. Ver battle.gd::_trigger_start_of_battle_abilities (mesmo laço
# ordenado por Speed que já dispara clima).
@export var sets_status_on_battle_start: String = ""
