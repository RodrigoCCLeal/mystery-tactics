extends "res://scripts/npc.gd"
class_name LootBall

# Objeto interagível parado no mapa (uma "bolinha de recompensa") — o
# jogador anda até ela, aperta X, recebe UMA de três recompensas possíveis
# (configurada no Inspector) e ela SOME da cena pra sempre. Pedido do
# usuário: "LootBall -> Vanishes after interacted with, will reward the
# player with a Unit, an amount of a specific Item or be a surprise
# battle."
#
# Por que herda de npc.gd em vez de ser um Node2D solto (do jeito que
# door.gd é): de graça, ganha o alinhamento no grid (_ready() calcula
# grid_pos a partir de onde foi arrastada no editor) e, mais importante, o
# grupo "npc" — é assim que world.gd/house_interior.gd::
# _try_interact() já sabem achar "tem algo interagível na minha frente"
# (ver _get_npc_at/has_npc_at nos três hosts) E bloquear o jogador de andar
# por cima. Sem isso, precisaríamos duplicar esse sistema de detecção
# inteiro só pra este objeto. _build_sprite_frames() é sobrescrito (ver
# abaixo) porque, diferente de todo outro Npc, a arte NÃO vem de um
# charset de personagem — vem de um único tile do TileSet do overworld.

# Tile (4, 118) da OW/outside.tres, pedido explicitamente pelo usuário — a
# textura é lida direto da imagem-fonte do TileSet (mesma técnica de
# recorte por região que player.gd/npc.gd/trainer.gd já usam pra montar
# sprite a partir de spritesheet crua), não pela API de TileSet em runtime,
# só pra bater com o padrão já usado no resto do projeto.
const TILESET_TEXTURE: Texture2D = preload("res://assets/tiles/tilesets/OW/sourceIMG/Outside.png")
const ATLAS_COORD := Vector2i(4, 118)
const ATLAS_TILE_SIZE := Vector2i(32, 32)

const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")
# Mesma pergunta Sim/Não que nurse.gd já usa (ver comentário dela) —
# reaproveitada aqui quando confirm_before_granting = true (ver abaixo).
const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")

@export_enum("Item", "Unit", "Battle") var reward_type: String = "Item"

# Identificador único DESTA LootBall — mesmo papel de Trainer.trainer_id
# (ver trainer.gd): GameState.collected_loot guarda por este id se ela já
# foi aberta, pra não voltar a aparecer depois de recarregar a cena (ex:
# voltando de uma batalha). Duas LootBalls com o MESMO id contam como uma
# só — sempre dê um valor único por instância.
@export var loot_id: String = ""

# Texto mostrado ao interagir, ANTES da recompensa em si ser revelada — a
# recompensa sempre ganha uma segunda mensagem própria (ver _grant_*
# abaixo), então este texto é só o "flavor" de abrir a bolinha. Pode conter
# o placeholder literal "_UNITNAME_" (ver _format_message) — só é
# substituído quando reward_type == "Unit" e reward_unit está preenchido;
# em qualquer outro caso, o placeholder simplesmente não aparece no texto,
# desconsiderado.
@export var open_message: String = "You found something!"

# false (padrão) = comportamento de sempre, uma caixa de texto só (ver
# MESSAGE_BOX_SCENE) e a recompensa já vem grátis ao fechá-la. true = abre
# uma pergunta Sim/Não (ver YES_NO_PROMPT_SCENE) com open_message —
# pedido do usuário (LootBall do laboratório do Oak): "This ball contains
# _UNITNAME_, will you take it?" (like with nurse). "No" NÃO consome a
# LootBall (mesmo caminho de "não coube no time" — ver _finish_no_reward),
# o jogador pode interagir de novo depois e mudar de ideia.
@export var confirm_before_granting: bool = false

@export_group("Escolha exclusiva (opcional)")
# Nome de uma flag em GameState.flags — vazio (padrão) = sem gate nenhum,
# comportamento de sempre. Preenchido: ANTES de mostrar qualquer coisa,
# interact() confere GameState.get_flag(exclusive_flag); se já for true,
# mostra blocked_message (em vez do fluxo normal) e não deixa a LootBall
# ser aberta. Depois de QUALQUER recompensa concedida com sucesso por esta
# LootBall (ver _mark_collected), a MESMA flag é marcada true — pedido do
# usuário: "It also needs a flag STARTER1_CHOSEN that stops the player
# from being able to take the unit ... Taking any STARTER1 unit makes the
# flag true". Várias LootBalls com o MESMO exclusive_flag implementam
# "escolha exclusiva": pegar QUALQUER UMA bloqueia as outras (caso de uso
# real: os 3 starters do laboratório do Oak).
@export var exclusive_flag: String = ""
# Mostrado no lugar do fluxo normal quando exclusive_flag já está true —
# pedido do usuário: "writing 'Don't be greedy!'" (texto configurável por
# instância, esse é só o padrão genérico).
@export var blocked_message: String = "You've already made your choice!"

@export_group("Reward: Item (reward_type == \"Item\")")
@export var reward_item: ItemData
@export var reward_item_amount: int = 1

@export_group("Reward: Unit (reward_type == \"Unit\")")
@export var reward_unit: UnitData
@export var reward_unit_level: int = 5
# false (padrão) = vai pra primeira vaga livre da RESERVA do PC
# (GameState.storage) — sempre cabe (STORAGE_CAPACITY = 288), nunca falha.
# true = vai DIRETO pro time ATIVO (GameState.roster) — pedido do usuário:
# "It adds directly to the player's party and should give an error message
# if it doesn't fit the team (either by team capacity or weight)". Ver
# GameState.add_to_first_empty_roster_slot pras duas razões possíveis de
# falha; se falhar, a LootBall NÃO é consumida (ver _grant_unit abaixo) —
# o jogador pode abrir espaço no time (PC) e voltar pra tentar de novo.
# "" (padrão) = UnitData.caught_location fica vazio (unit_summary.gd mostra
# "Time inicial" nesse caso — ver comentário lá). Preenchido: esta LootBall
# carimba esse texto como o local de captura da unidade concedida — pedido
# do usuário pros starters do laboratório do Oak, que não passam pela
# batalha/captura de verdade (só resolve_capture, ver battle.gd, carimba
# caught_location sozinho, e isso nunca roda pra uma unidade de LootBall).
# Ex: "Oak's Lab" nos 3 StarterX deste laboratório.
@export var caught_location_override: String = ""

@export var add_to_active_team: bool = false

var _opened: bool = false

func _ready() -> void:
	super._ready()
	# Já foi aberta antes (ver GameState.collected_loot) — desaparece na
	# hora, sem tocar animação/interação nenhuma. Checado DEPOIS de
	# super._ready() de propósito (não muda nada funcionalmente, já que
	# queue_free() só executa no fim do frame, mas mantém a ordem "monta
	# primeiro, decide depois" igual ao resto do arquivo).
	if loot_id != "" and GameState.collected_loot.has(loot_id):
		queue_free()

# Sobrescreve npc.gd::_build_sprite_frames() — em vez de fatiar um charset
# de personagem (sheet, 4 colunas x 4 linhas), recorta UM ÚNICO tile do
# TileSet do overworld e usa o MESMO quadro pras 4 direções (idle_down/
# left/right/up): a bolinha não tem arte direcional, então "virar de
# frente" pro jogador ao interagir — ver npc.gd::face_towards, chamado por
# todo host antes de interact() — não muda nada visualmente, e está tudo
# bem assim.
func _build_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	var atlas = AtlasTexture.new()
	atlas.atlas = TILESET_TEXTURE
	atlas.region = Rect2(
		ATLAS_COORD.x * ATLAS_TILE_SIZE.x,
		ATLAS_COORD.y * ATLAS_TILE_SIZE.y,
		ATLAS_TILE_SIZE.x,
		ATLAS_TILE_SIZE.y
	)
	for dir in SHEET_DIRECTIONS:
		var anim_name = "idle_" + dir
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, 5.0)
		frames.add_frame(anim_name, atlas)
	return frames

# O desenho da bolinha DENTRO da célula 32x32 recortada acima (tile (4,118)
# de Outside.png) não é perfeitamente centrado — medido recortando o tile e
# comparando o bounding-box dos pixels não-transparentes contra o centro
# geométrico da célula: sobra ~7-8px vazios em cima e só ~4-5px embaixo, ou
# seja, o desenho em si já nasce ~2px mais baixo que o centro real do tile.
# Sem correção, mesmo com o node perfeitamente alinhado ao grid (ver
# npc.gd::_ready), a bolinha aparece visualmente puxada pra baixo/lado em
# cima de móveis (mesa do laboratório do Oak, etc.) — o problema NÃO é de
# posicionamento do node, é da arte-fonte mesmo (pedido do usuário: "I think
# the problem is with the way the icon was positioned in the tileset").
const ART_CENTER_OFFSET := Vector2(0, -2)

# Ajuste fino OPCIONAL por instância, em cima da correção acima — pedido do
# usuário: "I even tried to center them" (arrastar o node na cena não
# resolve, porque npc.gd::_ready() SEMPRE resnapa position pro centro
# geométrico do tile toda vez que a cena carrega, desfazendo qualquer ajuste
# manual de posição). Use isto em vez de mover o node quando uma mesa/
# prateleira específica precisar de um empurrão a mais (ex: a "superfície"
# visível do móvel não ocupa o tile inteiro).
@export var visual_offset: Vector2 = Vector2.ZERO

# Sobrescreve npc.gd::_align_sprite_to_tile() — a base assume um charset de
# personagem (sheet + _find_foot_row, ver comentário lá), que não existe
# aqui (a arte vem de TILESET_TEXTURE, não de `sheet`) — por isso a base
# simplesmente não faz nada pra LootBall (sheet == null). Aqui aplicamos a
# correção medida acima, mais o ajuste manual opcional.
func _align_sprite_to_tile() -> void:
	anim.offset = ART_CENTER_OFFSET + visual_offset

# X de frente pra LootBall (mesmo caminho de qualquer Npc — ver world.gd::
# _try_interact, que já vira ela pro jogador ANTES de chamar isto).
# _opened trava contra abrir duas vezes no mesmo frame (ex: X segurado) —
# a bolinha só devia mesmo sumir depois que _vanish() rodar, mas isso só
# acontece no fim de uma sequência assíncrona (await na caixa de texto),
# então existe uma janela onde ela ainda está na árvore mas já foi "usada".
func interact() -> void:
	if _opened:
		return
	if exclusive_flag != "" and GameState.get_flag(exclusive_flag):
		_show_blocked_message()
		return
	_opened = true
	get_tree().paused = true
	if confirm_before_granting:
		var prompt = YES_NO_PROMPT_SCENE.instantiate()
		add_child(prompt)
		prompt.setup(_format_message(open_message))
		prompt.answered.connect(_on_confirm_answered)
	else:
		var box = MESSAGE_BOX_SCENE.instantiate()
		add_child(box)
		box.setup(_format_message(open_message))
		box.closed.connect(_on_open_message_closed)

# "Yes"/"No" do prompt de confirm_before_granting — "No" devolve pro estado
# neutro (ver _finish_no_reward) sem consumir a LootBall nem tocar em
# GameState nenhum, exatamente como o jogador nunca tivesse interagido.
func _on_confirm_answered(yes: bool) -> void:
	if not yes:
		_finish_no_reward()
		return
	_on_open_message_closed()

# Substitui o placeholder "_UNITNAME_" pelo nome de reward_unit — só faz
# sentido pra reward_type == "Unit" (as outras recompensas não têm uma
# "unidade" pra nomear); em qualquer outro caso o texto volta sem alteração
# nenhuma, então usar "_UNITNAME_" numa LootBall de Item/Battle por engano
# só deixa o placeholder literal na tela em vez de crashar.
func _format_message(text: String) -> String:
	if reward_type == "Unit" and reward_unit != null:
		return text.replace("_UNITNAME_", reward_unit.unit_name)
	return text

# Mostra blocked_message e NÃO abre a LootBall de verdade — usado quando
# exclusive_flag já está true (ver interact() acima). Pausa/despausa a
# árvore só ao redor desta caixa, igual qualquer outro popup do arquivo,
# mas nunca seta _opened nem mexe em GameState: interagir de novo depois
# mostra a MESMA mensagem de novo, indefinidamente.
func _show_blocked_message() -> void:
	get_tree().paused = true
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(_format_message(blocked_message))
	box.closed.connect(func(): get_tree().paused = false)

func _on_open_message_closed() -> void:
	match reward_type:
		"Item":
			_grant_item()
		"Unit":
			_grant_unit()
		"Battle":
			_grant_battle()
		_:
			_finish_no_reward()

# Item primeiro por ser o caso mais simples (e o único usado no teste
# pedido pelo usuário: "gives the player a Pokéball"). reward_item vazio no
# Inspector = configuração incompleta — some sem dar nada em vez de
# crashar (mesmo espírito defensivo de trainer.gd/battle.gd em vários
# lugares: preferir um "não faz nada" silencioso a um erro de tipo null).
func _grant_item() -> void:
	if reward_item == null:
		push_warning("LootBall '%s': reward_type=\"Item\" sem reward_item configurado." % name)
		_finish_no_reward()
		return
	GameState.add_item(reward_item, reward_item_amount)
	var label = reward_item.action_name
	if reward_item_amount > 1:
		label = "%d %s" % [reward_item_amount, label]
	_show_result_then_vanish("You got %s!" % label)

# .duplicate() + ensure_initialized() — MESMO padrão de GameState.
# _seed_testing_storage() (ver comentário lá): sem duplicate(), esta
# LootBall e qualquer outra cópia futura da MESMA espécie dividiriam
# nível/xp/HP entre si, já que preload() sempre devolve a MESMA instância
# de Resource.
func _grant_unit() -> void:
	if reward_unit == null:
		push_warning("LootBall '%s': reward_type=\"Unit\" sem reward_unit configurado." % name)
		_finish_no_reward()
		return
	var data: UnitData = reward_unit.duplicate()
	data.ensure_initialized(reward_unit_level)
	if caught_location_override != "":
		data.caught_location = caught_location_override
	if add_to_active_team:
		var error := GameState.add_to_first_empty_roster_slot(data)
		if error != "":
			# NÃO consome a LootBall — ver comentário de add_to_active_team
			# acima. _show_error_and_retry devolve o controle pra
			# _finish_no_reward() quando o jogador fechar o aviso, em vez de
			# _vanish(): time cheio/pesado demais é uma condição TEMPORÁRIA
			# (o jogador pode ir ao PC resolver e voltar), diferente de um
			# Inspector mal configurado, mas o efeito prático é o mesmo —
			# a bolinha continua lá, interagível.
			_show_error_and_retry(error)
			return
		_show_result_then_vanish("%s joined your team!" % data.unit_name)
		return
	if not GameState.add_to_first_empty_storage_slot(data):
		_show_result_then_vanish("Your Storage is full — %s couldn't be added!" % data.unit_name)
		return
	_show_result_then_vanish("%s was added to your Storage!" % data.unit_name)

# "Surprise battle" — reusa o MESMO sistema de encontro selvagem da grama
# alta (ver world.gd::trigger_wild_encounter, wrapper público de
# _start_encounter), em vez de inventar uma tabela de inimigo própria só
# pra LootBall: o oponente sorteado é o da EncounterArea ATUAL do jogador
# (GameState.current_area), do mesmo jeito que pisar na grama decidiria.
# Sem caixa de "you got" nenhuma aqui — a troca de cena pra battle.tscn já
# é o "resultado" acontecendo na hora.
func _grant_battle() -> void:
	if not world.has_method("trigger_wild_encounter"):
		push_warning("LootBall '%s': host '%s' não sabe iniciar encontro selvagem (trigger_wild_encounter ausente) — recompensa \"Battle\" ignorada." % [name, world.name])
		_finish_no_reward()
		return
	# get_tree().paused = false ANTES de trocar de cena — SceneTree.paused
	# sobrevive a change_scene_to_file() (mesmo ponto já corrigido em
	# trainer.gd/world.gd::start_trainer_battle), e interact() acima deixou
	# a árvore pausada pra travar o jogador durante a caixa "open_message".
	# _vanish() já desliga o pause sozinho, mas fazemos ANTES de chamar
	# trigger_wild_encounter() mesmo assim — troca de cena não pode esperar
	# queue_free() (que só executa no fim do frame) pra acontecer.
	get_tree().paused = false
	world.trigger_wild_encounter()
	_vanish()

# Caminho comum de Item/Unit: mostra o resultado numa segunda caixa de
# texto e só desaparece quando o jogador fecha ELA (não a primeira) — dá
# tempo de ler as duas mensagens em vez de piscar uma em cima da outra.
func _show_result_then_vanish(text: String) -> void:
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(text)
	box.closed.connect(_vanish)

# Mostra um erro (ver add_to_active_team acima) e devolve pra
# _finish_no_reward() em vez de _vanish() — a LootBall NÃO é gasta, o
# jogador pode voltar depois de abrir espaço/peso no time.
func _show_error_and_retry(text: String) -> void:
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup(text)
	box.closed.connect(_finish_no_reward)

# Configuração incompleta (reward_item/reward_unit nulo) ou host sem
# trigger_wild_encounter — desfaz a pausa e deixa a LootBall exatamente
# como estava (NÃO desaparece, NÃO marca collected_loot), pra não "gastar"
# a instância por um erro do Inspector; corrija reward_item/reward_unit e
# interaja de novo pra testar.
func _finish_no_reward() -> void:
	get_tree().paused = false
	_opened = false

func _mark_collected() -> void:
	if loot_id != "":
		GameState.collected_loot[loot_id] = true
	if exclusive_flag != "":
		GameState.set_flag(exclusive_flag, true)

func _vanish() -> void:
	get_tree().paused = false
	_mark_collected()
	queue_free()
