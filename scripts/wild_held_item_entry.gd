class_name WildHeldItemEntry
extends Resource

# Um par (item, chance) dentro de UnitData.wild_held_items — "essa espécie
# selvagem tem `chance` de probabilidade de nascer segurando `item`". Dados
# vindos do PokeMMO (rarity média entre as versões, já convertida de 0-100
# pra 0.0-1.0 aqui). Mora num Resource dedicado (em vez de dois Arrays
# paralelos em UnitData) pelo mesmo motivo de LearnsetEntry: mais fácil de
# ler/editar no Inspector do que dois arrays sincronizados por índice.
#
# UnitData._pick_random_held_item() percorre esta lista fazendo um sorteio
# cumulativo (mesmo padrão de _pick_random_ability): rola um float 0.0-1.0
# e soma as chances em ordem até passar do valor sorteado — a "sobra" (1.0
# menos a soma de todas as chances) é implicitamente "nenhum item", por
# isso a maioria das espécies (chances baixas, tipicamente 1-10%) fica sem
# item na maior parte das vezes, exatamente como pedido: "supposed to be
# empty most of the time, but will have a random chance of containing an
# item, also following the Pokemmo data".
@export var item: ItemData
@export_range(0.0, 1.0) var chance: float = 0.0
