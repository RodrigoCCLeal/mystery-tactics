class_name ActionData
extends Resource

# Base pra qualquer coisa que ocupa um dos 6 slots de ação de uma unidade:
# Ataque, Habilidade ou Item. Por enquanto só AttackData existe (veja
# attack_data.gd) — Ability/Item viram novas subclasses depois, do mesmo jeito.
#
# O "loadout" (quais 6 ActionData cada personagem carrega) fica em
# UnitData.slots. Pode ser trocado fora de batalha (equipar/desequipar num
# menu futuro) — dentro de uma batalha em andamento, fica travado.

@export var action_name: String = ""

# Contador de usos (atual/máximo) é OPCIONAL e genérico pra qualquer
# ActionData — não é exclusivo de ataque. Convenção: -1 = sem contador (a
# ação é "passiva"/ilimitada, não gasta uso). Ataques sempre definem um valor
# >0 aqui (todo ataque tem uso limitado); Habilidade e a maioria dos Itens
# devem deixar no padrão -1; só itens específicos (ex: uma poção com 3 cargas)
# definem um valor >0. Fica aqui na base, não em AttackData, justamente pra
# não precisar checar o tipo da ação (is AttackData) toda vez — ver
# Unit.slot_uses / Unit._apply_common().
@export var max_uses: int = -1

# Alcance em distância Chebyshev (igual ao movimento — diagonal conta como 1,
# as 8 direções valem o mesmo). Pro caso normal (AttackData.is_projectile
# falso, que é a maioria) é a distância EXATA, não "até" — range=1 só acerta
# tiles a exatamente 1 de distância (nunca os pés da própria unidade,
# distância 0). Isso importa pro futuro: dá pra ter ataque de alcance mínimo
# (ex: uma lança que só acerta longe, não corpo a corpo) sem precisar de um
# campo separado. Já pra ataques-projétil (AttackData.is_projectile = true),
# range vira o alcance MÁXIMO em linha reta — ver comentário lá. Genérico
# aqui na base pela mesma razão de max_uses: ataque sempre usa isso, mas
# item/habilidade também podem precisar, então não faz sentido só em
# AttackData.
@export var range: int = 1
