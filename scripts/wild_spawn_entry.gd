class_name WildSpawnEntry
extends Resource

# UMA espécie elegível a nascer como sprite selvagem visível na grama alta de
# uma EncounterArea — pedido do usuário (refactor de encontro selvagem,
# 2026-09-10, verbatim): "grass areas will spawn overworld sprites for units
# able to spawn in that region... instead of being a % chance of a certain
# group spawning, we will calculate for each individual species". Substitui
# EncounterGroup pra fonte "Grass" (EncounterGroup/EncounterEntry continuam
# valendo pra "Water"/"Fishing", que não fizeram parte deste pedido) — cada
# espécie tem sua PRÓPRIA chance, independente de qualquer outra, em vez de
# um grupo fixo inteiro (várias espécies sempre juntas) ser sorteado como uma
# unidade só.
#
# Migração dos dados antigos (ver data/areas/*.tres): cada EncounterEntry que
# antes vivia dentro de um EncounterGroup virou uma WildSpawnEntry própria
# aqui, herdando min_badges/times_of_day do grupo que a continha.
# spawn_chance é uma conversão HEURÍSTICA do peso relativo antigo
# (weight/10.0, script de migração usado uma vez só) — não é dado real do
# PokeMMO (que não expõe % de spawn por rota), então os números aqui são só
# um ponto de partida plausível pra o usuário rebalancear depois.

@export var species: UnitData
@export var level: int = 1

# Chance (0.0-1.0) de UM tile de grama elegível, ao ser sorteado durante o
# povoamento/refresh do patch de grama que o contém (ver
# world.gd::_refresh_grass_patch, chamado no início da cena, a cada troca de
# área e a cada GRASS_GROUP_REFRESH_INTERVAL segundos), instanciar UM sprite
# desta espécie especificamente — rolado
# independentemente de qualquer outra WildSpawnEntry (world.gd embaralha a
# ORDEM das entries elegíveis por tile, então nenhuma espécie tem vantagem
# fixa de "ser checada primeiro"). Tipicamente baixo (a maioria dos tiles de
# grama fica sem sprite nenhum, "supposed to be empty most of the time" é a
# mesma frase usada pro item do slot 6, mesmo espírito aqui pro tile em si).
@export_range(0.0, 1.0) var spawn_chance: float = 0.1

# Mesmos filtros "macios" que EncounterGroup já tinha (ver encounter_group.gd
# pro comentário completo de cada um) — só que aplicados por ESPÉCIE agora,
# não por grupo inteiro. Uma espécie fora do badge/horário simplesmente não
# entra no sorteio daquele tile (não spawna em lugar nenhum, sem fallback:
# diferente de EncounterArea.pick_group(), que caía pro conjunto mais amplo
# se ninguém passasse — aqui "ninguém elegível" só significa "esse tile fica
# sem sprite", o que já é o resultado mais comum de qualquer jeito).
@export var min_badges: int = 0
@export_flags("Morning", "Day", "Night") var times_of_day: int = 7
