extends Node2D

# preload em vez de confiar no class_name global — assim funciona mesmo se o
# editor ainda não tiver re-escaneado os scripts do projeto depois que
# exp_groups.gd foi criado (era a causa do erro "Identifier not declared").
const ExpGroups = preload("res://scripts/exp_groups.gd")

const TILE_SIZE = 24
const MOVE_SPEED = 5.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar_bg: ColorRect = $HealthBarBg
@onready var health_bar_fill: ColorRect = $HealthBarFill
@onready var status_emote: Sprite2D = $StatusEmote
@onready var damage_popup: Label = $DamagePopup

const HEALTH_BAR_WIDTH = 20.0

# ---------- Popup de dano ("-X HP") ----------
# Só usado em inimigos (ver take_damage() — a barra de vida deles está
# escondida desde mark_as_enemy(), então esse número é o único feedback de
# dano que sobrou pro jogador; aliados continuam com a barra visível, não
# precisam do popup). Pisca por DAMAGE_POPUP_BLINK_DURATION segundos (5
# ciclos de fade out/in) e depois some — tudo numa cadeia sequencial de
# Tween explícita (sem set_loops()) pra garantir que o tween_callback final
# de esconder rode exatamente uma vez, no fim, e não a cada ciclo. A cor
# (amarelo escuro) fica só no .tscn (theme_override_colors/font_color do
# DamagePopup) — é estática, não precisa de const aqui.
const DAMAGE_POPUP_BLINK_DURATION = 1.0
const DAMAGE_POPUP_BLINK_STEP = 0.1
var _damage_popup_tween: Tween = null

func show_damage_popup(amount: int) -> void:
	damage_popup.text = "-%d HP" % amount
	damage_popup.modulate.a = 1.0
	damage_popup.visible = true

	if _damage_popup_tween != null and _damage_popup_tween.is_valid():
		_damage_popup_tween.kill()
	_damage_popup_tween = create_tween()

	var cycles = int(DAMAGE_POPUP_BLINK_DURATION / (DAMAGE_POPUP_BLINK_STEP * 2))
	for i in cycles:
		_damage_popup_tween.tween_property(damage_popup, "modulate:a", 0.0, DAMAGE_POPUP_BLINK_STEP)
		_damage_popup_tween.tween_property(damage_popup, "modulate:a", 1.0, DAMAGE_POPUP_BLINK_STEP)
	_damage_popup_tween.tween_callback(func(): damage_popup.visible = false)

# ---------- Emote de Status Condition (ex: "?" de Confused) ----------
# Mesma técnica de fatiar quadros do Projectile/ImpactEffect (tira horizontal
# de quadros QUADRADOS, tamanho calculado em runtime a partir da textura —
# ver _start_status_emote()), mas em LOOP em vez de tocar uma vez só: fica
# flutuando sobre a cabeça a unidade inteira enquanto a condição durar, não
# só no instante em que ela é aplicada (isso já existe separado, ver
# AttackData.secondary_status_texture/play_impact_effect).
#
# Nem toda entrada aqui é uma tira de quadros — Foresight_Glass (Blind) é uma
# imagem ÚNICA (sem animação própria). O mesmo cálculo de frame_size/
# frame_count já cobre isso sozinho: largura/altura de uma imagem quase
# quadrada dá frame_count=1, então o "loop de quadros" em _process() não tem
# o que trocar. Pra essa não ficar parada e sem graça, quando frame_count<=1
# a gente liga um balanço vertical suave em vez do ciclo de quadros (ver
# _start_emote_bob()).
#
# Caminho corrigido pra assets/sprites/Status/ (não mais .../effects/) —
# essas duas imagens moraram lá numa reorganização de pastas anterior a esta.
const CONFUSED_EMOTE_TEXTURE = preload("res://assets/sprites/Status/Emote_Question.None.png")
const BLIND_EMOTE_TEXTURE = preload("res://assets/sprites/Status/Foresight_Glass.None.png")
const STATUS_EMOTE_TEXTURES := {
	"Confused": CONFUSED_EMOTE_TEXTURE,
	"Blind": BLIND_EMOTE_TEXTURE,
}

# Burned: pasta com 9 arquivos SEPARADOS (BurnedIndicator/000.png..008.png),
# não uma tira dentro de uma imagem só — mesmo formato "vários arquivos" já
# usado em AttackData.projectile_frames/Projectile.raw_frames (ver comentário
# lá). Por isso vive num dicionário À PARTE (STATUS_EMOTE_FRAME_ARRAYS): cada
# entrada aqui já é a lista de quadros pronta, sem corte de atlas nenhum (ver
# _start_status_emote()/_process()).
const BURNED_EMOTE_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Status/BurnedIndicator/000.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/001.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/002.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/003.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/004.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/005.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/006.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/007.png"),
	preload("res://assets/sprites/Status/BurnedIndicator/008.png"),
]
const STATUS_EMOTE_FRAME_ARRAYS := {
	"Burned": BURNED_EMOTE_FRAMES,
}

# Default "vazio" tipado pra STATUS_EMOTE_FRAME_ARRAYS.get(status, ...) em
# _start_status_emote() — um literal `[]` cru ali seria um Array GENÉRICO
# (sem tipo), e atribuir isso direto a _status_emote_raw_frames (tipada
# Array[Texture2D]) quebra em runtime ("Trying to assign an array of type
# 'Array' to a variable of type 'Array[Texture2D]'"). Bug reportado pelo
# usuário: acontecia com QUALQUER status fora do dicionário (Confused é o
# caso comum, mas Poisoned/Frozen/etc. teriam o mesmo problema se algum dia
# passassem por aqui) — sempre que status não é "Burned".
const EMPTY_TEXTURE_ARRAY: Array[Texture2D] = []
const STATUS_EMOTE_FRAME_DURATION = 0.08

var _status_emote_atlas: AtlasTexture
var _status_emote_frame_size: int = 1
var _status_emote_frame_count: int = 1
var _status_emote_frame_index: int = 0

# Preenchido só quando o status atual usa o formato "vários arquivos" (ver
# STATUS_EMOTE_FRAME_ARRAYS/BURNED_EMOTE_FRAMES) — vazio = modo de sempre
# (_status_emote_atlas fatiado de uma textura só).
var _status_emote_raw_frames: Array[Texture2D] = []

# Balanço vertical do emote quando ele não tem quadros próprios (ver acima).
# Guardamos a posição "de repouso" em _ready() em vez de um Vector2 fixo, pra
# não depender de decorar o valor que está no .tscn (StatusEmote.position).
const EMOTE_BOB_OFFSET = 3.0
const EMOTE_BOB_STEP = 0.4
var _status_emote_rest_position: Vector2 = Vector2.ZERO
var _emote_bob_tween: Tween = null
var _status_emote_frame_timer: float = 0.0

# Cores da barra de vida por faixa de HP restante (ratio = hp_current/hp_max).
# Acima de 50% fica verde (cor original da cena), entre 25% e 50% fica
# amarela, abaixo de 25% fica vermelha.
const HEALTH_COLOR_HIGH = Color(0.2, 0.85, 0.2, 1)
const HEALTH_COLOR_MID = Color(0.9, 0.85, 0.2, 1)
const HEALTH_COLOR_LOW = Color(0.85, 0.2, 0.2, 1)

# Quantas vezes a animação hurt_<dir> repete antes da unidade sumir de vez,
# e o piscar de opacidade (via Tween) que acompanha essas voltas.
const DEATH_HURT_CYCLES = 2
const DEATH_BLINK_ALPHA = 0.3
const DEATH_BLINK_INTERVAL = 0.15

# ---------- Stat Stages (Altered Stats) ----------
# Só estes 5 stats podem ser alterados por estágio — HP e peso NUNCA (regra
# explícita do design). Cada estágio vai de -6 a +6, com o multiplicador
# batendo exatamente na tabela pedida (não é uma fórmula limpa nos negativos,
# por isso é uma tabela, não uma conta).
const STAGE_STATS = ["attack", "defense", "special_attack", "special_defense", "speed"]
const STAT_STAGE_MIN = -6
const STAT_STAGE_MAX = 6
const STAT_MIN = 1     # nenhum stat com estágio pode cair abaixo disso
const STAT_MAX = 999   # nem subir acima disso
const STAT_STAGE_MULTIPLIERS := {
	-6: 2.0 / 8.0, -5: 2.0 / 7.0, -4: 2.0 / 6.0, -3: 2.0 / 5.0, -2: 2.0 / 4.0, -1: 2.0 / 3.0,
	0: 1.0,
	1: 1.5, 2: 2.0, 3: 2.5, 4: 3.0, 5: 3.5, 6: 4.0,
}

# ---------- Status Conditions ----------
# "" = nenhuma condição. Não empilham (ver apply_status_condition) e são
# resetadas sozinhas todo combate — Unit é recriado do zero a cada batalha
# (ver UNIT_SCENE.instantiate() em battle.gd), então não precisa de nenhum
# código extra pra "curar ao fim do combate": o valor padrão já é "sem
# condição" sempre que uma unidade nova entra em cena.
#
# Duração em turnos de quem tem prazo fixo (Poisoned e Burned não têm — só
# saem por cura; Flinched também não usa isso, ver comentário em
# battle.gd::begin_current_turn). O contador desce no fim do turno da PRÓPRIA
# unidade afetada (ver battle.gd::apply_end_of_turn_status), nunca no turno
# de quem aplicou a condição.
const STATUS_DURATIONS := {
	"Frozen": 2, "Paralyzed": 2, "Confused": 2, "Blind": 2, "Asleep": 3,
}

# Quais condições bloqueiam o quê — segue a letra do design (Frozen só trava
# movimento, Paralyzed só trava ataque, Asleep trava os dois; Flinched trava
# os dois mas só por 1 turno e é tratado à parte em begin_current_turn).
const MOVEMENT_BLOCKING_STATUS = ["Frozen", "Asleep", "Flinched"]
const ATTACK_BLOCKING_STATUS = ["Paralyzed", "Asleep", "Flinched"]

const POISON_DAMAGE_PERCENT = 8  # Poisoned: 8/100 do hp_max, por turno

# Imunidade por TIPO — uma unidade cujo UnitData.types contenha qualquer um
# dos tipos listados aqui nunca pega essa condição (apply_status_condition
# simplesmente recusa, ver lá). Regra do design: Steel/Poison são imunes a
# Poisoned, Fire é imune a Burned, Electric é imune a Paralyzed, Ice é imune
# a Frozen. Condições sem entrada aqui (Confused/Asleep/Flinched/Blind) não
# têm imunidade de tipo nenhuma.
const STATUS_TYPE_IMMUNITIES := {
	"Poisoned": ["Steel", "Poison"],
	"Burned": ["Fire"],
	"Paralyzed": ["Electric"],
	"Frozen": ["Ice"],
}

# ---------- Indicadores visuais de Status Condition ----------
# "Máscara" de cor sobre o sprite (ver _refresh_tint). Condições sem entrada
# aqui (Poisoned/Frozen têm cor, mas Paralyzed/Confused/Asleep/Flinched não
# — essas usam outro indicador: tremor, animação própria, ou o emote de
# status flutuando acima da cabeça, ver STATUS_EMOTE_TEXTURES/
# STATUS_EMOTE_FRAME_ARRAYS) ficam com Color.WHITE (sem máscara). Burned
# SAIU daqui: agora tem indicador animado próprio (BurnedIndicator, ver
# STATUS_EMOTE_FRAME_ARRAYS) em vez de tingir o sprite inteiro de vermelho.
const STATUS_TINT_COLORS := {
	"Frozen": Color(0.65, 0.85, 1.0),
	"Poisoned": Color(0.75, 0.45, 0.95),
}

# Tremor horizontal de Paralyzed — desloca só o AnimatedSprite2D (não o Node2D
# raiz, que é a posição LÓGICA de grid usada por movimento/mira/etc.), então
# não interfere em nada de gameplay, só visual.
const PARALYZE_SHAKE_OFFSET = 2.0
const PARALYZE_SHAKE_STEP = 0.08
var _status_shake_tween: Tween = null

# Posição no grid
var grid_pos: Vector2i = Vector2i(0, 0)
var is_moving: bool = false

# Direção que a unidade está encarando (usada pra escolher idle_<dir> / walk_<dir>).
# Nomes batem com as linhas do sprite sheet: 0=baixo, 1=baixo-direita, 2=direita,
# 3=cima-direita, 4=cima, 5=cima-esquerda, 6=esquerda, 7=baixo-esquerda.
var facing: String = "down"

# Marca se essa unidade é inimiga (usado pelo battle.gd e pela IA). Não aplica
# nenhum tint (ver _refresh_tint) — o vermelho fixo de "isso é inimigo" foi
# removido de propósito pra testar as máscaras de Status Condition sem
# interferência. A distinção visual aliado/inimigo agora é a barra de vida:
# só unidades do jogador mostram a própria (ver mark_as_enemy() abaixo) —
# assim dá pra saber quem é quem só de olhar o HUD acima da sprite.
var is_enemy: bool = false

# true a partir do instante em que hp_current chega a 0, até o nó sumir de
# vez. Usado por _on_attack_animation_finished pra saber se deve tocar a
# sequência de morte (repetir hurt_<dir> mais uma vez) em vez de voltar pro
# idle normalmente, e por take_damage() pra não disparar die() de novo se
# outro ataque acertar essa unidade enquanto ela ainda está sumindo.
var is_dying: bool = false
var death_hurt_cycles_left: int = 0

func mark_as_enemy() -> void:
	is_enemy = true
	# Some com a barra de vida do inimigo — é a nossa distinção visual entre
	# aliado e inimigo agora (ver comentário de is_enemy acima). update_health_bar()
	# só mexe em size.x/color do fill, nunca em .visible, então isso fica
	# escondido pelo resto da batalha sem precisar repetir em nenhum outro lugar.
	health_bar_bg.visible = false
	health_bar_fill.visible = false

# Recalcula modulate a partir só da "máscara" de Status Condition
# (STATUS_TINT_COLORS) — sem status, fica branco (sem tint nenhum, nem de
# inimigo). Chamado sempre que status_condition muda. modulate:a (opacidade)
# fica de fora de propósito: quem mexe nisso é o Tween de morte (ver die()),
# então só tocamos R/G/B aqui.
func _refresh_tint() -> void:
	var status_tint: Color = STATUS_TINT_COLORS.get(status_condition, Color.WHITE)
	modulate = Color(status_tint.r, status_tint.g, status_tint.b, modulate.a)

# UnitData de origem — guardado pra poder recalcular os stats reais sempre
# que o nível mudar (level up, etc).
var data: UnitData = null

var unit_name: String = ""
var weight: int = 1       # 0 a 4 — cópia direta de data.weight, não escala com nível
var iq: String = "Easy"   # cópia de data.iq, ou sobrescrito por GameState.current_trainer_iq (ver _apply_common)

# Nível e XP. Ainda não temos os patamares de XP que definem quando sobe de
# nível — por enquanto o nível só é usado pra calcular os stats reais.
var level: int = 1
var xp: int = 0

# Stats REAIS — calculados a partir dos stats base (UnitData) + nível.
# Fórmula (todas as divisões truncam a parte decimal, sem arredondar):
#   HP:            (2*base * nivel)/100 + nivel*peso + 10
#   Outros stats:  (2*base * nivel)/100 + 5
var hp_max: int = 1
var hp_current: int = 1
var attack: int = 1
var special_attack: int = 1
var defense: int = 1
var special_defense: int = 1
var speed: int = 1

# Movimento: base (5 - peso) + bônus por velocidade (1 a cada 100 pontos).
# Usa get_effective_stat("speed") (não a var speed crua) pra já respeitar um
# eventual estágio de Speed alterado (ver STAGE_STATS).
var move_range: int:
	get:
		var base = max(1, 5 - weight)
		@warning_ignore("integer_division")
		var bonus = get_effective_stat("speed") / 100   # divisão inteira proposital: 1 ponto a cada 100 de speed
		return base + bonus

# Usos restantes de cada slot (paralelo a data.slots — slot_uses[i] é quanto
# ainda sobra do ActionData em data.slots[i]). Fica AQUI, não no ActionData,
# porque data pode ser a mesma instância de Resource compartilhada por várias
# unidades da mesma espécie — se o contador vivesse lá, gastar o ataque de uma
# unidade descontaria de todas as outras. Reseta a cada _apply_common() (ou seja,
# a cada batalha — ver comentário em UnitData.slots sobre o loadout travar
# durante a batalha).
#
# 0 aqui pode significar duas coisas: slot vazio, OU ação sem contador de uso
# (max_uses -1 no ActionData — o normal pra Habilidade e a maioria dos Itens).
# Não precisa distinguir os dois casos: os dois têm o mesmo efeito prático
# (não gasta uso, não bloqueia por "usos esgotados").
var slot_uses: Array[int] = []

# Quantos Ataques essa unidade ainda pode usar NESTE turno. É um int (não um
# bool) de propósito: hoje só vai a 1 -> 0, mas assim um efeito futuro (ex:
# uma Habilidade de "ataque duplo") pode simplesmente somar +1 aqui em vez de
# precisar de um sistema à parte. Resetado pra 1 no início de cada turno da
# unidade (battle.gd begin_current_turn()) — Habilidade e Item NÃO mexem
# nisso, essa trava é só pra Ataque (ver ActionData -> AttackData).
var attacks_remaining: int = 1

# Estágio atual de cada stat alterável (ver STAGE_STATS/STAT_STAGE_MULTIPLIERS
# acima) — 0 = normal, igual attacks_remaining/slot_uses isso é só de batalha,
# some sozinho quando a unidade é recriada no próximo combate.
var stat_stages: Dictionary = {"attack": 0, "defense": 0, "special_attack": 0, "special_defense": 0, "speed": 0}

# "" = sem Status Condition. status_turns_left só é relevante pra quem está
# em STATUS_DURATIONS (-1 = não se aplica, ex: Poisoned/Burned, que só saem
# por cura).
var status_condition: String = ""
var status_turns_left: int = -1

# Duas formas de aplicar UnitData (aparência + stats base) nesta instância —
# ambas precisam ser chamadas DEPOIS de add_child(), pra que @onready var anim
# já exista:
#
# - apply_persisted_data(): pro TIME DO JOGADOR. Lê nível/xp/HP que já
#   estavam salvos em `new_data` (ver UnitData.level/xp/current_hp e
#   GameState.roster) — é a unidade "de verdade", com o progresso de
#   batalhas anteriores. Precisa ter passado por UnitData.ensure_initialized()
#   antes (GameState._ready() já garante isso pro roster inteiro).
#
# - apply_fresh_data(): usada pelos inimigos (battle.gd::spawn_enemies),
#   sorteados de GameState.ALL_SPECIES — um catálogo read-only de todas as
#   espécies do jogo, sem relação com o roster do jogador. Sempre entra
#   fresco (nível fixo, xp 0, HP cheio), sem ler NEM escrever em
#   new_data.level/xp/current_hp — ALL_SPECIES nunca é mutado, então nem
#   precisaria dessa trava pra evitar vazamento de progresso, mas continua
#   sendo o jeito certo de spawnar algo que não deve "lembrar" nada entre
#   batalhas.
func apply_persisted_data(new_data: UnitData) -> void:
	_apply_common(new_data)
	level = new_data.level
	xp = new_data.xp
	recalculate_stats()
	# max(..., 1) é só uma segunda trava — quem decide se uma unidade
	# desmaiada (current_hp <= 0) entra em campo é battle.gd::spawn_player_
	# units_staged() (filtra ANTES de chamar isso aqui). Isso aqui só evita
	# um HP negativo/zero se algum caminho futuro esquecer daquele filtro.
	hp_current = max(new_data.current_hp, 1)
	update_health_bar()

# forced_loadout opcional — usado por battle.gd::spawn_enemies() pra times de
# Trainer com golpes específicos (ver TrainerTeamEntry.loadout). Vazio
# (padrão, único caso antes desse parâmetro existir) mantém o comportamento
# de sempre: loadout automático via get_recent_loadout(), tanto pra selvagem
# quanto pra entrada de Trainer sem loadout customizado (regra 3 do usuário:
# "se não especificado, use as mesmas regras de unidades selvagens").
func apply_fresh_data(new_data: UnitData, start_level: int, forced_loadout: Array[ActionData] = [], extra_loadout: Array[ActionData] = []) -> void:
	# Duplica ANTES de mexer no loadout — new_data normalmente é a mesma
	# instância compartilhada do catálogo (GameState.ALL_SPECIES), reusada por
	# todo inimigo dessa espécie em qualquer batalha. Escrever em new_data.slots
	# direto contaminaria esse catálogo pra sempre (várias unidades inimigas
	# apontam pro mesmo Resource — ver comentário de UnitData.slots). Mesmo
	# motivo de GameState.roster já duplicar UnitData por slot do time do
	# jogador. get_recent_loadout() monta o loadout automático (as até 6 ações
	# mais recentes do learnset pra esse nível — ver comentário lá).
	var fresh_data: UnitData = new_data.duplicate()
	fresh_data.slots = forced_loadout if not forced_loadout.is_empty() else fresh_data.get_recent_loadout(start_level)
	# extra_loadout: ANEXADO por cima do loadout já resolvido (forçado OU
	# automático), nunca o substitui — usado hoje só por times "Rocket" (ver
	# battle.gd::spawn_enemies), que precisam garantir 1 Rocket Ball em CADA
	# unidade além de quaisquer golpes já configurados/automáticos. Só 6
	# slots cabem no total (mesmo limite de sempre, ver UnitData.slots) — se o
	# loadout já resolvido tiver enchido os 6, o extra simplesmente não entra
	# em vez de estourar o array (o autor do Trainer precisa deixar espaço de
	# propósito; mesmo espírito defensivo de "não crashar por configuração
	# incompleta" já usado no resto do projeto).
	if not extra_loadout.is_empty() and fresh_data.slots.size() < 6:
		fresh_data.slots = fresh_data.slots + extra_loadout.slice(0, 6 - fresh_data.slots.size())
	_apply_common(fresh_data)
	level = start_level
	xp = 0
	recalculate_stats()
	hp_current = hp_max
	update_health_bar()

func _apply_common(new_data: UnitData) -> void:
	data = new_data
	unit_name = data.unit_name
	weight = data.weight
	iq = data.iq
	anim.sprite_frames = data.sprite_frames
	slot_uses.clear()
	for action in data.slots:
		if action != null and action.max_uses > 0:
			slot_uses.append(action.max_uses)
		else:
			slot_uses.append(0)   # slot vazio, ou ação sem contador de uso (max_uses -1)

# Grava level/xp/hp_current de volta em `data` — SÓ pra unidades do jogador
# (is_enemy == false; inimigos usam apply_fresh_data, que nunca deveria
# persistir nada mesmo). Como `data` é a mesma instância guardada em
# GameState.roster (ver o .duplicate() lá — cada slot tem a sua própria),
# escrever aqui já é o suficiente pra persistir — não precisa de nenhum
# "save" explícito ao sair da batalha.
func sync_to_data() -> void:
	if is_enemy or data == null:
		return
	data.level = level
	data.xp = xp
	data.current_hp = max(hp_current, 0)

# Recalcula todos os stats reais a partir de data (stats base) + level.
# Chamar de novo sempre que o nível mudar (level up).
func recalculate_stats() -> void:
	if data == null:
		return
	hp_max = calc_hp(data.hp_base)
	attack = calc_stat(data.attack_base)
	defense = calc_stat(data.defense_base)
	special_attack = calc_stat(data.special_attack_base)
	special_defense = calc_stat(data.special_defense_base)
	speed = calc_stat(data.speed_base)

func calc_hp(base: int) -> int:
	return calc_hp_static(base, level, weight)

func calc_stat(base: int) -> int:
	return calc_stat_static(base, level)

# Versões static das mesmas fórmulas — pra quem precisa calcular o HP/stat de
# uma unidade SEM instanciar a cena Unit inteira (ex: party_screen.gd, que só
# quer mostrar "HP máximo no nível X" pra cada UnitData do roster, fora de
# qualquer batalha). calc_hp()/calc_stat() acima só existem por conveniência,
# chamando essas com o level/weight da própria instância.
static func calc_hp_static(base: int, unit_level: int, unit_weight: int) -> int:
	@warning_ignore("integer_division")
	return (2 * base * unit_level) / 100 + unit_level * unit_weight + 10

static func calc_stat_static(base: int, unit_level: int) -> int:
	@warning_ignore("integer_division")
	return (2 * base * unit_level) / 100 + 5

# Soma exp acumulada (xp) e sobe de nível quantas vezes for preciso — um
# ganho grande pode subir mais de 1 nível de uma vez, por isso o "while" em
# vez de um "if". Usa o grupo de crescimento de data (ver ExpGroups). Ao
# subir de nível, o hp_current sobe junto na mesma quantidade que o hp_max
# aumentou (preserva o dano já tomado, em vez de curar tudo ou só esticar a
# barra) — por isso guarda hp_max ANTES de recalcular, pra saber a diferença.
func gain_exp(amount: int) -> void:
	xp += amount
	var leveled_up = false
	while level < ExpGroups.MAX_LEVEL and xp >= ExpGroups.total_exp_for_level(level + 1, data.growth_group):
		level += 1
		leveled_up = true
	if leveled_up:
		var hp_max_before = hp_max
		recalculate_stats()
		hp_current += hp_max - hp_max_before
		update_health_bar()
	sync_to_data()

func _ready() -> void:
	anim.animation_finished.connect(_on_attack_animation_finished)
	_status_emote_rest_position = status_emote.position

# Chamado toda vez que UMA animação do AnimatedSprite2D termina (só as que têm
# loop=false disparam isso — idle/walk são loop=true e nunca "terminam").
# Ou seja, na prática só as animações de ataque/hurt chegam aqui.
# Se a unidade está morrendo (is_dying), controla a sequência de morte:
# repete hurt_<dir> por DEATH_HURT_CYCLES voltas e só então tira a unidade de
# cena. Fora disso, é o caso normal — só volta pro idle olhando na direção em
# que a unidade ficou (facing não muda durante o ataque).
func _on_attack_animation_finished() -> void:
	if is_dying:
		death_hurt_cycles_left -= 1
		if death_hurt_cycles_left <= 0:
			queue_free()
		else:
			anim.play("hurt_" + facing)
		return
	# Flinched: em vez de voltar pro idle normal, continua exibindo hurt_<dir>
	# até a condição ser curada (ver begin_current_turn em battle.gd, que
	# cura Flinched bem no início do turno seguinte) — hurt_<dir> tem
	# loop=false, então sem isso esse mesmo sinal (animation_finished) já
	# devolveria pro idle sozinho assim que o hurt tocasse uma vez.
	if status_condition == "Flinched":
		_play_anim("hurt_" + facing)
		return
	_play_anim(_idle_anim_name())

func init(start_pos: Vector2i, initial_facing: String = "down") -> void:
	grid_pos = start_pos
	position = cell_to_position(grid_pos)
	facing = initial_facing
	# hp_current NÃO é resetado aqui — já vem certo de apply_persisted_data()
	# (dano de batalhas anteriores) ou apply_fresh_data() (cheio), chamado
	# antes disso. Resetar aqui apagaria a persistência de HP.
	_play_anim(_idle_anim_name())
	update_health_bar()

# Ajusta a largura do retângulo de preenchimento pra refletir hp_current/hp_max,
# e a cor dele conforme a faixa de HP (verde -> amarelo -> vermelho).
func update_health_bar() -> void:
	var ratio = 0.0
	if hp_max > 0:
		ratio = clamp(float(hp_current) / float(hp_max), 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	if ratio < 0.25:
		health_bar_fill.color = HEALTH_COLOR_LOW
	elif ratio < 0.5:
		health_bar_fill.color = HEALTH_COLOR_MID
	else:
		health_bar_fill.color = HEALTH_COLOR_HIGH

# Converte uma célula do grid para a posição de pixel do CENTRO dessa célula.
# O AnimatedSprite2D é desenhado centrado na origem do nó (comportamento padrão),
# então o nó precisa ficar no centro da célula (x*TILE + metade, y*TILE + metade),
# não no canto (x*TILE, y*TILE). Era isso que empurrava a sprite pra ponta da célula.
func cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2.0, cell.y * TILE_SIZE + TILE_SIZE / 2.0)

# amount já vem PRONTO (a fórmula de dano, calculada em battle.gd, já leva
# ataque/defesa em conta) — aqui só desconta do HP, sem mitigar de novo.
func take_damage(amount: int) -> void:
	hp_current -= amount
	update_health_bar()
	sync_to_data()
	# Só inimigos — a barra de vida deles está escondida (ver mark_as_enemy),
	# então esse número é o feedback de dano que sobrou pro jogador. Aliados
	# já têm a própria barra visível, não precisam do popup também.
	if is_enemy:
		show_damage_popup(amount)
	# Berry só entra em ação se a unidade sobreviveu ao golpe (hp_current > 0)
	# — abaixo de 50% de HP, não desmaiada. Ver _check_berry_auto_use().
	if hp_current > 0:
		_check_berry_auto_use()
	if hp_current <= 0 and not is_dying:
		die()

# Toda categoria "Berry" com heal_amount > 0 se auto-consome quando o HP da
# unidade cai abaixo de 50% (ver ItemData.category/heal_amount) — cura
# heal_amount e some do loadout (data.slots[i] = null), igual um item de
# verdade sendo gasto. Só a PRIMEIRA Berry encontrada nos slots é usada (se
# a unidade carregar duas por algum motivo, a segunda fica pra próxima vez
# que o HP cair abaixo de 50% de novo).
#
# is_enemy: trava por DESIGN, não mais por segurança de dados — desde que
# apply_fresh_data() passou a duplicar UnitData pra montar o loadout
# automático (ver get_recent_loadout()), mutar data.slots de um inimigo já
# não vaza mais pro catálogo compartilhado. A trava continua porque inimigo
# SELVAGEM nunca carrega item nenhum (loadout vem só do learnset — ataques e
# Habilidades, nunca ItemData): só times de TREINADOR (feature futura, loadout
# montado à mão pelo design) vão poder ter Berry/item equipado. Até lá, essa
# condição aqui é redundante com a ausência de itens no loadout, mas serve de
# documentação da regra e trava de segurança se algo mudar antes da hora.
func _check_berry_auto_use() -> void:
	if is_enemy or data == null or hp_max <= 0:
		return
	if float(hp_current) / float(hp_max) >= 0.5:
		return
	for i in data.slots.size():
		var item = data.slots[i]
		if item is ItemData and item.category == "Berry" and item.heal_amount > 0:
			hp_current = min(hp_current + item.heal_amount, hp_max)
			data.slots[i] = null
			slot_uses[i] = 0
			update_health_bar()
			sync_to_data()
			return

# Multiplica accuracy_multiplier de todo ItemData equipado no loadout (ex:
# Focus Band, ver ItemData.accuracy_multiplier) e o x0.5 de Blind — usado por
# battle.gd::execute_attack no roll de acerto de verdade (ver comentário em
# AttackData.accuracy). Sem item nenhum equipado e sem Blind, retorna 1.0
# (sem efeito nenhum no roll).
func get_accuracy_multiplier() -> float:
	if data == null:
		return 1.0
	var multiplier = 1.0
	for action in data.slots:
		if action is ItemData:
			multiplier *= action.accuracy_multiplier
	if status_condition == "Blind":
		multiplier *= 0.5
	return multiplier

# ---------- Stat Stages: API pública ----------

# Emitido só quando o stat alterado é "speed" (ver modify_stat_stage) — quem
# ouve isso é battle.gd (conectado em spawn_player_units_staged/
# spawn_enemies), pra reordenar a fila de turnos na hora em que a velocidade
# de alguém muda no meio da rodada, em vez de só na próxima vez que
# start_turn_order() rodar (ver battle.gd::reorder_turn_queue_by_speed).
signal speed_changed

# Some por enquanto sem nenhum ataque chamando isso — é o "cano" que os
# futuros efeitos secundários (ex: "Growl reduz Attack em 1") vão usar.
func modify_stat_stage(stat: String, delta: int) -> void:
	if not STAGE_STATS.has(stat):
		return
	stat_stages[stat] = clamp(stat_stages.get(stat, 0) + delta, STAT_STAGE_MIN, STAT_STAGE_MAX)
	if stat == "speed":
		speed_changed.emit()

# Stat "de verdade" (attack/defense/special_attack/special_defense/speed) já
# multiplicado pelo estágio atual (ver STAT_STAGE_MULTIPLIERS) e travado entre
# STAT_MIN e STAT_MAX. Pra stats fora de STAGE_STATS (ex: chamar com "hp" por
# engano), devolve o valor cru sem tocar em nada — HP/peso nunca têm estágio.
# `get(stat)` lê a var pelo NOME (string) — funciona porque attack/defense/
# etc. são vars comuns declaradas nesta mesma classe.
func get_effective_stat(stat: String) -> int:
	return _effective_stat_with_stage(stat, stat_stages.get(stat, 0))

# ---------- Stat Stages: versões pra Acerto Crítico ----------
# Um Acerto Crítico (ver battle.gd::calculate_damage/CRITICAL_HIT_CHANCE)
# ignora estágios DESFAVORÁVEIS pra quem ataca — nunca os favoráveis. Ou
# seja: um Attack/Sp.Atk REBAIXADO (estágio negativo) do atacante não conta
# pro crítico (age como se estivesse em 0), mas um Attack/Sp.Atk AUMENTADO
# (estágio positivo) continua contando normalmente. Mesma ideia espelhada pro
# defensor: uma Defense/Sp.Def AUMENTADA (positiva) não protege contra o
# crítico, mas uma REBAIXADA (negativa) continua penalizando normalmente.
# As duas funções abaixo só diferem em qual METADE da tabela elas zeram —
# _effective_stat_with_stage faz o cálculo de verdade (mesmo usado por
# get_effective_stat, só que com o estágio já filtrado).
func get_offensive_stat_for_crit(stat: String) -> int:
	var stage: int = max(stat_stages.get(stat, 0), 0)   # ignora estágio < 0
	return _effective_stat_with_stage(stat, stage)

func get_defensive_stat_for_crit(stat: String) -> int:
	var stage: int = min(stat_stages.get(stat, 0), 0)   # ignora estágio > 0
	return _effective_stat_with_stage(stat, stage)

func _effective_stat_with_stage(stat: String, stage: int) -> int:
	var base_value: int = get(stat)
	if not STAGE_STATS.has(stat):
		return base_value
	var multiplier: float = STAT_STAGE_MULTIPLIERS.get(stage, 1.0)
	return clamp(int(base_value * multiplier), STAT_MIN, STAT_MAX)

# ---------- Status Conditions: API pública ----------

# "Status Conditions não se acumulam... a antiga se preserva" — cobre os dois
# casos do design (condição NOVA tentando substituir uma diferente, e a MESMA
# condição tentando reiniciar o próprio contador) com uma regra só: se já tem
# alguma coisa, essa chamada não faz nada. Devolve se conseguiu aplicar, útil
# pra quem chamar (ex: efeito secundário futuro) saber se "gastou" o efeito.
# Também recusa se a unidade for de um tipo imune a essa condição (ver
# STATUS_TYPE_IMMUNITIES/is_immune_to_status) — mesma sinalização (false) que
# o caso "já tem outra condição", quem chamou não precisa distinguir os dois.
func apply_status_condition(new_status: String) -> bool:
	if status_condition != "":
		return false
	if is_immune_to_status(new_status):
		return false
	status_condition = new_status
	status_turns_left = STATUS_DURATIONS.get(new_status, -1)
	_on_status_condition_changed()
	return true

func cure_status_condition() -> void:
	status_condition = ""
	status_turns_left = -1
	_on_status_condition_changed()

# Ex: Charmander (Fire) tentando ser Burned — devolve true, apply_status_
# condition recusa antes mesmo de aplicar. data == null (unidade ainda não
# totalmente inicializada) nunca é imune a nada, só por segurança.
func is_immune_to_status(status: String) -> bool:
	if data == null:
		return false
	var immune_types: Array = STATUS_TYPE_IMMUNITIES.get(status, [])
	for t in immune_types:
		if data.types.has(t):
			return true
	return false

func can_move() -> bool:
	return not MOVEMENT_BLOCKING_STATUS.has(status_condition)

func can_attack() -> bool:
	return not ATTACK_BLOCKING_STATUS.has(status_condition)

# Reage à MUDANÇA de status_condition (chamado por apply_status_condition e
# cure_status_condition — nunca direto): tint, tremor de Paralyzed, emote de
# Confused/Blind/Burned e a animação própria de quem tem uma (Frozen pausa
# tudo, Asleep dorme, Flinched fica com cara de dor). Poisoned não mexe em
# animação nenhuma, só na cor (STATUS_TINT_COLORS já cobre isso via
# _refresh_tint).
func _on_status_condition_changed() -> void:
	_refresh_tint()

	if status_condition != "Paralyzed":
		_stop_paralyze_shake()
	if not STATUS_EMOTE_TEXTURES.has(status_condition) and not STATUS_EMOTE_FRAME_ARRAYS.has(status_condition):
		_stop_status_emote()

	match status_condition:
		"Frozen":
			# pause() (não stop()) mantém o frame atual visível — "não
			# performa animação ao fazer nada" enquanto congelada. Ver
			# _play_anim(), que bloqueia qualquer NOVO play() vindo de
			# outro lugar (attack/hurt/walk/idle) enquanto isso durar.
			anim.pause()
		"Asleep":
			# Só existe a variação "_down" desse sprite sheet (foi feito
			# originalmente pro retrato da tela de Party, sem depender de
			# direção) — por isso ignora `facing` aqui, diferente de
			# idle_<dir>/hurt_<dir>/etc.
			_play_anim("sleep_down")
		"Flinched":
			_play_anim("hurt_" + facing)
		"Paralyzed":
			_start_paralyze_shake()
		"Confused", "Blind", "Burned":
			_start_status_emote(status_condition)
		"":
			# Cura de QUALQUER condição — importante sobretudo saindo de
			# Frozen (anim.play(nome) sempre retoma mesmo se estava
			# pausado) e de Asleep/Flinched (volta pro idle de verdade,
			# não só continua o sleep/hurt que estava tocando).
			_play_anim(_idle_anim_name())

# Nome da animação de "descanso" a usar AGORA, olhando pra 3 coisas: se a
# espécie tem hover_<dir> (voa/flutua parada em vez de ficar em pé — ex:
# espécies Flying puramente aéreas, que nem chegam a ter idle_<dir> nenhum),
# se ela tem idle_<dir> de verdade, e o estado ATUAL de data.grounded (pode
# ter sido forçado a true por um efeito de ataque/item/habilidade — nenhum
# ainda faz isso, mas a checagem já fica pronta pra quando algum fizer).
# Regras (pedidas pelo usuário):
#  1. Espécie sem hover_<dir> nenhum -> sempre idle_<dir>, como sempre foi
#     (imensa maioria das espécies hoje).
#  2. Espécie com hover_<dir> E efetivamente grounded (data.grounded==true,
#     seja de base ou forçado) E tem idle_<dir> de verdade -> usa idle_<dir>
#     normalmente, igual qualquer outra espécie grounded.
#  3. Espécie com hover_<dir> e (não-grounded OU grounded mas SEM idle_<dir>
#     nenhum) -> usa hover_<dir> "como se nada tivesse mudado" (mesma pose
#     flutuando — só a flag grounded em si que já mudou, pra fins de
#     terreno/fluido, ver battle.gd::generate_fluid).
func _idle_anim_name() -> String:
	var idle_name = "idle_" + facing
	var hover_name = "hover_" + facing
	if data == null or not anim.sprite_frames.has_animation(hover_name):
		return idle_name
	if data.grounded and anim.sprite_frames.has_animation(idle_name):
		return idle_name
	return hover_name

# Envelope fino sobre anim.play(): toda chamada de animação REATIVA (ataque,
# hurt, idle, walk) passa por aqui em vez de chamar anim.play() direto, pra
# respeitar Frozen ("não performa animação ao fazer nada") num lugar só, em
# vez de espalhar `if status_condition == "Frozen": return` em cada função.
# A sequência de MORTE (die()/_on_attack_animation_finished quando is_dying)
# passa direto por anim.play(), sem esse filtro — morrer não é opcional.
func _play_anim(anim_name: String) -> void:
	if status_condition == "Frozen":
		return
	anim.play(anim_name)

func _start_paralyze_shake() -> void:
	_stop_paralyze_shake()
	_status_shake_tween = create_tween()
	_status_shake_tween.set_loops()
	_status_shake_tween.tween_property(anim, "position:x", PARALYZE_SHAKE_OFFSET, PARALYZE_SHAKE_STEP)
	_status_shake_tween.tween_property(anim, "position:x", -PARALYZE_SHAKE_OFFSET, PARALYZE_SHAKE_STEP * 2)
	_status_shake_tween.tween_property(anim, "position:x", 0.0, PARALYZE_SHAKE_STEP)

func _stop_paralyze_shake() -> void:
	if _status_shake_tween != null and _status_shake_tween.is_valid():
		_status_shake_tween.kill()
	_status_shake_tween = null
	anim.position.x = 0.0

# Liga o emote de status_emote (nó Sprite2D acima da cabeça, ver unit.tscn).
# Dois formatos possíveis (ver comentário grande de STATUS_EMOTE_TEXTURES/
# STATUS_EMOTE_FRAME_ARRAYS lá em cima):
# - STATUS_EMOTE_FRAME_ARRAYS: quadros já prontos, um arquivo por quadro
#   (Burned) — troca status_emote.texture direto, sem AtlasTexture nenhum.
# - STATUS_EMOTE_TEXTURES: uma tira só, fatiada em quadros QUADRADOS igual
#   Projectile/ImpactEffect (tamanho calculado da própria textura).
# O avanço de quadro em si acontece em _process() — aqui só prepara o estado
# inicial e mostra o nó. Se a condição não tiver emote cadastrado em NENHUM
# dos dois dicionários, não faz nada.
#
# frame_count <= 1 (imagem única, sem tira — ex: Foresight_Glass de Blind)
# liga o balanço vertical (_start_emote_bob) em vez do ciclo de quadros, já
# que não há quadro nenhum pra trocar.
func _start_status_emote(status: String) -> void:
	_status_emote_frame_index = 0
	_status_emote_frame_timer = 0.0
	_status_emote_raw_frames = STATUS_EMOTE_FRAME_ARRAYS.get(status, EMPTY_TEXTURE_ARRAY)

	if not _status_emote_raw_frames.is_empty():
		_status_emote_frame_count = _status_emote_raw_frames.size()
		_status_emote_atlas = null
		status_emote.texture = _status_emote_raw_frames[0]
	else:
		var texture: Texture2D = STATUS_EMOTE_TEXTURES.get(status)
		if texture == null:
			return
		_status_emote_frame_size = int(texture.get_height())
		_status_emote_frame_count = max(1, int(texture.get_width()) / _status_emote_frame_size)
		_status_emote_atlas = AtlasTexture.new()
		_status_emote_atlas.atlas = texture
		_status_emote_atlas.region = Rect2(0, 0, _status_emote_frame_size, _status_emote_frame_size)
		status_emote.texture = _status_emote_atlas

	status_emote.position = _status_emote_rest_position
	status_emote.visible = true

	if _status_emote_frame_count <= 1:
		_start_emote_bob()
	else:
		_stop_emote_bob()

func _stop_status_emote() -> void:
	status_emote.visible = false
	_status_emote_raw_frames = []
	_stop_emote_bob()

# Balanço vertical suave e contínuo (sobe/desce EMOTE_BOB_OFFSET pixels em
# volta da posição de repouso) — usado só por emotes de imagem única, que
# não têm quadros próprios pra parecer "vivos" sozinhos (ver comentário em
# _start_status_emote).
func _start_emote_bob() -> void:
	_stop_emote_bob()
	var base_y = _status_emote_rest_position.y
	_emote_bob_tween = create_tween()
	_emote_bob_tween.set_loops()
	_emote_bob_tween.set_trans(Tween.TRANS_SINE)
	_emote_bob_tween.tween_property(status_emote, "position:y", base_y - EMOTE_BOB_OFFSET, EMOTE_BOB_STEP)
	_emote_bob_tween.tween_property(status_emote, "position:y", base_y + EMOTE_BOB_OFFSET, EMOTE_BOB_STEP * 2)
	_emote_bob_tween.tween_property(status_emote, "position:y", base_y, EMOTE_BOB_STEP)

func _stop_emote_bob() -> void:
	if _emote_bob_tween != null and _emote_bob_tween.is_valid():
		_emote_bob_tween.kill()
	_emote_bob_tween = null
	status_emote.position = _status_emote_rest_position

# Quanto dano o tick de fim de turno causa agora (só Poisoned, por enquanto).
# battle.gd::apply_end_of_turn_status chama isso e decide o que fazer com o
# resultado (aplicar o dano, checar morte, etc.) — essa função aqui só
# calcula o número, não mexe em hp_current nem dispara die().
func get_status_tick_damage() -> int:
	if status_condition == "Poisoned":
		@warning_ignore("integer_division")
		return hp_max * POISON_DAMAGE_PERCENT / 100
	return 0

# statusBonus da fórmula de captura (ver battle.gd::resolve_capture): 1.0
# sem status nenhum, 2.0 se Asleep/Frozen (a unidade não pode reagir, mais
# fácil de capturar), 1.5 pra qualquer outro status (ainda mais fácil que
# saudável, só que menos que Asleep/Frozen). Valores fixos que vieram
# direto da especificação da fórmula, não calculados de nenhum outro campo.
func get_capture_status_bonus() -> float:
	match status_condition:
		"":
			return 1.0
		"Asleep", "Frozen":
			return 2.0
		_:
			return 1.5

# Sequência de morte: repete hurt_<dir> por DEATH_HURT_CYCLES voltas enquanto
# pisca a opacidade (Tween em loop, some do modulate.a sem mexer no tint de
# mark_as_enemy), e só remove a unidade da cena quando a última volta termina
# — ver _on_attack_animation_finished(), que conta as voltas.
func die() -> void:
	is_dying = true
	death_hurt_cycles_left = DEATH_HURT_CYCLES
	_stop_paralyze_shake()   # não faz sentido continuar tremendo durante a sequência de morte
	_stop_status_emote()     # nem flutuando um "?" por cima enquanto pisca sumindo

	var blink_tween = create_tween()
	blink_tween.set_loops()
	blink_tween.tween_property(self, "modulate:a", DEATH_BLINK_ALPHA, DEATH_BLINK_INTERVAL)
	blink_tween.tween_property(self, "modulate:a", 1.0, DEATH_BLINK_INTERVAL)

	anim.play("hurt_" + facing)

# Reposiciona instantaneamente, sem animação de caminhada — usado pelo Undo.
func teleport_to(target_pos: Vector2i) -> void:
	grid_pos = target_pos
	position = cell_to_position(target_pos)
	is_moving = false
	facing = "down"
	_play_anim(_idle_anim_name())

# Vira no próprio eixo pra encarar target_cell, sem se mover — usado durante
# a mira de ataque, pra unidade "seguir" o tile destacado com o olhar.
func face_towards(target_cell: Vector2i) -> void:
	if target_cell == grid_pos:
		return
	facing = get_direction_suffix(target_cell - grid_pos)
	if not is_moving:
		_play_anim(_idle_anim_name())

# Toca a animação de ataque na direção atual (facing já deve ter sido ajustado
# por face_towards antes de chamar isso). Ataques físicos usam "attack_<dir>".
# Ataques especiais usam "shoot_<dir>" ou "charge_<dir>" dependendo do bicho —
# nem toda espécie tem as duas, então checa qual existe no SpriteFrames antes
# de tocar (0004 por exemplo só tem "charge", não "shoot").
func play_attack_animation(is_special: bool) -> void:
	var prefix = "attack"
	if is_special:
		if anim.sprite_frames.has_animation("shoot_" + facing):
			prefix = "shoot"
		elif anim.sprite_frames.has_animation("charge_" + facing):
			prefix = "charge"
	_play_anim(prefix + "_" + facing)

# Toca a animação de "levar dano" na direção atual (facing já deve ter sido
# ajustado por face_towards antes de chamar isso, pra unidade encarar quem
# bateu). Todas as espécies têm "hurt_<dir>", diferente de shoot/charge.
func play_hurt_animation() -> void:
	_play_anim("hurt_" + facing)

# Caminho restante (lista de células, sem a origem) que a unidade ainda
# precisa cruzar VISUALMENTE — preenchido por move_along_path(). walk_from
# guarda de onde ela partiu na perna atual, só pra saber a direção (facing)
# de cada trecho.
var walk_path: Array[Vector2i] = []
var walk_from: Vector2i = Vector2i.ZERO

# Emitido sempre que grid_pos muda pra uma célula NOVA via move_along_path
# (ou seja, todo movimento de verdade — inclusive o "caminho de 1 célula" do
# deploy, ver move_to() logo abaixo) — mesmo espírito de Player.tile_entered
# no overworld (ver player.gd/test.gd). battle.gd escuta isso em CADA
# unidade (ver spawn_player_units_staged/spawn_enemies) pra aplicar o efeito
# de pisar num tile de fluido (ex: Burned na lava — ver current_battle_
# tileset.fluid_status_on_enter/_on_unit_tile_entered), sem precisar que
# quem chama move_along_path/move_to se lembre de checar isso toda vez.
signal tile_entered(cell: Vector2i)

# Anda célula por célula por `path` (calculado por battle.gd get_path_to(),
# via BFS) em vez de deslizar em linha reta da origem até o destino — era
# isso que fazia a unidade atravessar visualmente paredes/fluido/outras
# unidades mesmo quando a distância "gasta" já respeitava o desvio real.
# grid_pos (posição LÓGICA, usada por ocupação/turno/etc.) muda pro destino
# final IMEDIATAMENTE, igual sempre foi — só a posição visual (position) é
# que percorre o caminho aos poucos, célula por célula. tile_entered emite
# com a posição LÓGICA final (não espera o slide visual terminar) — mesmo
# critério de "a unidade já está ali" usado no resto do arquivo.
func move_along_path(path: Array[Vector2i]) -> void:
	if path.is_empty():
		return
	walk_from = grid_pos
	grid_pos = path[path.size() - 1]
	walk_path = path.duplicate()
	is_moving = true
	_face_next_leg()
	tile_entered.emit(grid_pos)

# Atalho pra um "caminho" de uma célula só — usado no posicionamento de
# deploy (place_selected_unit em battle.gd), onde não faz sentido pathfinding
# de verdade: a unidade vem de fora do mapa (área de staging), não existe
# grid pra desviar de nada até lá.
func move_to(target_pos: Vector2i) -> void:
	move_along_path([target_pos])

func _face_next_leg() -> void:
	var next_cell = walk_path[0]
	facing = get_direction_suffix(next_cell - walk_from)
	_play_anim("walk_" + facing)

func _process(delta: float) -> void:
	if is_moving:
		var next_cell = walk_path[0]
		var target = cell_to_position(next_cell)
		position = position.move_toward(target, MOVE_SPEED)
		if position == target:
			walk_from = next_cell
			walk_path.remove_at(0)
			if walk_path.is_empty():
				is_moving = false
				_play_anim(_idle_anim_name())
			else:
				_face_next_leg()

	# Avança o quadro do emote de status (ver _start_status_emote) — só
	# quando visível, senão ficaria contando tempo à toa pra ninguém ver.
	# Dois formatos (ver _start_status_emote): quadros prontos (raw_frames,
	# troca status_emote.texture direto) ou atlas fatiado de uma tira só.
	if status_emote.visible:
		_status_emote_frame_timer += delta
		if _status_emote_frame_timer >= STATUS_EMOTE_FRAME_DURATION:
			_status_emote_frame_timer -= STATUS_EMOTE_FRAME_DURATION
			_status_emote_frame_index = (_status_emote_frame_index + 1) % _status_emote_frame_count
			if not _status_emote_raw_frames.is_empty():
				status_emote.texture = _status_emote_raw_frames[_status_emote_frame_index]
			else:
				_status_emote_atlas.region = Rect2(_status_emote_frame_index * _status_emote_frame_size, 0, _status_emote_frame_size, _status_emote_frame_size)

# Traduz um deslocamento em células (dx, dy) pra uma das 8 direções do sprite sheet.
# dy positivo = pra baixo, dx positivo = pra direita (convenção padrão do Godot 2D).
func get_direction_suffix(delta: Vector2i) -> String:
	var dx = sign(delta.x)
	var dy = sign(delta.y)
	if dx == 0 and dy == 0:
		return facing
	if dx == 0 and dy > 0:
		return "down"
	if dx > 0 and dy > 0:
		return "down_right"
	if dx > 0 and dy == 0:
		return "right"
	if dx > 0 and dy < 0:
		return "up_right"
	if dx == 0 and dy < 0:
		return "up"
	if dx < 0 and dy < 0:
		return "up_left"
	if dx < 0 and dy == 0:
		return "left"
	return "down_left"
