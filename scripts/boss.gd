class_name Boss
extends "res://scripts/npc.gd"

# Quarto skeleton de NPC do jogo, depois de Nurse/Merchant/Trainer — um
# chefe do overworld (Suicune é o primeiro, ver data/units/0245.tres).
# Pedido do usuário: "Boss battles are against wild pokémon, so the player
# CAN catch them, but they don't happen as wild encounters, only as
# events... We will need a Suicune NPC". Por baixo, uma batalha de chefe é
# bem mais parecida com uma batalha SELVAGEM do que com uma de Trainer (ver
# GameState.is_boss_battle/is_trainer_battle, battle.gd::resolve_capture) —
# só o "quem spawna" muda (um time fixo, não sorteado de EncounterArea).
#
# Comportamento de avistamento escolhido com o usuário: Talker puro (nunca
# anda/persegue sozinho, só abre a batalha quando o jogador interage) — por
# isso Boss estende Npc diretamente (não Trainer): toda a maquinaria de
# Spot Behavior/perseguição/patrulha/tiers de time por badge do Trainer não
# faz sentido nenhum pra um chefe parado esperando um evento. Herda
# aparência/grid/face_towards de npc.gd; só sprite (ver Npc.sheet, aponte
# pra assets/sprites/Boss/SUICUNE.png no Inspector) + as duas funções logo
# abaixo (interact/_begin_battle) precisam existir aqui.

# Único por INSTÂNCIA — mesmo papel de Trainer.trainer_id, mas SEM regra de
# "não força revanche depois de derrotado" nenhuma ainda (ver comentário
# grande de _begin_battle logo abaixo: capturar OU não capturar um chefe e
# poder desafiá-lo de novo depois é uma decisão de design que o usuário
# ainda não tomou — deixado como reinteração livre de propósito, em vez de
# adivinhar uma regra de "só uma vez" que ninguém pediu).
@export var boss_id: String = ""

# Mesmo papel de Trainer.spotted_message — mostrado na caixa de texto antes
# da batalha abrir de verdade.
@export var spotted_message: String = "..."

# Nível de IA que este chefe usa em batalha — mesmo papel de Trainer.iq (ver
# comentário grande lá), copiado pra GameState.current_boss_iq em
# world.gd::start_boss_battle() e aplicado em battle.gd::_spawn_enemy_unit(),
# mesmo ponto que já sobrescreve o iq de um time de Trainer. SEM "Rocket"
# aqui de propósito — esse tier vem com regras exclusivas de Trainer (Rocket
# Ball automática no loadout, "vanish" permanente depois da batalha, ver
# trainer.gd/battle.gd::spawn_enemies) que não fazem sentido nenhum pra um
# chefe. Pedido do usuário: "We also need an IQ value for bosses, default
# is Medium" — mesmo padrão/mesmo default de Trainer.
@export_enum("Easy", "Medium", "Hard", "Champion") var iq: String = "Medium"

# Espécie + nível + loadout deste chefe — reaproveita TrainerTeamEntry (ver
# comentário grande em GameState.current_boss_entry) em vez de 3 campos
# soltos aqui. loadout NÃO deveria ficar vazio pra um chefe de verdade (ver
# LearnsetEntry.is_boss_ability — só forced_loadout garante a Habilidade de
# Chefe equipada; o sorteio automático de get_recent_loadout() nunca a
# escolhe, ver UnitData._pick_random_ability).
@export var boss_entry: TrainerTeamEntry

@export_group("Mapa (ver GameState.generated_map/forced_battle_tileset)")
# Mesmo checkbox pedido pelo usuário pra Trainer (ver trainer.gd) — true
# (padrão) = mapa procedural de sempre. false = usa manual_map abaixo (ver
# nota de limitação conhecida em GameState.manual_map: o carregamento de
# verdade ainda não existe, só o campo).
@export var generated_map: bool = true
@export var manual_map: PackedScene = null
# Northwind Field é o primeiro caso (ver data/battle_tilesets/
# northwind_field.tres) — null = sorteia entre os 3 tilesets normalmente,
# igual qualquer batalha selvagem/Trainer.
@export var forced_battle_tileset: BattleTileset = null

const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")

# X de frente pro Boss (mesmo caminho de qualquer Npc, ver world.gd::
# _try_interact) — abre a mesma caixa de texto que Trainer usa antes de
# batalhar, só que sem exclamação/perseguição nenhuma (Talker puro, nunca
# avista o jogador sozinho).
func interact() -> void:
	get_tree().paused = true
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(spotted_message)
	box.closed.connect(_begin_battle)

# Abre a batalha de verdade — delegado pro "world" (mesmo padrão de
# Trainer._begin_battle/Door.use_door), que sabe salvar a posição do
# jogador e trocar de cena.
#
# NOTA (decisão de design ainda em aberto, documentada em vez de adivinhada
# — ver [[feedback_ask_dont_approximate]]): diferente de Trainer, este
# script não marca "já derrotado" nem "já vanished" em lugar nenhum — o
# jogador pode interagir com este Boss quantas vezes quiser, mesmo depois
# de já ter capturado a unidade uma vez (uma nova cópia idêntica spawnaria
# de novo). Perguntar ao usuário quando for hora de decidir a regra real
# (some pra sempre depois de capturado? Depois de vencido, capturado ou
# não? Permite revanche sempre?) em vez de travar esse comportamento agora
# sem ele ter pedido nada específico sobre isso.
func _begin_battle() -> void:
	world.start_boss_battle(self)
