class_name SaveData
extends Resource

# Um "save" inteiro, gravado como .tres de verdade em user:// (ver
# GameState.save_game/load_game) — NÃO em res://, porque res:// é
# somente-leitura depois que o jogo é exportado (é só o conteúdo que vem
# junto com o jogo); user:// é a pasta gravável, específica de cada jogador,
# que só existe em disco depois que o jogo já está rodando. É exatamente
# pra esse tipo de dado (progresso do jogador) que user:// existe.
#
# Cada campo aqui é uma cópia congelada do GameState no instante do Save —
# ResourceSaver.save() serializa tudo (incluindo os UnitData/ItemData
# aninhados dentro de roster/storage/inventory_items, do mesmo jeito que já
# funciona pra qualquer .tres de unidade em data/units/). @export em cada
# campo é o que faz o Godot de fato gravar/ler eles do disco (sem @export,
# um var comum de Resource ainda seria salvo, mas @export deixa explícito
# quais campos fazem parte do formato do save, igual UnitData/ItemData já
# fazem com os próprios campos).

@export var player_name: String = ""
@export var money: int = 0
@export var badges: Array[String] = []
# Ver GameState.game_mode/challenge_caught_areas — modo escolhido na criação
# do save ("normal"/"debugger"/"challenge") e, só pro Challenge, quais
# EncounterArea (por area_name) já tiveram uma captura selvagem bem-sucedida
# (regra 1: só uma unidade capturada por área). Saves de antes deste sistema
# existir carregam os defaults abaixo (GameState.load_game trata "" como
# "normal" por segurança, embora o próprio default já resolva isso sozinho).
@export var game_mode: String = "normal"
@export var challenge_caught_areas: Dictionary = {}
@export var defeated_trainer_badges: Dictionary = {}
# Ver GameState.vanished_trainers — treinadores Rocket somem pra sempre
# depois da primeira batalha (vitória OU derrota), não entram nas regras
# normais de rematch de defeated_trainer_badges acima.
@export var vanished_trainers: Dictionary = {}
# Ver comentário grande em GameState.trainer_positions/trainer_facings —
# posição/direção onde cada Trainer (por trainer_id) parou da última vez que
# perseguiu o jogador, pra não voltar pro spawn autorado na .tscn ao
# recarregar o overworld.
@export var trainer_positions: Dictionary = {}
@export var trainer_facings: Dictionary = {}
# Ver GameState.collected_loot — quais LootBall (por loot_id) já foram
# abertas, pra continuarem sumidas depois de recarregar o save.
@export var collected_loot: Dictionary = {}
# Ver GameState.flags — flags de progresso genéricas (nome -> bool).
@export var flags: Dictionary = {}
@export var player_gender: String = "boy"

# Cópia completa do time ativo e da reserva do PC no momento do Save — os
# UnitData aqui são instâncias PRÓPRIAS deste save (duplicadas na hora do
# Save, ver GameState.save_game), carregar de volta (ResourceLoader.load)
# cria instâncias novas de novo, sem risco de compartilhar estado com a
# sessão atual.
@export var roster: Array[UnitData] = []
@export var storage: Array[UnitData] = []
# "Giovanni's Account" (ver GameState.giovanni_storage) — unidades roubadas
# do jogador por treinadores Rocket. Mesmo formato/tamanho fixo de
# `storage`, só que outra caixa: o jogador só ganha acesso a ela depois de
# certo ponto da história (ver GameState.flags, "GIOVANNI_ACCOUNT_UNLOCKED").
@export var giovanni_storage: Array[UnitData] = []
# "Baldo's Account" (ver GameState.baldo_storage) — 1 de cada espécie nível
# 100, pré-preenchida. Mesmo formato/tamanho fixo de storage/
# giovanni_storage, atrás da senha 142857080500 (ver baldo.gd/
# BALDO_PC_UNLOCKED).
@export var baldo_storage: Array[UnitData] = []
# "Heaven Account" (ver GameState.heaven_storage) — unidades do jogador que
# sofreram permadeath no modo Challenge (ver battle.gd::
# _apply_challenge_permadeath). Mesmo formato/tamanho fixo das outras três
# reservas, atrás da senha H34V3N0RH377 (ver baldo.gd/HEAVEN_PC_UNLOCKED).
@export var heaven_storage: Array[UnitData] = []

# Inventário como DOIS arrays em vez de Dictionary (GameState.inventory é
# ItemData -> int) — Dictionary com Resource como chave é mais arriscado de
# serializar em .tres texto; dois arrays em paralelo (mesmo índice = mesmo
# par chave/valor) evita esse risco e é fácil de reconstruir no load.
@export var inventory_items: Array[ItemData] = []
@export var inventory_quantities: Array[int] = []

@export var tool_shortcuts: Array[ItemData] = []

# Área de encontro atual (ver EncounterArea) e pra qual cena de overworld
# voltar — várias cenas existem hoje (world.tscn + interiores), este campo
# é o que lembra em qual delas o jogador estava.
@export var current_area: EncounterArea
@export var overworld_scene_path: String = "res://scenes/overworld/world.tscn"
# Ver GameState.game_time_seconds — relógio próprio do jogo (Manhã/Dia/
# Noite), em segundos dentro de um dia de 24h.
@export var game_time_seconds: float = 8.0 * 3600.0

# Onde o jogador estava exatamente (ver GameState.live_grid_pos/live_facing —
# são estes, não player_grid_pos/player_facing, que valem "AGORA", os outros
# só mudam no instante em que uma batalha começa) e o último checkpoint de
# cura (ver GameState.last_heal_grid_pos/facing).
@export var player_grid_pos: Vector2i = Vector2i.ZERO
@export var player_facing: String = "down"
@export var last_heal_grid_pos: Vector2i = Vector2i.ZERO
@export var last_heal_facing: String = "down"
@export var last_heal_scene_path: String = "res://scenes/overworld/red_house_interior.tscn"
