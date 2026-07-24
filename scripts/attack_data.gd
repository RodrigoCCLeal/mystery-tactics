class_name AttackData
extends ActionData

# Definição de UM ataque (a "receita" — não confundir com o estado de uso em
# combate, que fica em Unit.slot_uses, não aqui). Como um AttackData pode ser
# a mesma instância de Resource compartilhada entre várias unidades da mesma
# espécie, current/max de usos NÃO mora aqui — senão gastar o ataque de uma
# unidade descontaria de todas as outras que carregam o mesmo AttackData.
#
# max_uses (contador atual/máximo) vem de ActionData — todo ataque deve
# definir um valor >0 nele (diferente de Habilidade/Item, onde -1 = sem
# contador é o normal). Ver comentário em ActionData.max_uses.

@export var is_special: bool = false   # false = Físico, true = Especial
@export var element_type: String = ""  # mesmo vocabulário de UnitData.types (Fire, Water, Grass, etc.)

# true = ataque de STATUS — nem Físico nem Especial (is_special vira
# irrelevante: nenhum dos dois se aplica). Não causa dano NENHUM, mesmo que
# power/element_type estejam preenchidos — battle.gd usa uma função de
# execução própria pra isso (execute_status_attack), separada de
# execute_attack, porque calculate_damage() sempre devolve pelo menos 1 de
# dano (max(1, damage) — ver comentário lá), então reaproveitar
# execute_attack faria um "ataque de status" causar 1 de dano por engano.
# Growl é o primeiro caso: só aplica stat_change_stat/_amount em quem está na
# área, sem tocar no HP de ninguém.
@export var is_status: bool = false

# Chance de acerto (1.0 = 100%). Rolado em battle.gd::execute_attack, logo
# depois do windup/cast/projétil e antes de qualquer reação de quem defende —
# accuracy * attacker.get_accuracy_multiplier() (Focus Band, Blind, ver
# Unit.get_accuracy_multiplier) é a chance final; 1.0 sempre acerta (pula o
# randf() de propósito). Ice Fang é o primeiro ataque com accuracy < 1.0
# (0.95) — os outros (Water Gun, Vine Whip) ainda usam o padrão de 1.0.
@export_range(0.0, 1.0) var accuracy: float = 1.0

# true = pula o roll de acerto POR COMPLETO em execute_attack, ignorando até
# attacker.get_accuracy_multiplier() (ex: o próprio atacante estar Blind) —
# diferente de só deixar accuracy no padrão 1.0, que ainda pode falhar se
# esse multiplicador cair abaixo de 1.0. Swift é o primeiro caso: "never
# misses" de verdade, pedido explícito do usuário depois de eu perguntar se
# eu devia tratar isso como um golpe comum de accuracy=1.0 (que ainda podia
# falhar num atacante Blind) ou um bypass de verdade.
@export var never_misses: bool = false

# 0 = sem dano direto (ex: ataque que só aplica um efeito/status, sem golpe).
@export var power: int = 0

# Quantos tiles o golpe atinge a partir do alvo (1 = só o próprio tile
# mirado, sem "espirrar" pros vizinhos). Groundwork: nenhum código ainda lê
# isso pra causar dano em mais de um tile — hoje todo ataque (mesmo os com
# area_of_effect > 1 aqui, se algum vier a ter) só afeta o alvo resolvido
# normalmente (ver battle.gd::execute_attack). Existe agora só pra já vir
# documentado nos dados do ataque (ex: Confusion = 1).
@export var area_of_effect: int = 1

# Formato da área atingida. "Single" só importa pra ataques de STATUS
# (is_status true) — ataques com dano continuam mirando 1 alvo só nesse caso
# (ver comentário de area_of_effect acima, ainda groundwork pra esses).
# "Cone", "Burst" e "Line" funcionam tanto pra ataque de Status quanto pra
# ataque QUE CAUSA DANO (ver battle.gd::execute_attack_burst) — por isso
# moram aqui, no campo compartilhado.
# "Single" (padrão) = mira 1 alvo só, igual todo ataque de sempre.
# "Cone" = abre um leque a partir de quem ataca, na direção mirada, até
# `range` tiles de distância. Pra ataque de Status (ver execute_status_
# attack), atinge só INIMIGOS dentro do leque (Growl é o primeiro caso:
# range=3, Cone, lowers Attack). Pra ataque QUE CAUSA DANO (ver
# execute_attack_burst), atinge TODO MUNDO no leque, aliado incluso (Overheat
# é o primeiro caso: "cone with the same range as growl, hit every unit
# including allies" — pedido do usuário).
# "Burst" = explosão centrada em QUEM ATACA — atinge TODO MUNDO (aliado E
# inimigo, exceto quem usou o golpe) dentro de `range` tiles, sem precisar
# mirar direção nenhuma de verdade (mesmo espírito de sets_weather/
# stat_change_target="Self": o clique só CONFIRMA o uso, não decide quem é
# atingido — ver battle.gd::execute_attack_burst). Lava Plume é o primeiro
# caso: range=1, "hits every target within 1-tile range, including allies"
# (pedido do usuário). Diferente de Cone, funciona tanto pra ataque de
# Status quanto pra ataque QUE CAUSA DANO — por isso mora aqui, no campo
# compartilhado, em vez de virar mais um campo só-de-status.
# "Line" = feixe reto de 1 tile de largura, saindo de quem ataca na direção
# mirada, até `range` tiles (para em parede/borda, mesmo critério de
# find_projectile_target) — atinge TODO MUNDO (aliado E inimigo) em CADA
# célula do caminho, não só o primeiro que encontrar (diferente de
# is_projectile, que para no primeiro inimigo). Flamethrower é o primeiro
# caso: range=3, "straight line of 3 tiles, hits every unit in the shape"
# (pedido do usuário, com fogo amigo incluído — mesma resposta de Burst).
# Resolvido pela MESMA função de Burst (ver battle.gd::execute_attack_burst)
# — só a geometria de quem é achado muda, o resto (roll de acerto único,
# aplicar em cada alvo, boost/recoil uma vez só no fim) é idêntico.
# "Wide" = 3 células NUMA FILA SÓ, perpendicular à direção mirada, todas a
# exatamente `range` passos de distância na direção mirada (não um leque que
# cresce com a distância feito Cone, nem um raio ao redor feito Burst) —
# Rock Slide é o primeiro caso (pedido do usuário, com exemplo exato: "user
# on (1,1), hits on (2,0)(2,1)(2,2)" mirando pra direita, range=1). Ver
# battle.gd::get_wide_cells — cell central = origin + dir*range, e as outras
# duas são cell central ± o vetor perpendicular a dir (rotação de 90°:
# Vector2i(-dir.y, dir.x)). Igual Cone/Line, atinge TODO MUNDO (aliado E
# inimigo) nas 3 células — resolvido pela mesma execute_attack_burst.
# "Team" = sem mira nenhuma, sem geometria de grid nenhuma — atinge TODO MUNDO
# do MESMO lado de quem usa (aliados E quem usa, ver battle.gd::
# execute_status_attack), não importa a posição/distância de ninguém. Pensado
# pra efeitos de time inteiro tipo Tailwind ("All allies gain Tailwind
# Status", pedido do usuário, SEM nenhum número de alcance dado — diferente de
# Safeguard, que ganhou "burst range 3" explícito, por isso os dois usam
# mecanismos diferentes: Safeguard é Burst+targets_allies, Tailwind é Team).
# Só faz sentido em ataque de Status (is_status=true), igual Burst/Cone/Line.
@export_enum("Single", "Cone", "Burst", "Line", "Wide", "Team") var area_shape: String = "Single"

# true = a geometria Burst (ver area_shape acima) atinge ALIADOS (incluindo
# quem usa) em vez de INIMIGOS — inverte o filtro padrão de execute_status_
# attack's ramo Burst, que normalmente pula quem é do mesmo lado. Safeguard é
# o primeiro caso: "All allies in burst range 3 gain Safeguard status"
# (pedido do usuário) — quem usa TAMBÉM entra (é um efeito de proteção, faz
# sentido o próprio usuário se beneficiar também, mesmo espírito de Tailwind/
# area_shape=="Team"). false (padrão) = comportamento de sempre, mira inimigo.
@export var targets_allies: bool = false

# ---------- Mudança de Stat (ataques de Status) ----------
# "" = sem mudança de stat. Vocabulário igual Unit.STAGE_STATS ("attack",
# "defense", "special_attack", "special_defense", "speed"). Só lido quando
# is_status=true — battle.gd::execute_status_attack aplica isso (via
# Unit.modify_stat_stage) em CADA inimigo encontrado na área (Single ou
# Cone), sem checar dano nenhum (ataque de Status não causa dano). Por
# enquanto só afeta INIMIGOS (não existe ainda um modo "self"/aliados — um
# futuro "Swords Dance", que sobe o próprio Attack, precisaria de um campo
# novo pra escolher o alvo, já que Growl só precisa mirar inimigo mesmo).
@export var stat_change_stat: String = ""

# Quanto mexe no estágio (ver Unit.STAGE_STATS/STAT_STAGE_MULTIPLIERS) —
# pode ser negativo (Growl = -1 no Attack) ou positivo (um futuro golpe de
# buff). 0 = sem efeito, mesmo com stat_change_stat preenchido.
@export var stat_change_amount: int = 0

# "Enemy" (padrão, todo golpe de antes deste campo existir continua igual) =
# stat_change_stat/_amount aplicam em cada INIMIGO achado na área (Single ou
# Cone), igual sempre. "Self" = aplica em QUEM ATACA, sem mirar ninguém —
# ignora a busca de inimigo na área por completo (ver battle.gd::
# execute_status_attack). Defense Curl é o primeiro caso: sobe a própria
# Defense, sem precisar achar um inimigo pra "funcionar" (mesmo espírito de
# sets_weather nunca falhar por falta de alvo, ver comentário lá) — pedido do
# usuário: "Add a target mode to AttackData" pra golpes de auto-buff em geral
# (não só Defense Curl), então qualquer golpe futuro tipo Swords Dance/Iron
# Defense/Agility usa isso também.
@export_enum("Enemy", "Self") var stat_change_target: String = "Enemy"

# Segundo stat mexido pelo MESMO golpe, além de stat_change_stat/_amount —
# "" (padrão) = golpe de um stat só, como sempre foi. Growth é o primeiro
# caso: sobe Attack (stat_change_stat/_amount) E Special Attack ao mesmo
# tempo, sempre nos DOIS, nunca só um. Aplicado sempre no MESMO alvo que
# stat_change_stat (mesmo stat_change_target — não existe "stat 1 no
# inimigo, stat 2 em mim"), ver battle.gd::execute_status_attack. Padrão
# reaproveitável pra qualquer golpe futuro de "sobe 2 stats juntos" (Calm
# Mind, Bulk Up, Dragon Dance, etc.) sem precisar de campo novo cada vez.
@export var stat_change_stat_2: String = ""
@export var stat_change_amount_2: int = 0

# Terceiro stat mexido pelo MESMO golpe, além de stat_change_stat/_2 — ""
# (padrão) = golpe de até 2 stats, como antes deste campo existir. Quiver
# Dance é o primeiro caso: sobe Special Attack/Special Defense/Speed, os TRÊS
# de uma vez, sempre em quem usa (stat_change_target=="Self") — não reaproveita
# self_stat_boost_chance/_amount (Ancient Power) porque aquele mecanismo é
# SEMPRE os 5 stats de STAGE_STATS com uma % de chance; este é um número FIXO
# de stats ESCOLHIDOS, sempre garantido (sem chance nenhuma), igual stat_
# change_stat/_2. Nunca precisa de "stat 4" — se um golpe futuro precisar de
# mais que 3, essa lista vira Array em vez de crescer campo por campo.
@export var stat_change_stat_3: String = ""
@export var stat_change_amount_3: int = 0

# true = stat_change_amount E stat_change_amount_2 DOBRAM de valor enquanto o
# clima da batalha for Sunny/Harsh Sunlight (ver battle.gd::is_sun_weather) —
# Growth é o primeiro caso: "+1/+1 normalmente, +2/+2 durante o Sol", mesma
# regra da série principal. false (padrão) = amount/_2 sempre fixos,
# independente de clima nenhum.
@export var stat_change_doubles_in_sun: bool = false

# ---------- Cura em si mesmo (Synthesis e afins) ----------
# 0.0 (padrão) = golpe não cura ninguém. > 0.0 = golpe de Status que cura o
# PRÓPRIO usuário em uma fração de hp_max, sempre em QUEM ATACA (não existe
# "curar o inimigo") — ver battle.gd::execute_status_attack, que checa este
# campo ANTES de stat_change_target=="Self"/sets_weather (os três são
# mutuamente exclusivos na prática: nenhum golpe hoje combina cura com
# mudança de stat ou clima). Synthesis é o primeiro caso — este valor aqui é
# a fração "padrão" (sem Sol nem clima ruim, ver comentário grande dos dois
# campos abaixo): pedido do usuário, "Strong winds or no weather, 1/2 hp".
# Falha ("But it failed!") se quem usa já estiver com HP cheio, mesmo
# comportamento de cura de item/série principal.
@export var self_heal_fraction: float = 0.0

# -1.0 (padrão) = SEM caso especial de Sol, usa self_heal_fraction normal
# mesmo com Sunny/Harsh Sunlight ativo. >= 0.0 = SUBSTITUI self_heal_fraction
# só enquanto o clima for de Sol (ver battle.gd::is_sun_weather) — Synthesis:
# "Sun 2/3 hp". Padrão de "-1 = sem caso especial, senão substitui" igual
# crit_chance_override acima, mesmo motivo (0.0 seria ambíguo com "cura 0%
# de propósito", que nenhum golpe real usaria, mas -1 deixa a intenção
# explícita mesmo assim).
@export var self_heal_fraction_in_sun: float = -1.0

# -1.0 (padrão) = SEM caso especial de clima ruim. >= 0.0 = SUBSTITUI
# self_heal_fraction enquanto o clima for QUALQUER coisa que não seja Sol
# nem Strong Winds nem "sem clima" (ver battle.gd::
# get_effective_self_heal_fraction — Rain/Heavy Rain/Sandstorm/Snow) —
# Synthesis: "Any other weather, 1/4 hp". Strong Winds SAI desta categoria
# de propósito (pedido do usuário: "Strong winds or no weather, 1/2 hp" —
# mesma fração do caso sem clima nenhum, não a de clima ruim).
@export var self_heal_fraction_in_bad_weather: float = -1.0

# "" = sem Status Condition nenhuma aplicada. Vocabulário igual
# Unit.status_conditions (ex: "Blind", "Poisoned"...) — diferente de
# secondary_status/secondary_status_2 acima (que só existem em ataques QUE
# CAUSAM DANO, rolados só se o golpe acertou e o alvo sobreviveu, ver
# execute_attack/_try_apply_secondary_status), este é o equivalente pra
# ataques de STATUS (is_status=true): aplicado, SEMPRE que acha um alvo
# (sem chance nenhuma — pedido do usuário: Smokescreen aplica Blind de forma
# garantida, não uma % de chance), em CADA inimigo encontrado na área (Single
# ou Cone, mesmo critério de stat_change_stat acima), via
# battle.gd::execute_status_attack. Smokescreen é o primeiro caso: "Blind"
# (ver Unit.get_accuracy_multiplier(), que já dá x0.5 de precisão a quem está
# Blind — a "queda de precisão" da série principal vira uma Status Condition
# de verdade aqui, em vez de reaproveitar stat_change_stat, porque não existe
# stat_stage de precisão/evasão neste jogo).
@export var inflicts_status: String = ""

# Textura tocada em cima do alvo quando inflicts_status realmente aplica (ver
# ImpactEffect.play(), mesma ideia de secondary_status_texture acima) — null
# (padrão) = sem efeito visual nenhum.
@export var inflicts_status_texture: Texture2D

# false (padrão) = inflicts_status mira o(s) INIMIGO(S) encontrado(s) na área,
# igual sempre. true = Protect é o primeiro caso — a Status Condition acima
# (aqui, "Protected") é aplicada em QUEM ATACA, nunca em quem foi clicado, o
# clique só confirma o uso (mesmo espírito de stat_change_target=="Self"/
# self_heal_fraction, ver is_self_target_status). "75% chance to give user
# full immunity until its next turn" (pedido do usuário) já é coberto pelo
# roll de acerto que TODO golpe de Status agora tem (ver o "We need to
# implement accuracy checks for status moves" desta mesma sessão) — Protect
# só precisa de accuracy=0.75 no .tres, sem campo novo pra "chance de
# funcionar" separado da accuracy normal.
@export var inflicts_status_on_self: bool = false

# Nome de um clima (ver battle.gd::WEATHER_*) que esse ataque de Status
# ativa — "" (padrão) = não mexe em clima nenhum. Só lido quando
# is_status=true, igual stat_change_stat acima, mas SEM depender de achar
# ninguém na área mirada (ver battle.gd::execute_status_attack): diferente
# de stat_change_stat (que precisa de um inimigo pra fazer efeito, e loga
# "But it failed!" sem um), clima é um efeito de CAMPO, não mira ninguém de
# verdade — o jogador ainda clica uma direção (mesmo fluxo de mira de
# qualquer ataque de Status, ver is_valid_target_cell), mas o que tem ou não
# na célula clicada não importa nada pro resultado. Sunny Day (ver
# data/attacks/sunny_day.tres) é o primeiro caso: "Sunny". `attacker` vira o
# `activator` de battle.gd::try_set_weather() — um item que estende clima
# (ver ItemData.extends_weather) equipado por quem usa este ataque funciona
# normalmente.
@export var sets_weather: String = ""

# Se esse ataque encosta fisicamente no alvo (ex: Tackle) ou não (ex: Ember,
# que acerta de longe com fogo). Não afeta nada ainda — vai importar no
# futuro pra Habilidades/efeitos que só disparam "em contato" (ex: uma
# Habilidade que causa queimadura em quem encostar no usuário).
@export var makes_contact: bool = false

# false (padrão) = ataque "corpo a corpo": só acerta na distância EXATA de
# ActionData.range (ver comentário lá). true = ataque-projétil: viaja em
# linha reta (horizontal/vertical/diagonal de 45°) a partir de quem ataca e
# acerta o PRIMEIRO inimigo que encontrar pelo caminho, até no máximo
# ActionData.range tiles de distância — ou seja, pra projétil, range é o
# alcance MÁXIMO, não uma distância exata (ver battle.gd is_valid_target_cell
# e find_projectile_target). Aliados no meio do caminho não bloqueiam (por
# enquanto — ver comentário em find_projectile_target).
@export var is_projectile: bool = false

# true = mesmo pra um ataque-projétil (is_projectile=true), quem ataca se
# move fisicamente pra perto de onde o golpe conectou de verdade, MESMA
# regra de _try_melee_lunge (ver comentário grande lá) — só existe como
# campo separado porque _try_melee_lunge, por padrão, NUNCA mexe num ataque-
# projétil (um golpe à distância normal, tipo Ember, não devia fazer quem
# ataca correr pra cima do alvo). Rollout é o primeiro caso a precisar dos
# dois ao mesmo tempo: "Same logic as quick attack, stop at the first enemy
# hit and move to the free tile closest to the hit target" — um projétil que
# também fecha distância, sem transformar TODO projétil em lunge por engano.
@export var lunges_to_target: bool = false

# Sprite do projétil: uma tira horizontal de quadros QUADRADOS (largura =
# altura de cada quadro), ex: assets/sprites/move/Ember.None.png. Só usado
# se is_projectile=true. battle.gd calcula o tamanho/quantidade de quadros
# em runtime a partir da textura (ver Projectile.launch()), não precisa
# configurar nada além de arrastar a imagem aqui.
@export var projectile_texture: Texture2D

# Alternativa a projectile_texture pra quando a arte do projétil vem como
# VÁRIOS arquivos separados (um por quadro), em vez de uma única tira
# horizontal dentro de uma imagem só — ex: Water Gun (waterGun0.png,
# waterGun1.png). Se preenchido (não vazio), tem prioridade sobre
# projectile_texture: cada Texture2D aqui é usado INTEIRO como um quadro,
# sem nenhum corte de atlas (ver Projectile.launch()/_process()). Vazio
# (padrão) = comportamento de sempre, lendo projectile_texture como tira.
@export var projectile_frames: Array[Texture2D] = []

# true = a arte do projétil (projectile_texture OU projectile_frames) foi
# desenhada olhando pra DIREITA, então o projétil precisa girar (ver
# Projectile.launch()) pra apontar de verdade na direção que está viajando
# na tela. false (padrão) = arte omnidirecional (ex: Ember, Powder Snow —
# uma bola/nuvem que fica igual em qualquer ângulo), sem rotação nenhuma —
# preserva o visual de todo projétil já existente antes deste campo existir.
@export var projectile_faces_right: bool = false

# Sprite do "efeito de impacto": mesma ideia do projectile_texture (tira
# horizontal de quadros quadrados), mas tocado PARADO em cima do alvo no
# instante em que o golpe acerta, em vez de viajar até lá (ver
# ImpactEffect.play() e battle.gd::execute_attack). Opcional pra qualquer
# ataque, físico ou especial — ex: Vine Whip usa os dois campos: o "chicote"
# (projectile_texture) viajando até o alvo, e um efeito de folhas/estrelas
# (impact_texture) no ponto do impacto.
@export var impact_texture: Texture2D

# Alternativa a impact_texture pra quando a arte do impacto vem como VÁRIOS
# arquivos separados (um por quadro), em vez de uma tira horizontal só — ex:
# Confusion (13 arquivos, 000.png a 024.png). Mesma relação que
# projectile_frames tem com projectile_texture (ver comentário lá): se
# preenchido (não vazio), tem prioridade sobre impact_texture pra CAMADA 1 —
# cada Texture2D aqui é usado INTEIRO como um quadro, sem corte de atlas (ver
# ImpactEffect.play()/_process()). Vazio (padrão) = comportamento de sempre,
# lendo impact_texture como tira.
@export var impact_frames: Array[Texture2D] = []

# Segunda CAMADA de impacto, tocada ao mesmo tempo que impact_texture,
# sobreposta no mesmo ponto (ver ImpactEffect.play()/_process()) — pra golpes
# cuja arte de impacto vem em duas peças separadas em vez de uma tira só. Ex:
# Ice Fang combina Ice_Fang_Fang.None.png (a "mordida") com
# Ice_Fang_Hit.None.png (cacos de gelo espalhando) — as duas tiras tocam
# juntas, cada uma no seu próprio ritmo, e o efeito inteiro só termina quando
# AMBAS chegarem no último quadro. "" (null, padrão) = sem segunda camada,
# comportamento idêntico a antes (só impact_texture).
@export var impact_texture_2: Texture2D

# Sprite do "efeito de cast": diferente de projectile_texture/impact_texture
# (que tocam viajando até o alvo ou parados EM CIMA do alvo), esse toca
# parado em cima de QUEM ATACA — a arte que sai do próprio usuário do golpe,
# ex: a onda sonora do Growl (ver CastEffect.play()/scripts/cast_effect.gd).
# Formato bem diferente dos outros dois: não é uma tira horizontal só, é uma
# GRADE — 8 colunas (uma por direção, sentido HORÁRIO a partir de "down",
# ver CastEffect.DIRECTION_COLUMNS — reparar que é o sentido CONTRÁRIO da
# ordem usada nas sprites de personagem/Pokémon) x 6 linhas (os quadros da
# animação dentro de cada direção). null (padrão) = sem cast effect nenhum.
@export var cast_frames_by_direction: Texture2D

# ---------- Efeito secundário ----------
# "" = sem efeito secundário. Vocabulário igual Unit.status_conditions (ex:
# "Burned", "Poisoned"...). Só é testado se o golpe causou dano de verdade e
# o alvo sobreviveu — ver battle.gd::execute_attack. Como
# Unit.apply_status_condition() já se recusa sozinha a sobrescrever uma
# condição existente, não precisa checar isso aqui: o roll pode "acertar" e
# mesmo assim não fazer efeito nenhum, sem problema.
@export var secondary_status: String = ""

# Chance (0.0 a 1.0) de secondary_status ser aplicado quando o golpe acerta.
# Ex: Ember = 0.1 (10% de queimar).
@export_range(0.0, 1.0) var secondary_status_chance: float = 0.0

# Animação tocada em cima do ALVO (mesmo mecanismo do impact_texture — ver
# comentário lá, e ImpactEffect.play()), mas só quando secondary_status
# realmente "pegou" (não a cada golpe, como impact_texture) — ex: Ember só
# mostra o efeito de fogo quando o alvo é queimado de verdade, não em todo
# golpe que acerta.
@export var secondary_status_texture: Texture2D

# Segundo efeito secundário, rolado de forma TOTALMENTE INDEPENDENTE do
# primeiro (mesma regra: só tenta se o golpe acertou e o alvo sobreviveu, ver
# battle.gd::execute_attack/_try_apply_secondary_status) — pensado pra golpes
# que têm DOIS efeitos ao mesmo tempo, cada um com sua própria chance. Ex:
# Ice Fang de verdade: 10% de congelar E, numa rolagem separada, 10% de
# Flinch (podem acontecer as duas juntas, nenhuma, ou só uma). "" (padrão) =
# sem segundo efeito — a maioria dos ataques só usa o primeiro conjunto
# acima. Se um dia um golpe precisar de um TERCEIRO efeito independente,
# talvez valha a pena virar um Array[Resource] em vez de continuar
# duplicando campos — com só dois casos (o de cima e este), a duplicação
# ainda é mais simples de ler.
@export var secondary_status_2: String = ""
@export_range(0.0, 1.0) var secondary_status_chance_2: float = 0.0
@export var secondary_status_texture_2: Texture2D

# ---------- Efeito secundário: boost de stat no PRÓPRIO ATACANTE ----------
# Diferente de secondary_status/_2 acima (que miram o DEFENSOR), este mira
# QUEM ATACA — ex: Ancient Power, que tem chance de subir TODOS os 5 stats
# (Unit.STAGE_STATS) do usuário em +1 estágio cada, ao mesmo tempo que causa
# dano normal no alvo (por isso não reaproveita stat_change_stat/_amount lá
# em cima — aqueles só rodam em ataques de Status, via
# execute_status_attack, que nunca causam dano; este roda em ataques COM
# dano, via execute_attack, e sempre afeta os 5 stats juntos, não 1 só).
# Rolado de forma independente do(s) secondary_status acima e cancelado por
# Sheer Force igual eles (ver battle.gd::has_sheer_force/
# _try_apply_self_stat_boost). 0.0 = sem esse efeito.
@export_range(0.0, 1.0) var self_stat_boost_chance: float = 0.0

# Quanto sobe CADA UM dos 5 stats quando o roll acima acerta — 0 (padrão) =
# sem efeito, mesmo com self_stat_boost_chance > 0.
@export var self_stat_boost_amount: int = 0

# ---------- Efeito secundário: muda 1 stat do DEFENSOR, com % de chance ----------
# Rock Smash é o primeiro caso: "50% chance to lower Defense" (pedido do
# usuário, "same as bite" só confirmou reaproveitar o número exato da série
# principal). Três variantes de "stat muda por causa de um ataque" já
# existiam e NENHUMA cobria isso: stat_change_stat/_amount/_target lá em
# cima é SEMPRE garantido, sem chance (Growl/Flame Charge); self_stat_boost_
# chance/_amount sobe os 5 stats JUNTOS, sempre no próprio ATACANTE (Ancient
# Power). Este aqui é o terceiro caso que faltava: 1 stat só, com %, no
# DEFENSOR — mesmo texto/vocabulário de stat (ver STAT_DISPLAY_NAMES em
# battle.gd), amount negativo pra abaixar (Rock Smash: -1) ou positivo pra
# subir, se algum golpe futuro precisar do inverso. "" (padrão) = sem esse
# efeito. Rolado de forma independente de secondary_status/_2 (mesmo
# espírito de Ice Fang ter dois rolls próprios) e cancelado por Sheer Force
# igual eles (ver battle.gd::has_sheer_force/_try_apply_secondary_stat_change
# — chamado no mesmo bloco `if not has_sheer_force(attacker)` que já protege
# secondary_status).
@export var secondary_stat_change_stat: String = ""
@export var secondary_stat_change_amount: int = 0
@export_range(0.0, 1.0) var secondary_stat_change_chance: float = 0.0

# ---------- Recoil (dano no próprio atacante) ----------
# Fração do PRÓPRIO hp_max (não do dano causado, nem do hp_current) que quem
# usa esse ataque perde, SEMPRE que o golpe acerta e causa dano de verdade —
# ver battle.gd::execute_attack, aplicado depois do dano no defensor e dos
# efeitos secundários. 0.0 (padrão) = sem recoil nenhum, comportamento igual
# a antes desse campo existir. Struggle é o primeiro caso: 0.25 (perde 25%
# do próprio hp_max) — mesma convenção da série principal (fração do hp_max,
# não do dano causado, e SEM checar Rock Head ou qualquer outra Habilidade
# que algum dia venha a cancelar recoil, já que nenhuma existe ainda).
@export_range(0.0, 1.0) var self_max_hp_recoil_fraction: float = 0.0

# Fração do DANO CAUSADO (não do próprio hp_max, diferente do campo acima —
# os dois são mutuamente exclusivos na prática, nenhum golpe hoje usa os
# dois juntos) que quem ataca perde de recoil. Double-Edge é o primeiro
# caso: "user takes 1/3 of DAMAGE DEALT as recoil" (pedido explícito do
# usuário — Struggle usava a aproximação de cima, fração do hp_max, porque
# Struggle não causa dano de verdade a ninguém específico; Double-Edge causa
# dano real, então usa a fração do dano de verdade em vez de aproximar).
# 0.0 (padrão) = sem esse tipo de recoil. Ver battle.gd::execute_attack/
# execute_attack_burst (nesse último, soma o dano de TODOS os alvos
# atingidos antes de aplicar a fração, ver comentário lá).
@export_range(0.0, 1.0) var self_recoil_fraction_of_damage_dealt: float = 0.0

# ---------- Escala com uso consecutivo (ex: Rollout) ----------
# true = power/range deste ataque NÃO são os campos `power`/`range` fixos lá
# em cima — em vez disso, escalam com Unit.consecutive_attack_uses (ver
# comentário grande lá e battle.gd::_track_attack_use/get_effective_power/
# get_effective_attack_range). Rollout é o primeiro caso, pedido do usuário:
# "we won't lock the user into only using Rollout" (usar OUTRO ataque no
# meio reseta a sequência de volta pra 1, mas nada impede) + "It starts at
# 30 base power and 1 range, then double the power and increase the range
# by 1 for each consecutive usage, capping the max power at 480 power and 5
# range" + "If that unit has used Defense Curl during any time this combat,
# the base power starts at 60 ... Capping the max power at 960 power".
@export var scales_with_consecutive_use: bool = false

# Power/cap "normais" (sem o pré-requisito abaixo) — Nª uso consecutivo =
# min(consecutive_use_max_power, consecutive_use_base_power * 2^(N-1)).
@export var consecutive_use_base_power: int = 0
@export var consecutive_use_max_power: int = 0

# AttackData que, se já tiver sido usado QUALQUER hora nesta batalha (ver
# Unit.used_attacks_this_battle — não precisa ser IMEDIATAMENTE antes, nem
# consecutivo com nada), troca a base/cap de power pros dois campos
# _boosted_ abaixo em vez dos normais acima. null (padrão) = sem pré-
# requisito nenhum, sempre usa base/cap normais. Defense Curl é o primeiro
# caso, referenciado pelo próprio Resource (mesmo padrão de EvolutionOption.
# requires_action/target — comparação por IDENTIDADE do Resource, não nome).
@export var consecutive_use_boost_prerequisite: AttackData = null
@export var consecutive_use_boosted_base_power: int = 0
@export var consecutive_use_boosted_max_power: int = 0

# Teto do RANGE (o range em si é sempre = Nº do uso consecutivo, começando
# em 1 — sem "boosted" separado pro range, só o power tem essa variante,
# pedido do usuário deixa isso explícito: "Capping the max power at 960
# power and 5 range" pro caso boosted, MESMO 5 do caso normal).
@export var consecutive_use_max_range: int = 0

# ---------- Área em anel (ex: Eruption) ----------
# 0 (padrão) = área começa bem no centro (attacker.grid_pos), igual sempre.
# > 0 = exclui qualquer célula com distância MENOR que isso — só importa pra
# area_shape == "Burst" (ver battle.gd::execute_attack_burst). Eruption é o
# primeiro caso: "hits all units on a 3 to 5 range from the user, doesnt hit
# units up to 2 range" — range=5 (teto de sempre) + area_min_range=3 formam
# um ANEL em vez de um círculo cheio.
@export var area_min_range: int = 0

# true = power NÃO é o campo `power` fixo lá em cima — escala com o HP
# ATUAL de quem ataca, formula (ver battle.gd::get_effective_power):
# power = attack.power * (hp_current / hp_max) de quem ataca, arredondado,
# mínimo 1. Eruption é o primeiro caso: "Base power = 150 x CurrentHP/Max
# HP" (pedido do usuário) — `power` acima guarda o 150 (o "100% de HP"), a
# escala de verdade acontece em runtime.
@export var power_scales_with_own_hp: bool = false

# true = power escala com a RAZÃO de Speed entre alvo e quem ataca (ver
# battle.gd::get_effective_power) — power = min(
# power_scales_with_speed_ratio_cap, attack.power * defender.Speed /
# attacker.Speed), Speed já com estágio alterado (Unit.get_effective_stat).
# Gyro Ball é o primeiro caso: "Base power: 25 x target speed/user speed,
# capped at 150" (pedido do usuário) — `power` acima guarda o 25 (o
# multiplicador-base), power_scales_with_speed_ratio_cap guarda o teto (150).
# Diferente de power_scales_with_own_hp/scales_with_consecutive_use (que só
# olham pra quem ataca), este é o primeiro a precisar do DEFENSOR também —
# por isso get_effective_power() ganhou um terceiro parâmetro (defender,
# opcional/null) só pra este caso.
@export var power_scales_with_speed_ratio: bool = false
@export var power_scales_with_speed_ratio_cap: int = 0

# "" (padrão) = sem esse efeito. Nome de uma Status Condition (vocabulário
# igual Unit.status_conditions/AttackData.secondary_status) — se o ALVO
# tiver EXATAMENTE essa condição no momento do golpe, power dobra (ver
# battle.gd::get_effective_power). Infernal Parade é o primeiro caso: "add
# the burn chance and conditional doubling if the target is BURNED exactly"
# (pedido do usuário — só Burned conta, não qualquer Status Condition).
@export var power_doubles_if_target_has_status: String = ""

# false (padrão) = power nunca muda por causa do clima. true = Solar Beam é
# o primeiro caso — pedido do usuário (2026-07-23): "Solar Beam's power
# needs to be halved during Sand, Rain and Snow". Deliberadamente só essas
# TRÊS (ver battle.gd::get_effective_power) — Sunny/Harsh Sunlight (o golpe
# já dispara na hora nesses dois, ver AttackData.instant_in_sun) e o clima
# NEUTRO (WEATHER_NONE) continuam com o power cheio, e Heavy Rain/Strong
# Winds ficaram de fora por não terem sido citados — decisão minha, não
# confirmada com o Rodrigo, revisar se algum dia isso importar. Nome
# diferente de propósito do "bad weather" de Synthesis (self_heal_fraction_
# in_bad_weather) — lá "ruim" significa QUALQUER clima fora do baseline,
# aqui significa só estes três nomeados, escopos diferentes que não devem
# se confundir.
@export var power_halved_in_rain_sand_snow: bool = false

# -1.0 (padrão) = usa a chance de Acerto Crítico GLOBAL de sempre (ver
# battle.gd::CRITICAL_HIT_CHANCE, 1/16 = 6.25%). >= 0.0 = SUBSTITUI a chance
# global por este valor exato só pra este golpe — Razor Leaf é o primeiro
# caso: "increased critical hit chance (12,5% base chance to crit)" (pedido
# do usuário), 12.5% = exatamente o dobro do padrão, mesma proporção da
# "alta chance de crítico" da série principal, só que aqui como um número
# fixo em vez de um "+1 estágio de crítico" (não existe estágio de crítico
# neste projeto). Reaproveitável por qualquer golpe futuro de alta-crítico
# (Slash, Karate Chop, Crabhammer, etc.) sem precisar de campo novo.
@export var crit_chance_override: float = -1.0

# ---------- Golpes de carga ("2 Action Point moves") ----------
# false (padrão) = golpe normal, dispara assim que usado (todo golpe até
# agora). true = Solar Beam é o primeiro caso — pedido do usuário (2026-07-23):
# "Solar Beam charges and consumes 1 action point. Then, as soon as the unit
# has another action point, it fires". Ou seja, o USO em si (ver
# battle.gd::execute_charge_attack) só gasta 1 ação e guarda o golpe/direção
# em Unit.charging_attack/charging_dir — NENHUM dano acontece nessa hora. O
# disparo de verdade só roda no PRÓXIMO Action Point que essa unidade
# receber (ver begin_current_turn, checado logo depois de calcular
# attacks_remaining do turno — "as soon as the unit has another action
# point" quase sempre = "no começo do próximo turno dela", já que a maioria
# das unidades só recebe 1 Action Point por turno; a exceção rara seria uma
# unidade com Chlorophyll ainda tendo 1 AP sobrando no MESMO turno que
# carregou, mas isso não é possível pra Solar Beam especificamente porque
# instant_in_sun abaixo já dispara na hora sempre que há Chlorophyll ativo
# de qualquer jeito, os dois dependendo do mesmo clima de Sol).
#
# Se a unidade ficar travada (Frozen/Asleep/paralisia total) bem no turno em
# que deveria disparar, o golpe carregado simplesmente continua esperando
# pro turno seguinte (attacks_remaining vem 0 nesse caso, então
# begin_current_turn não tenta disparar) — decisão minha, não confirmada
# com o Rodrigo; a série principal tem regras mais específicas pra isso,
# revisar se algum dia importar.
@export var is_charge_move: bool = false

# false (padrão) = sempre carrega primeiro (1 turno) antes de disparar no
# seguinte, nunca instantâneo. true = Solar Beam de novo — pedido do
# usuário: "During Sun weather, it requires 1 fewer action point, so it will
# activate instantly" — ou seja, com Sunny/Harsh Sunlight ativo (ver
# battle.gd::is_sun_weather), o golpe pula a fase de carga inteira e
# dispara na hora, igual qualquer golpe normal (só importa se is_charge_move
# também for true — sem carga nenhuma, este campo não faz nada).
@export var instant_in_sun: bool = false

# Golpes de RECARGA (Giga Impact/Hyper Beam/Blast Burn — pedido do usuário,
# "future moves... They come out when used, but consume the next action
# point the unit would have") são o OPOSTO deste mecanismo: disparam na
# HORA (sem fase de carga), só que "gastam" o PRÓXIMO Action Point da
# unidade depois de disparar (turno de recarga, sem poder agir). Ainda não
# implementado — nenhum golpe da Bulbasaur/Ivysaur/Venusaur usa isso, só
# fica documentado aqui pra quando chegar a hora de um golpe assim de
# verdade (Groundwork, mesmo espírito de outros campos "ainda não lidos em
# lugar nenhum" deste arquivo).

# ---------- Tags ----------
# Rótulos livres pra agrupar ataques por CATEGORIA além do element_type — ex:
# "Wind" (Powder Snow), pra futuras interações que dependam de "isso é um
# golpe de vento", não de um tipo elemental específico (ex: uma Habilidade
# que bloqueia golpes de vento, independente do tipo ser Ice/Flying/Normal).
# Groundwork: nenhum código ainda lê isso, mesma ideia de area_of_effect
# acima — existe só pra já vir documentado nos dados do ataque.
@export var tags: Array[String] = []

# ---------- Roubo de Berry (ex: Bug Bite) ----------
# true = ao acertar um alvo que sobreviveu ao golpe, se esse alvo carregar
# QUALQUER ItemData category=="Berry" equipado no loadout, quem ATACA rouba e
# consome ela na hora (mesmo efeito que o alvo teria — hoje só existe cura via
# ItemData.heal_amount, ver Oran Berry — mas o mecanismo lê qualquer efeito de
# Berry que já exista, sem precisar de campo novo se uma Berry futura tiver
# outro efeito além de cura). Se o alvo carregar MAIS de uma Berry ao mesmo
# tempo, sorteia UMA aleatória entre elas (pedido do usuário, Bug Bite: "If
# there are more than one berry, consume a random one"). false (padrão) = sem
# esse efeito, golpe comum. Ver battle.gd::_try_bug_bite_steal_berry.
@export var steals_target_berry: bool = false

# ---------- Empurrão (ex: Whirlwind) ----------
# true = este golpe de Status NÃO aplica stat/status/clima nenhum — em vez
# disso, empurra cada unidade encontrada na área (ver battle.gd::
# execute_whirlwind_push) `5 - peso_da_unidade` tiles na MESMA direção mirada
# (pedido do usuário, Whirlwind: "Pushes all units in rock slide range (3
# tiles range 1) a number of tiles equal to 5-target's weight"). Reaproveita
# a geometria "Wide" de area_shape (mesma de Rock Slide) pra achar quem é
# empurrado, mas SEM o filtro "só inimigo" que Cone/Burst/projétil usam em
# execute_status_attack normalmente — Whirlwind empurra TODO MUNDO (aliado E
# inimigo) na área, mesma regra de "sem isenção de fogo amigo" que toda área de
# dano (Cone/Burst/Line/Wide) já segue. Se o empurrão esbarrar em parede/borda
# ou outra unidade no meio do caminho, para ali e causa dano (ver comentário
# grande de execute_whirlwind_push pras regras exatas de colisão). false
# (padrão) = golpe de Status comum, sem empurrão nenhum.
@export var push_mechanic: bool = false
