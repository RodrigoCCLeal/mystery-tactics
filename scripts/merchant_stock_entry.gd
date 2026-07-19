class_name MerchantStockEntry
extends Resource

# UMA linha do estoque de um Merchant (ver merchant.gd) — qual item, e
# quantas unidades esse Merchant especificamente ainda tem pra vender.
# Mesmo espírito de EncounterEntry (espécie + nível, ver encounter_entry.gd):
# um Resource pequeno que vira um array editável no Inspector, sem precisar
# de cena nenhuma pra representar "uma entrada de uma lista".
#
# Preço de compra/venda NÃO mora aqui — isso é ItemData.buy_price/
# sell_price (o mesmo preço em qualquer loja, ver comentário lá). Este
# Resource só controla ESTOQUE, que é por-loja.

@export var item: ItemData

# -1 (padrão) = estoque infinito, nunca esgota (pedido do usuário: "The
# default is having infinite items, but I will state otherwise when
# needed"). Qualquer valor >= 0 é a quantidade EXATA que resta — cai pra 0
# conforme o jogador compra (ver merchant_buy_screen.gd), e chegando a 0 o
# item some da lista de compra (mas continua vendável de volta pro
# Merchant... não, Sell não lê o estoque do Merchant, só o inventário do
# jogador — ver merchant_sell_screen.gd).
@export var quantity: int = -1

func is_infinite() -> bool:
	return quantity == -1

func is_in_stock() -> bool:
	return is_infinite() or quantity > 0
