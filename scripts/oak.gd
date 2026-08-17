extends "res://scripts/npc.gd"

# Professor Oak (laboratório de Archis, ver oak_lab_interior.tscn) — pedido
# do usuário (2026-08-04): "Stops the player from leaving Archis town the
# first time they try to, if the 'chose a starter' flag is negative, then
# teleports the player to his lab. If the player tries to leave the lab
# without choosing a starter, Oak will stop them aswell."
#
# As DUAS travas ("sair de Archis" via mato alto/Barias, ver world.gd::
# _on_player_tile_entered/_block_leaving_without_starter, e "sair do
# laboratório", ver oak_lab_interior.tscn::Door_town/Door_grass) são
# inteiramente guiadas por dado (GameState.get_flag("STARTER1_CHOSEN"),
# mesma flag que os 3 StarterX/loot_ball.gd já usam como exclusive_flag) —
# nenhuma das duas precisa de código bespoke aqui, diferente de Mom (que dá
# dinheiro ao bloquear, ver mom.gd). Este script só cobre a PARTE
# "personagem": uma linha de diálogo curta ao interagir com ele de frente,
# parado do lado das 3 LootBalls dos starters.

const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")
const POKEBALL_ITEM: ItemData = preload("res://data/items/pokeball.tres")

# Pedido do usuário (2026-08-04): "When talked to the first time after
# getting the starter, Oak will give the player 5 Pokéballs" — terceira
# camada de diálogo, só depois de STARTER1_CHOSEN já estar true (mesma flag
# de sempre) e só na PRIMEIRA vez (POKEBALL_GIFT_FLAG, mesmo padrão do
# GIFT_FLAG de mom.gd: uma flag nova, dedicada, marcada assim que o presente
# é dado, pra nunca repetir).
const POKEBALL_GIFT_AMOUNT = 5
const POKEBALL_GIFT_FLAG = "oak_gave_pokeballs"

func interact() -> void:
	get_tree().paused = true
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	# Ordem importa: só entra aqui com starter já escolhido E ainda sem ter
	# recebido as bolas — dá o item/marca a flag ANTES de montar a caixa,
	# pra _message() (chamada por _give_pokeballs_message logo abaixo) já
	# poder descrever o presente que acabou de entrar no inventário.
	if GameState.get_flag("STARTER1_CHOSEN") and not GameState.get_flag(POKEBALL_GIFT_FLAG):
		GameState.add_item(POKEBALL_ITEM, POKEBALL_GIFT_AMOUNT)
		GameState.set_flag(POKEBALL_GIFT_FLAG)
		box.setup("Here, take these! Every Trainer needs a few Poké Balls of their own. You received %d Poké Balls!" % POKEBALL_GIFT_AMOUNT)
	else:
		box.setup(_message())
	box.closed.connect(func(): get_tree().paused = false)

# Antes de escolher: aponta pras bolinhas. Depois (já com as Poké Balls
# entregues, ver interact() acima): só uma linha genérica de boa sorte —
# mesma flag (STARTER1_CHOSEN) que já trava as portas.
func _message() -> String:
	if GameState.get_flag("STARTER1_CHOSEN"):
		return "Take good care of your partner out there!"
	return "Go on, take a look! Choose whichever partner speaks to you."
