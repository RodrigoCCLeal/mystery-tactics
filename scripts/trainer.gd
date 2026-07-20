class_name Trainer
extends "res://scripts/npc.gd"

# Terceiro skeleton de NPC do jogo (depois de Nurse e Merchant) — o mais
# importante dos quatro do roster pedido ("1-Merchant 2-Trainer 3-Gift
# 4-Transporter"): batalha de verdade contra o jogador, com time próprio,
# prêmio em dinheiro, e (pra Spinner/Walker/Stander) pode ANDAR sozinho e
# forçar a batalha sem esperar o jogador interagir — é por isso que este é o
# primeiro NPC do jogo que se move fora de uma batalha; Nurse/Baldo/Merchant
# são todos parados (ver npc.gd).
#
# Herda aparência/grid/face_towards de npc.gd, igual os outros dois — mas
# SOBRESCREVE _build_sprite_frames() (pra também montar animação "walk_",
# que a base não constrói, já que NPC normal nunca anda) e _ready() (pra
# completar a configuração de Spot Behavior antes de _process rodar).

# ---------- Identidade ----------
@export_enum(
	"Rival", "Friend", "Champion", "Elite Four", "Leader", "RocketBoss",
	"TeamRocket", "Twins", "Tuber", "Swimmer", "Psychic", "PokémonRanger",
	"Lass", "Youngster", "CoolTrainer", "Picknicker", "Camper", "CrushGirl",
	"Blackbelt", "Tamer", "Supernerd", "Scientist", "Sailor", "RuinMaiac",
	"Rocker", "Professor", "PokemonBreeder", "PokeManiac", "Painer", "Lady",
	"Juggler", "Hiker", "Gentleman", "CueBall", "Channeler", "Burglar",
	"Birdkeeper", "Biker", "AromaLady", "Gambler", "Fisherman", "Engineer",
	"BugCatcher"
)
var trainer_class: String = "Youngster"

# Único por INSTÂNCIA (não por classe) — chave de GameState.
# defeated_trainer_badges (regra 6: "não força batalha de novo depois de
# derrotado"). Preencha algo estável tipo "test_bugcatcher_1"; deixar vazio
# faz esta instância nunca "lembrar" de ter sido derrotada (toda recarga de
# cena esquece), então sempre preencha antes de testar de verdade.
@export var trainer_id: String = ""

# "" (padrão) = sorteia um nome do pool da classe (ver TrainerClassData.
# random_name) em _ready(), uma vez, e fica fixo dali em diante — preenchido
# à mão = nome FIXO, pulando o sorteio (regra 4: "nome aleatorizado, exceto
# personagens importantes"; um personagem importante é só esta instância
# JÁ ter um nome escrito no Inspector).
@export var trainer_name: String = ""

# Mostrado na caixa de texto que abre assim que este Trainer avista o
# jogador (ver _spot_player) — pedido do usuário: "some generic text like
# 'Found you!'". Exportado (não const) pra poder variar por instância/classe
# depois, sem mexer em código.
@export var spotted_message: String = "Found you!"

# Nível de IA que TODAS as unidades deste Trainer usam em batalha —
# sobrescreve o iq individual de cada UnitData (ver comentário grande em
# unit_data.gd::iq) assim que a batalha começa (ver GameState.
# current_trainer_iq, copiado daqui em world.gd/house_interior.gd::
# start_trainer_battle, e aplicado unidade por unidade em battle.gd::
# _spawn_enemy_unit). "Medium" como padrão (não "Easy") porque um Trainer
# humano jogando "burro que nem selvagem" não fazia muito sentido como
# comportamento padrão — ajuste por instância no Inspector quando fizer
# sentido (ex: Trainer's classe iniciante == Easy, um mais forte == Hard).
# "Rocket" tem uma REGRA A MAIS além da tática em si — ver battle.gd::
# _plan_rocket_action e spawn_enemies(): todo time com iq == "Rocket" ganha
# automaticamente 1 Rocket Ball no loadout de cada unidade (pedido do
# usuário: "All units from Rocket teams will have 1 Rocket Ball item action
# in their loadout"), sem precisar configurar isso aqui manualmente.
@export_enum("Easy", "Medium", "Hard", "Rocket", "Champion") var iq: String = "Medium"

@export_group("Time (9 tiers = 0..8 badges)")
# Índice = GameState.badges.size() no momento da batalha (regra 3 do
# usuário). Não precisa preencher os 9 — get_active_team() cai pro tier
# preenchido mais alto ABAIXO do número de badges atual quando o tier exato
# está vazio, então um Trainer só recebe os tiers que realmente mudam (ex:
# só índice 0 e 1 preenchidos, como o BugCatcher de teste pede).
@export var teams: Array[TrainerTeam] = []

@export_group("Spot Behavior")
# Talker = nunca anda, só bate quando o jogador interage (igual Nurse/
# Merchant, só que abrindo batalha em vez de um menu) — ver EYESIGHT_BY_
# BEHAVIOR abaixo pros outros três, cada um com seu próprio alcance de
# visão. Ver comentário grande em _check_sight()/_advance_toward_player()
# pra como a visão/perseguição funcionam de verdade.
@export_enum("Spinner", "Walker", "Stander", "Talker") var spot_behavior: String = "Talker"

@export_group("Walker (só spot_behavior == \"Walker\")")
# Sequência de células (coordenada de GRID, não pixel) que este Trainer
# percorre em loop quando ninguém foi avistado — vazio = Walker fica parado
# no lugar (equivalente a Stander, só que ainda oferecendo o alcance de
# visão de Walker). MVP simples: anda em LINHA RETA de um ponto ao próximo,
# sem desviar de obstáculo nenhum no meio do caminho — funciona bem pra
# patrulhas simples (corredor reto, ida-e-volta), mas não faz pathfinding de
# verdade; um patrol_path com obstáculo no meio trava o Trainer ali.
@export var patrol_path: Array[Vector2i] = []

# Alcance de visão (em tiles, na direção que o Trainer está olhando AGORA —
# ver _check_sight) de cada Spot Behavior, exatamente como os números que o
# usuário deu. Talker fica de fora de propósito (0 = nunca checa visão,
# _process já pula a checagem inteira pra ele antes de olhar aqui).
const EYESIGHT_BY_BEHAVIOR := {
	"Spinner": 2,
	"Walker": 3,
	"Stander": 5,
}

# Spinner troca de direção (a cada SPIN_INTERVAL segundos) percorrendo essa
# ordem em loop — down -> left -> up -> right -> down -> ... (ordem
# arbitrária, só precisa ser consistente).
const SPIN_ORDER := ["down", "left", "up", "right"]
const SPIN_INTERVAL := 1.2

const DIR_VECTORS := {
	"down": Vector2i(0, 1),
	"up": Vector2i(0, -1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}

const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")
const EXCLAMATION_SCENE: PackedScene = preload("res://scenes/effects/exclamation_mark.tscn")

# Posição LOCAL (relativa a este Trainer) onde o "!" nasce — acima da
# cabeça. Ajuste no Inspector se ficar alto/baixo demais pro sprite usado.
@export var exclamation_offset: Vector2 = Vector2(0, -40)

# Mesma duração de passo do Player ANDANDO (não correndo/de bike, ver
# player.gd::MOVE_DURATION) — Trainer sempre persegue no passo normal.
const MOVE_DURATION := 0.22

var _spin_timer: float = 0.0
var _spin_index: int = 0
var _patrol_index: int = 0

# true assim que _check_sight() encontra o jogador — a partir daqui,
# _process() para de checar visão/patrulha e a perseguição começa (ver
# _advance_toward_player). Só volta a false quando a batalha realmente
# começa ou a perseguição é abandonada (ver _give_up_chase).
var is_spotted: bool = false

# true enquanto a caixa de texto (spotted_message) está aberta — só existe
# DEPOIS que o Trainer chega adjacente ao jogador (ver
# _advance_toward_player), nunca antes. Pedido do usuário: "the text box has
# to appear after the trainer reaches the player" — antes disso a caixa
# abria logo depois do "!", ANTES da perseguição, e só liberava a
# perseguição quando fechada; agora é o oposto: perseguição primeiro,
# caixa por último, batalha só quando ela fechar (ver
# _on_reached_player_message_closed). Gate extra em _process() pra não
# tentar andar mais um passo enquanto a caixa estiver na tela.
var _showing_message: bool = false

# true enquanto ESTE Trainer é quem pausou a árvore (ver _spot_player) —
# diferencia "pausado pela minha própria sequência de avistamento" (nesse
# caso o Trainer PRECISA continuar processando, ver _process) de "pausado
# por outra coisa" (menu do sistema, outro NPC com popup aberto — nesse
# caso o Trainer deve congelar igual o resto do overworld, senão continuaria
# girando/perseguindo por baixo de um menu aberto).
var _pausing_for_battle: bool = false

# Referência ao "!" instanciado (ver _spot_player) — guardada só pra dar
# queue_free() nele assim que a animação termina (ver fim de _spot_player)
# ou, se a perseguição for abandonada antes disso, em _give_up_chase().
var _exclamation: Node2D = null

# Movimento passo-a-passo — mesma técnica de player.gd (interpola position
# entre move_start/move_target numa duração fixa), só que sem input nenhum:
# quem decide o próximo passo é sempre _advance_toward_player() ou
# _advance_patrol(), nunca o jogador.
var is_moving: bool = false
var move_start: Vector2 = Vector2.ZERO
var move_target: Vector2 = Vector2.ZERO
var move_elapsed: float = 0.0

func _ready() -> void:
	super._ready()   # posiciona no grid, monta sprite_frames (JÁ com walk_, ver override abaixo), toca idle
	# Treinador Rocket que já entrou em batalha ANTES (vitória OU derrota do
	# jogador, ver GameState.vanished_trainers/battle.gd::end_battle) some
	# pra sempre — checado logo cedo, igual loot_ball.gd já faz com
	# collected_loot: se este trainer_id estiver marcado, esta instância se
	# destrói na hora, sem restaurar posição/Spot Behavior nenhum. Pedido do
	# usuário: "Rocket trainers also vanish after defeating or being
	# defeated. They cannot be rematched" — bem diferente da regra 6 (rematch
	# normal libera com badge nova, ver defeated_trainer_badges mais abaixo).
	if trainer_id != "" and GameState.vanished_trainers.has(trainer_id):
		queue_free()
		return
	# PROCESS_MODE_ALWAYS — necessário pra _process() continuar rodando
	# enquanto a ÁRVORE está pausada (ver _spot_player/_pausing_for_battle):
	# sem isso, pausar pra travar o jogador durante o "!"/caixa de texto
	# também congelaria o próprio Trainer, e ele nunca chegaria a andar até
	# o jogador nem abrir a batalha. O guard no topo de _process() é quem
	# garante que isso NÃO faz o Trainer ignorar pausas de OUTRA origem
	# (menu do sistema, outro NPC).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Sobrescreve a posição/direção que super._ready() acabou de calcular a
	# partir do que está autorado na .tscn — SE este trainer_id já tem uma
	# entrada salva (ver GameState.trainer_positions/_begin_battle abaixo),
	# significa que ele já perseguiu o jogador antes e parou em outro lugar;
	# sem isso, toda recarga de cena (ex: voltando de uma batalha vencida)
	# devolvia o Trainer pro spawn original, desfazendo a perseguição.
	# Pedido do usuário: "the trainer must remain on the spot they moved to
	# when going towards the player, at the end of combat".
	if trainer_id != "" and GameState.trainer_positions.has(trainer_id):
		grid_pos = GameState.trainer_positions[trainer_id]
		global_position = tile_map.to_global(tile_map.map_to_local(grid_pos))   # global_position, não position — ver comentário grande em npc.gd::_ready()
		facing = GameState.trainer_facings.get(trainer_id, facing)
		anim.play("idle_" + facing)
	if trainer_name == "":
		trainer_name = TrainerClassData.random_name(trainer_class)
	if spot_behavior == "Spinner":
		_spin_index = SPIN_ORDER.find(facing)
		if _spin_index < 0:
			_spin_index = 0

# Sobrescreve npc.gd::_build_sprite_frames() pra também montar "walk_<dir>"
# (a base só monta "idle_<dir>", 1 quadro parado — nenhum outro Npc anda).
# Mesma técnica de player.gd::_add_walk_and_idle, só que numa sheet só (os
# NPCs deste projeto não têm sheet separada de walk/idle como o Player).
func _build_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	if sheet == null:
		return frames
	@warning_ignore("integer_division")
	var frame_w = sheet.get_width() / FRAMES_PER_CYCLE
	@warning_ignore("integer_division")
	var frame_h = sheet.get_height() / SHEET_DIRECTIONS.size()
	for row in SHEET_DIRECTIONS.size():
		var dir = SHEET_DIRECTIONS[row]
		frames.add_animation("idle_" + dir)
		frames.set_animation_loop("idle_" + dir, true)
		frames.set_animation_speed("idle_" + dir, 5.0)
		frames.add_animation("walk_" + dir)
		frames.set_animation_loop("walk_" + dir, true)
		frames.set_animation_speed("walk_" + dir, 8.0)
		for col in FRAMES_PER_CYCLE:
			var atlas = AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame("walk_" + dir, atlas)
			if col == IDLE_FRAME_INDEX:
				frames.add_frame("idle_" + dir, atlas)
	return frames

func _process(delta: float) -> void:
	# Pausado por ALGO QUE NÃO SOMOS NÓS (menu do sistema, outro NPC com
	# popup aberto...) — congela igual qualquer node comum faria (ver
	# comentário de PROCESS_MODE_ALWAYS em _ready()). Só quando é ESTE
	# Trainer quem pausou (_pausing_for_battle, ver _spot_player) é que
	# continuamos processando apesar da pausa.
	if get_tree().paused and not _pausing_for_battle:
		return
	# Uma batalha selvagem já está a caminho ESTE MESMO frame (ver
	# world.gd::_battle_starting/is_battle_starting) — não vale a pena nem
	# começar a se mexer/avistar: a cena inteira está prestes a ser trocada
	# de qualquer jeito, e começar _spot_player() agora só criaria uma
	# corrida entre as duas trocas de cena (ver comentário grande em
	# world.gd sobre o motivo dessa trava existir).
	if world.is_battle_starting():
		return
	if is_moving:
		_continue_move(delta)
		return
	if is_spotted:
		# is_spotted já travou o resto de _process() (spin/patrulha/visão
		# não rodam mais abaixo) — a perseguição roda todo frame a partir
		# daqui, EXCETO enquanto a caixa de texto final estiver aberta
		# (_showing_message, ver _advance_toward_player/
		# _on_reached_player_message_closed): sem esse gate o Trainer
		# tentaria dar mais um passo por baixo da caixa.
		if not _showing_message:
			_advance_toward_player()
		return
	if spot_behavior == "Talker":
		return
	# Já derrotado uma vez (vitória do jogador, ver GameState.
	# defeated_trainer_badges/battle.gd::end_battle) — regra 6: para de
	# FORÇAR batalha PRA SEMPRE (não gira/anda/checa visão mais), mesmo que
	# uma badge nova apareça depois — só o gatilho AUTOMÁTICO desliga;
	# interact() ainda pode reabilitar uma revanche, mas só com badge nova
	# (ver função lá embaixo).
	if GameState.defeated_trainer_badges.has(trainer_id):
		return
	if spot_behavior == "Spinner":
		_process_spin(delta)
	elif spot_behavior == "Walker" and patrol_path.size() > 1:
		_process_patrol_idle_step()
	_check_sight()

func _process_spin(delta: float) -> void:
	_spin_timer += delta
	if _spin_timer < SPIN_INTERVAL:
		return
	_spin_timer = 0.0
	_spin_index = (_spin_index + 1) % SPIN_ORDER.size()
	facing = SPIN_ORDER[_spin_index]
	anim.play("idle_" + facing)

# Um passo de patrulha por vez, na direção do próximo ponto de patrol_path —
# MVP em linha reta (ver comentário de patrol_path acima): não desvia de
# obstáculo, só anda reto até a célula alvo e passa pro próximo índice.
func _process_patrol_idle_step() -> void:
	var target = patrol_path[_patrol_index]
	if grid_pos == target:
		_patrol_index = (_patrol_index + 1) % patrol_path.size()
		return
	var dir = Vector2i(sign(target.x - grid_pos.x), sign(target.y - grid_pos.y))
	# Só 4 direções (sem diagonal) — se o próximo ponto não está alinhado
	# num eixo só, anda primeiro no eixo com maior distância (mesmo critério
	# simples de battle.gd::path_axis_score).
	if abs(dir.x) > 0 and abs(dir.y) > 0:
		dir = Vector2i(dir.x, 0) if abs(target.x - grid_pos.x) >= abs(target.y - grid_pos.y) else Vector2i(0, dir.y)
	var new_facing = _facing_for_dir(dir)
	if new_facing != facing:
		facing = new_facing
		anim.play("idle_" + facing)
		return
	var step_cell = grid_pos + dir
	# world.has_npc_at() só enxerga o grupo "npc" (ver world.gd::_get_npc_at)
	# — o Player NUNCA se registra nesse grupo (ele é o dono do overworld, não
	# um NPC), então essa checagem sozinha NUNCA barra o Walker de pisar em
	# cima do jogador. É exatamente o bug reportado: "the hiker seems to have
	# no collision sometimes, it went right through the player" — não era
	# "às vezes", era SEMPRE que o próximo passo da patrulha calhava de cair
	# na célula onde o jogador está parado. Checar _get_player().grid_pos à
	# parte (mesma função que _advance_toward_player() já usa) fecha o
	# buraco: se o jogador estiver bem na célula alvo, o Walker só espera
	# (mesmo comportamento de "bloqueado", igual parede ou outro NPC —
	# tenta de novo no próximo frame, sem replanejar rota).
	var player := _get_player()
	if player != null and player.grid_pos == step_cell:
		# Bloqueado esperando o jogador sair da frente — força idle aqui:
		# _continue_move() não faz mais isso sozinho (ver comentário lá), e
		# sem chamar _start_move() de novo o quadro atual ficaria parado no
		# meio do ciclo de walk_ em vez de numa pose parada de verdade.
		anim.play("idle_" + facing)
		return
	if world.is_cell_walkable(step_cell) and not world.has_npc_at(step_cell):
		_start_move(step_cell)
	else:
		anim.play("idle_" + facing)   # bloqueado por parede/NPC — mesmo motivo do comentário acima

func _facing_for_dir(dir: Vector2i) -> String:
	for key in DIR_VECTORS:
		if DIR_VECTORS[key] == dir:
			return key
	return facing

# Alcance de visão (ver EYESIGHT_BY_BEHAVIOR) na direção que o Trainer está
# olhando agora — igual uma lanterna reta, não um cone. Spinner com o
# jogador CORRENDO (Input "run" — ver player.gd::is_running) é a única
# exceção: regra do usuário "will turn to the player immediately if the
# player is running" — em vez de esperar o giro natural alinhar com a
# direção certa, checa as 4 direções de uma vez nesse caso (o barulho de
# correr "chama a atenção" antes mesmo do Trainer estar de frente).
func _check_sight() -> void:
	var eyesight: int = EYESIGHT_BY_BEHAVIOR.get(spot_behavior, 0)
	if eyesight <= 0:
		return
	var player := _get_player()
	if player == null:
		return
	# player.grid_pos já vira a célula de DESTINO assim que um passo COMEÇA
	# (ver player.gd::_try_start_move — grid_pos muda antes do lerp visual
	# terminar), então checar visão no meio de um passo detecta o jogador
	# "chegando" na célula antes dele visualmente estar lá — mais perceptível
	# correndo, já que os passos são mais curtos/rápidos e a checagem roda
	# todo frame. Esperar o passo terminar (mesmo instante em que a grama
	# selvagem confere tile_entered, ver world.gd) alinha a checagem com o que
	# o jogador está vendo na tela. Reportado pelo usuário: "When running,
	# the player is spotted before actually entering eyesight."
	if player.is_moving:
		return
	var running := Input.is_action_pressed("run")
	var directions: Array = SPIN_ORDER if (spot_behavior == "Spinner" and running) else [facing]
	for dir_name in directions:
		if _can_see_player_in_direction(dir_name, eyesight, player):
			facing = dir_name
			anim.play("idle_" + facing)
			_spot_player()
			return

# Varre em linha reta a partir de grid_pos, na direção dir_name, até `range`
# células — para (sem enxergar) na primeira célula não-andável (parede
# bloqueia visão igual bloqueia passo, mesma fonte de verdade de sempre:
# world.is_cell_walkable). Sucesso = o jogador está numa das células
# varridas ANTES de bater em parede nenhuma.
func _can_see_player_in_direction(dir_name: String, max_range: int, player: Node2D) -> bool:
	var dir: Vector2i = DIR_VECTORS[dir_name]
	var cell := grid_pos
	for i in max_range:
		cell += dir
		if not world.is_cell_walkable(cell):
			return false
		if player.grid_pos == cell:
			return true
	return false

# Avistou o jogador de verdade (ver _check_sight) — pausa a árvore (trava o
# Player e qualquer outro sistema de input do overworld, mesmo padrão de
# Nurse/Merchant/Baldo) e toca o "!" — a caixa de texto NÃO abre mais aqui
# (pedido do usuário: "the text box has to appear after the trainer reaches
# the player"). Assim que o "!" termina, esta função simplesmente volta:
# _process() já enxerga is_spotted=true e _showing_message=false no próximo
# frame e chama _advance_toward_player() sozinho, começando a perseguição.
# start_trainer_battle() (world.gd/house_interior.gd) é quem desliga
# o pause de volta, bem no fim, antes de trocar de cena — não fazemos isso
# aqui de propósito, pra manter o jogador travado o tempo TODO até a
# batalha realmente começar, perseguição e caixa de texto incluídas.
func _spot_player() -> void:
	is_spotted = true
	_pausing_for_battle = true
	get_tree().paused = true
	_exclamation = EXCLAMATION_SCENE.instantiate()
	add_child(_exclamation)
	_exclamation.position = exclamation_offset
	await _exclamation.play_and_wait()   # toca a animação inteira — é o "mais tempo" que o usuário pediu
	if _exclamation != null and is_instance_valid(_exclamation):
		_exclamation.queue_free()
	_exclamation = null

# Instancia a caixa de texto (ver trainer_message_box.gd) com
# spotted_message e chama `on_closed` quando ela fechar (X ou Z) —
# compartilhado entre _spot_player() (avistamento automático, ver acima) e
# interact() (falar direto com o Trainer, ver embaixo) pra não duplicar a
# instanciação em dois lugares.
func _open_message_box(on_closed: Callable) -> void:
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(spotted_message)
	box.closed.connect(on_closed)

# X ou Z na caixa de texto que abre quando o Trainer CHEGA perto do jogador
# (ver _advance_toward_player) — só AGORA a batalha de verdade começa.
func _on_reached_player_message_closed() -> void:
	_showing_message = false
	_begin_battle()

# Chamado todo frame enquanto is_spotted e a caixa de texto final não está
# aberta (ver _process/_showing_message) — persegue em linha reta na MESMA
# direção (facing) que avistou o jogador (nunca muda de direção no meio da
# perseguição: como a visão só acontece em linha reta, perseguir na mesma
# direção sempre encurta a distância). Assim que fica adjacente, PARA de
# andar e abre a caixa de texto (spotted_message) — só quando ela fecha
# (_on_reached_player_message_closed) é que a batalha começa de verdade.
# Desiste (_give_up_chase) se o caminho for bloqueado no meio (parede ou
# outro NPC) — MVP simples, não replaneja rota nem persegue por outro
# caminho.
func _advance_toward_player() -> void:
	var player := _get_player()
	if player == null:
		_give_up_chase()
		return
	if _chebyshev_distance(grid_pos, player.grid_pos) <= 1:
		face_towards(player.grid_pos)
		# face_towards() só troca de animação se a direção MUDOU — se o
		# Trainer já estava perseguindo nessa mesma direção, força idle aqui
		# mesmo assim (ver comentário grande em _continue_move: sem isso, o
		# sprite ficaria parado no meio do ciclo de walk_ durante a caixa de
		# texto/batalha, em vez de numa pose parada de verdade).
		anim.play("idle_" + facing)
		_showing_message = true
		_open_message_box(_on_reached_player_message_closed)
		return
	var dir: Vector2i = DIR_VECTORS.get(facing, Vector2i.ZERO)
	var target_cell = grid_pos + dir
	if not world.is_cell_walkable(target_cell) or world.has_npc_at(target_cell):
		_give_up_chase()
		return
	_start_move(target_cell)

# Desiste de perseguir (caminho bloqueado por parede/NPC, ou o Player
# simplesmente não existe mais nesta cena por algum motivo) — ANTES disto só
# desligava is_spotted, mas _spot_player() já tinha pausado a árvore
# inteira (get_tree().paused = true, ver lá) pra travar o jogador durante o
# "!" + caixa de texto + perseguição, e SÓ start_trainer_battle() desliga
# esse pause de volta. Sem chegar numa batalha de verdade, esse pause nunca
# era desfeito — o jogo ficava travado pra sempre (bug real: "game freezes
# and battle doesn't start"), bem mais fácil de acontecer no mapa de
# ARCHI, cheio de parede/prédio no meio do caminho, do que no campo
# aberto de world.tscn onde isso nunca tinha sido reparado. Devolve tudo pro
# estado neutro: o jogador recupera o controle, e o Trainer volta a girar/
# patrulhar normalmente (ver _process) como se nunca tivesse avistado
# ninguém.
func _give_up_chase() -> void:
	is_spotted = false
	_showing_message = false
	_pausing_for_battle = false
	# Mesmo motivo do anim.play("idle_"+facing) em _advance_toward_player():
	# a perseguição pode parar bem no meio de um passo (ver _continue_move),
	# sem isso o Trainer voltaria a girar/patrulhar com o sprite travado
	# numa pose de walk_.
	anim.play("idle_" + facing)
	if _exclamation != null and is_instance_valid(_exclamation):
		_exclamation.queue_free()
	_exclamation = null
	get_tree().paused = false

func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _start_move(target_cell: Vector2i) -> void:
	grid_pos = target_cell
	# global_position, não position — mesmo fix de npc.gd::_ready()/
	# player.gd::_try_start_move (tile_map.map_to_local() é sempre espaço da
	# TileMapLayer, nunca do pai deste Trainer).
	move_start = global_position
	move_target = tile_map.to_global(tile_map.map_to_local(grid_pos))
	move_elapsed = 0.0
	is_moving = true
	anim.play("walk_" + facing)

func _continue_move(delta: float) -> void:
	move_elapsed += delta
	var t = clamp(move_elapsed / MOVE_DURATION, 0.0, 1.0)
	global_position = move_start.lerp(move_target, t)
	if t >= 1.0:
		is_moving = false
		# NÃO troca pra idle aqui — mesmo bug (e mesma correção) documentados
		# em player.gd::_continue_move: AnimatedSprite2D.play() só CONTINUA de
		# onde parou se for a MESMA animação já tocando; trocar de animação
		# (walk_ -> idle_ -> walk_) sempre volta pro quadro 0. Como
		# MOVE_DURATION (0.22s) é bem mais curto que um ciclo de walk_ inteiro
		# (4 quadros a 8 fps = 0.5s), forçar idle a cada passo reiniciava o
		# ciclo toda vez — o walk nunca chegava a mostrar os 4 quadros,
		# parecia travado/estranho (bug reportado pelo usuário). Quem decide
		# mostrar idle agora é só quem decide "não vou dar mais um passo"
		# (_process_patrol_idle_step, _advance_toward_player, _give_up_chase)
		# — chamando _start_move() de novo com a MESMA direção, o walk_
		# continua o ciclo em vez de reiniciar.

func _get_player() -> Node2D:
	return get_node("../Player") if has_node("../Player") else null

# X de frente pro Trainer (mesmo caminho de qualquer Npc, ver world.gd::
# _try_interact, que já vira o Trainer pro jogador ANTES de chamar isto) —
# regra do usuário: "They all initiate a battle if the player interacts
# with them", mas SÓ depois da mesma caixa de texto que o avistamento
# automático mostra (pedido do usuário: "when interacted with, the trainer
# also has to display its text box, the battle is starting automatically"
# — antes disso a batalha começava na hora, sem diálogo nenhum). Sem
# exclamação nem perseguição aqui — o jogador já está bem na frente,
# encarando o Trainer, não faz sentido nenhum dos dois.
#
# EXCETO se este Trainer já foi derrotado ANTES e o jogador ainda não
# ganhou nenhuma badge nova desde então (regra 6: "the player may battle
# them again by interacting after winning a new badge" — sem badge nova,
# interagir não faz nada, silenciosamente, mesmo espírito de outros guards
# do projeto que só "não fazem nada" quando a ação não faz sentido ainda,
# ver item_list_screen.gd::_activate_selected_row).
func interact() -> void:
	if GameState.defeated_trainer_badges.has(trainer_id):
		var badges_at_defeat: int = GameState.defeated_trainer_badges[trainer_id]
		if GameState.badges.size() <= badges_at_defeat:
			return
	# Termina JÁ qualquer passo de patrulha/giro em andamento (is_moving) —
	# diferente de _spot_player(), interact() NÃO liga _pausing_for_battle,
	# então o "if get_tree().paused and not _pausing_for_battle: return" no
	# topo de _process() vai travar o resto do script assim que pausarmos
	# duas linhas abaixo. Se o jogador interage bem no meio de um passo
	# (comum com Walker, ver Pedro/patrol_path), is_moving ficava preso em
	# true pra sempre — e _begin_battle() se recusa a começar a batalha com
	# is_moving == true (ver lá), então o jogo ficava pausado sem jeito
	# nenhum de sair (bug reportado: "when talked to, freezes the game" —
	# só acontecia quando o Trainer estava andando no instante exato da
	# interação; por isso "when spotted works normally", a perseguição
	# sempre termina o passo antes de chegar em _begin_battle).
	if is_moving:
		is_moving = false
		global_position = move_target
		anim.play("idle_" + facing)
	is_spotted = false
	get_tree().paused = true
	_open_message_box(_begin_battle)

# Abre a batalha de verdade — delegado pro "world" (Test, ver
# start_trainer_battle lá) porque é ele quem sabe salvar a posição do
# jogador e trocar de cena (mesmo padrão de use_door() delegar pro world em
# vez do próprio Door trocar de cena).
func _begin_battle() -> void:
	if is_moving:
		return
	# Última chance de gravar ONDE este Trainer está — start_trainer_battle()
	# (chamado logo abaixo) troca de cena na sequência, o que destrói este
	# node inteiro. Ver GameState.trainer_positions/_ready() acima pra como
	# isso é lido de volta na próxima vez que a cena carregar. Sem trainer_id
	# não tem chave pra guardar (mesmo guard que defeated_trainer_badges já
	# usa em outros lugares deste script).
	if trainer_id != "":
		GameState.trainer_positions[trainer_id] = grid_pos
		GameState.trainer_facings[trainer_id] = facing
	world.start_trainer_battle(self)

# Time ativo pro número de badges atual (regra 3 do usuário). badges.size()
# como índice direto: 0 badges = tier 0, 1 badge = tier 1, etc. Se o tier
# exato não existir (fora dos limites de `teams`) ou estiver vazio, cai pro
# tier preenchido mais alto ABAIXO dele — assim um Trainer só precisa
# preencher os tiers que realmente mudam.
func get_active_team() -> Array[TrainerTeamEntry]:
	var tier: int = mini(GameState.badges.size(), teams.size() - 1)
	while tier >= 0:
		var team: TrainerTeam = teams[tier]
		if team != null and not team.entries.is_empty():
			return team.entries
		tier -= 1
	return []

# nível_mais_alto_do_time x modifier_da_classe (regra 2 do usuário, ver
# TrainerClassData.get_modifier). Lido no tier ATIVO agora (get_active_team),
# então o prêmio já escala sozinho conforme o jogador ganha badges.
func get_prize_money() -> int:
	var entries := get_active_team()
	var highest_level := 0
	for entry in entries:
		highest_level = maxi(highest_level, entry.level)
	return highest_level * TrainerClassData.get_modifier(trainer_class)
