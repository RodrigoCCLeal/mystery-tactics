extends "res://scripts/npc.gd"

# Merchant — segundo skeleton de NPC do jogo (depois de Nurse), pra lojas
# que compram/vendem itens (pedido do usuário: roster de NPCs #1 Merchant,
# #2 Trainer, #3 Gift, #4 Transporter — só este está implementado por
# enquanto). Herda aparência/posição/face_towards de npc.gd, igual nurse.gd;
# só sobrescreve interact() e adiciona os campos de loja abaixo.
#
# Cada instância de Merchant tem SEU PRÓPRIO estoque (stock, ver
# merchant_stock_entry.gd) — dois Merchants podem vender itens diferentes,
# ou o mesmo item com estoques diferentes, sem duplicar nenhum script.
# Preço de compra/venda vem de ItemData.buy_price/sell_price (mesmo em
# qualquer loja); só a QUANTIDADE em estoque é por-Merchant.

const MERCHANT_MENU_SCENE: PackedScene = preload("res://scenes/ui/screens/merchant_menu.tscn")

@export var shop_name: String = "Loja"
@export var stock: Array[MerchantStockEntry] = []

func interact() -> void:
	var menu = MERCHANT_MENU_SCENE.instantiate()
	add_child(menu)
	menu.setup(shop_name, self)
	menu.closed.connect(_on_menu_closed)
	get_tree().paused = true

func _on_menu_closed() -> void:
	get_tree().paused = false
