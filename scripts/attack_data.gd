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

# 0 = sem dano direto (ex: ataque que só aplica um efeito/status, sem golpe).
@export var power: int = 0

# Quantos tiles o golpe atinge a partir do alvo (1 = só o próprio tile
# mirado, sem "espirrar" pros vizinhos). Groundwork: nenhum código ainda lê
# isso pra causar dano em mais de um tile — hoje todo ataque (mesmo os com
# area_of_effect > 1 aqui, se algum vier a ter) só afeta o alvo resolvido
# normalmente (ver battle.gd::execute_attack). Existe agora só pra já vir
# documentado nos dados do ataque (ex: Confusion = 1).
@export var area_of_effect: int = 1

# Formato da área atingida — só importa pra ataques de STATUS (is_status
# true) por enquanto; ataques com dano continuam mirando 1 alvo só (ver
# comentário de area_of_effect acima, ainda groundwork pra esses).
# "Single" (padrão) = mira 1 alvo só, igual todo ataque de sempre.
# "Cone" = abre um leque a partir de quem ataca, na direção mirada, até
# `range` tiles de distância — atinge TODOS os inimigos dentro do leque de
# uma vez (ver battle.gd::get_cone_cells/execute_status_attack). Growl é o
# primeiro caso: range=3, Cone, atinge todo inimigo na área.
@export_enum("Single", "Cone") var area_shape: String = "Single"

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
# "" = sem efeito secundário. Vocabulário igual Unit.status_condition (ex:
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

# ---------- Tags ----------
# Rótulos livres pra agrupar ataques por CATEGORIA além do element_type — ex:
# "Wind" (Powder Snow), pra futuras interações que dependam de "isso é um
# golpe de vento", não de um tipo elemental específico (ex: uma Habilidade
# que bloqueia golpes de vento, independente do tipo ser Ice/Flying/Normal).
# Groundwork: nenhum código ainda lê isso, mesma ideia de area_of_effect
# acima — existe só pra já vir documentado nos dados do ataque.
@export var tags: Array[String] = []
