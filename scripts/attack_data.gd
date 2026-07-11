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

# Chance de acerto (1.0 = 100%). Nenhum lugar em battle.gd ainda faz um roll
# de acerto de verdade — todo ataque implementado até agora sempre acerta,
# então este campo ainda não muda comportamento nenhum. Existe agora porque
# ItemData.accuracy_multiplier (ex: Focus Band) já precisa de ALGO pra
# multiplicar (ver Unit.get_accuracy_multiplier) — quando o roll de acerto
# for implementado de verdade, ele deve usar accuracy * essa multiplicação.
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

# Sprite do "efeito de impacto": mesma ideia do projectile_texture (tira
# horizontal de quadros quadrados), mas tocado PARADO em cima do alvo no
# instante em que o golpe acerta, em vez de viajar até lá (ver
# ImpactEffect.play() e battle.gd::execute_attack). Opcional pra qualquer
# ataque, físico ou especial — ex: Vine Whip usa os dois campos: o "chicote"
# (projectile_texture) viajando até o alvo, e um efeito de folhas/estrelas
# (impact_texture) no ponto do impacto.
@export var impact_texture: Texture2D

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

# ---------- Tags ----------
# Rótulos livres pra agrupar ataques por CATEGORIA além do element_type — ex:
# "Wind" (Powder Snow), pra futuras interações que dependam de "isso é um
# golpe de vento", não de um tipo elemental específico (ex: uma Habilidade
# que bloqueia golpes de vento, independente do tipo ser Ice/Flying/Normal).
# Groundwork: nenhum código ainda lê isso, mesma ideia de area_of_effect
# acima — existe só pra já vir documentado nos dados do ataque.
@export var tags: Array[String] = []
