class_name TrainerClassData
extends RefCounted

# Utilitário estático (nunca instanciado — mesmo espírito de exp_groups.gd/
# type_chart.gd) com duas tabelas por CLASSE de Trainer (ver trainer.gd):
# quanto multiplicar pelo nível da unidade mais forte do time inimigo pra
# saber o prêmio em dinheiro por vencer (regra 2 do usuário: prize =
# nível_mais_alto x modifier), e um pool de nomes pra sortear quando a
# instância não tiver trainer_name fixo (regra 4: "cada trainer tem um nome
# aleatorizado, exceto personagens importantes").

# Coluna "Gen III" (RS/E ou FRLG, o que for MAIOR — pedido explícito do
# usuário) da tabela de Prize Money do Bulbapedia:
# https://bulbapedia.bulbagarden.net/wiki/Prize_money
#
# Rival/Friend/Champion/"Elite Four"/Leader/RocketBoss vieram DIRETO do
# usuário (ele passou os 6 primeiros valores junto do pedido) — nos jogos de
# verdade essas "classes" são na verdade personagens únicos com prêmio
# individual, sem uma linha de classe fixa na tabela; pra este projeto
# (regra 2: UM modifier por classe) usamos o valor que o usuário informou.
# "Professor" não tem entrada (nem do usuário, nem uma linha própria no
# Bulbapedia — no jogo de verdade também varia por personagem) — cai no
# fallback (ver DEFAULT_MODIFIER/get_modifier abaixo) até existir um valor
# específico.
const MODIFIERS := {
	"Rival": 36,
	"Friend": 16,
	"Champion": 200,
	"Elite Four": 100,
	"Leader": 100,
	"RocketBoss": 32,
	"TeamRocket": 32,
	"Twins": 24,
	"Tuber": 4,
	"Swimmer": 8,
	"Psychic": 24,
	"PokémonRanger": 48,
	"Lass": 16,
	"Youngster": 16,
	"CoolTrainer": 48,
	"Picknicker": 20,
	"Camper": 20,
	"CrushGirl": 24,
	"Blackbelt": 32,
	"Tamer": 48,
	"Supernerd": 24,
	"Scientist": 48,
	"Sailor": 32,
	"RuinMaiac": 60,
	"Rocker": 24,
	"PokemonBreeder": 40,
	"PokeManiac": 60,
	"Painer": 16,
	"Lady": 200,
	"Juggler": 40,
	"Hiker": 40,
	"Gentleman": 80,
	"CueBall": 24,
	"Channeler": 32,
	"Burglar": 88,
	"Birdkeeper": 32,
	"Biker": 20,
	"AromaLady": 40,
	"Gambler": 72,
	"Fisherman": 40,
	"Engineer": 48,
	"BugCatcher": 16,
}

# Usado só pra classe sem entrada em MODIFIERS ("Professor" hoje, ver
# comentário acima) — evita devolver 0 (prêmio de $0 pareceria bug, não
# "ainda não configurado").
const DEFAULT_MODIFIER := 20

static func get_modifier(trainer_class: String) -> int:
	return MODIFIERS.get(trainer_class, DEFAULT_MODIFIER)

# Pool de nomes por classe — só BugCatcher preenchido por enquanto (primeira
# classe implementada de verdade, ver trainer.gd). Qualquer classe futura
# sem pool próprio cai em DEFAULT_NAME_POOL (genérico, sem "cara" de nenhuma
# classe específica) até alguém preencher um pool dedicado — mesmo espírito
# de MODIFIERS/DEFAULT_MODIFIER acima, extensível aos poucos.
const NAME_POOLS := {
	"BugCatcher": ["Doug", "Anthony", "Rick", "Robby", "Wade", "José"],
}
const DEFAULT_NAME_POOL := ["Joey", "Ben", "Chad", "Sam", "Alex", "Todd"]

static func random_name(trainer_class: String) -> String:
	var pool: Array = NAME_POOLS.get(trainer_class, DEFAULT_NAME_POOL)
	return pool[randi() % pool.size()]
