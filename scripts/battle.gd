extends Node2D

const MAP_WIDTH = 20
const MAP_HEIGHT = 14
const TILE_SIZE = 24

# Zona de deploy: 1/4 do mapa, do lado esquerdo (colunas 0..DEPLOY_ZONE_WIDTH-1).
# Divisão inteira é proposital (queremos um número de colunas, não fração).
@warning_ignore("integer_division")
const DEPLOY_ZONE_WIDTH = MAP_WIDTH / 4

const UNIT_SCENE: PackedScene = preload("res://scenes/actors/unit.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/effects/projectile.tscn")
const IMPACT_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/impact_effect.tscn")
const CAPTURE_BALL_SCENE: PackedScene = preload("res://scenes/effects/capture_ball.tscn")
const STAT_CHANGE_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/stat_change_effect.tscn")
const CAST_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/cast_effect.tscn")

# Item forçado no loadout de TODA unidade de um time "Rocket" (ver
# spawn_enemies()/_spawn_enemy_unit) — pedido do usuário: "All units from
# Rocket teams will have 1 Rocket Ball item action in their loadout".
const ROCKET_BALL_ITEM: ItemData = preload("res://data/items/rocketball.tres")

# Volta de Unit.facing (string) pra um Vector2i de direção — o INVERSO de
# Unit.get_direction_suffix (delta -> string). Usada só por play_cast_effect
# (ver comentário lá): a partir de qual tile o CastEffect nasce/viaja.
const FACING_TO_DIR := {
	"down": Vector2i(0, 1),
	"down_right": Vector2i(1, 1),
	"right": Vector2i(1, 0),
	"up_right": Vector2i(1, -1),
	"up": Vector2i(0, -1),
	"up_left": Vector2i(-1, -1),
	"left": Vector2i(-1, 0),
	"down_left": Vector2i(-1, 1),
}

# preload em vez de confiar no class_name global — mesmo motivo do unit.gd.
const ExpGroups = preload("res://scripts/exp_groups.gd")
const TypeChart = preload("res://scripts/type_chart.gd")
const UnitScript = preload("res://scripts/unit.gd")

# ---------- Efeito visual de mudança de stat (ver AttackData.stat_change_stat
# e scripts/stat_change_effect.gd) ----------
# Duas artes genéricas (sobe/desce), cada uma como VÁRIOS arquivos separados
# — o usuário adicionou em assets/sprites/Status/statChangeUp (15 quadros,
# 000-014) e statChangeDown (11 quadros, 000-010). Mesmo formato "vários
# arquivos" de PROJECTILE_SCENE/IMPACT_EFFECT_SCENE (ver comentário nos
# scripts deles) — cada Texture2D é um quadro inteiro.
const STAT_CHANGE_UP_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Status/statChangeUp/000.png"),
	preload("res://assets/sprites/Status/statChangeUp/001.png"),
	preload("res://assets/sprites/Status/statChangeUp/002.png"),
	preload("res://assets/sprites/Status/statChangeUp/003.png"),
	preload("res://assets/sprites/Status/statChangeUp/004.png"),
	preload("res://assets/sprites/Status/statChangeUp/005.png"),
	preload("res://assets/sprites/Status/statChangeUp/006.png"),
	preload("res://assets/sprites/Status/statChangeUp/007.png"),
	preload("res://assets/sprites/Status/statChangeUp/008.png"),
	preload("res://assets/sprites/Status/statChangeUp/009.png"),
	preload("res://assets/sprites/Status/statChangeUp/010.png"),
	preload("res://assets/sprites/Status/statChangeUp/011.png"),
	preload("res://assets/sprites/Status/statChangeUp/012.png"),
	preload("res://assets/sprites/Status/statChangeUp/013.png"),
	preload("res://assets/sprites/Status/statChangeUp/014.png"),
]
const STAT_CHANGE_DOWN_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Status/statChangeDown/000.png"),
	preload("res://assets/sprites/Status/statChangeDown/001.png"),
	preload("res://assets/sprites/Status/statChangeDown/002.png"),
	preload("res://assets/sprites/Status/statChangeDown/003.png"),
	preload("res://assets/sprites/Status/statChangeDown/004.png"),
	preload("res://assets/sprites/Status/statChangeDown/005.png"),
	preload("res://assets/sprites/Status/statChangeDown/006.png"),
	preload("res://assets/sprites/Status/statChangeDown/007.png"),
	preload("res://assets/sprites/Status/statChangeDown/008.png"),
	preload("res://assets/sprites/Status/statChangeDown/009.png"),
	preload("res://assets/sprites/Status/statChangeDown/010.png"),
]

# "Máscara de cor" por stat, pedida pelo usuário — aplicada como modulate do
# Sprite2D do efeito (ver StatChangeEffect.play(), mesma técnica de
# Unit._refresh_tint()). Sp. Defense = Branco = Color.WHITE = sem tint
# nenhum (a arte já sai "correta" nesse caso).
const STAT_CHANGE_TINTS := {
	"speed": Color(0.3, 0.55, 1.0),             # Azul
	"defense": Color(0.35, 0.85, 0.35),         # Verde
	"special_defense": Color(1.0, 1.0, 1.0),    # Branco
	"attack": Color(1.0, 0.3, 0.3),             # Vermelho
	"special_attack": Color(0.75, 0.35, 0.95),  # Roxo
}

# Nome exibido de cada stat alterável (ver Unit.STAGE_STATS) — usado nas
# mensagens de log de execute_status_attack/apply_stat_change e no tooltip
# de ataque (_build_attack_tooltip).
const STAT_DISPLAY_NAMES := {
	"attack": "Attack",
	"defense": "Defense",
	"special_attack": "Sp. Atk",
	"special_defense": "Sp. Def",
	"speed": "Speed",
}

# Tileset de verdade vai só até x=17, y=7 (o .tres declara coordenadas além
# disso, mas são sobra sem imagem por trás — ficam em branco se usadas).
# Qualquer tile com x>11 dentro desse limite é "chão" e pode ser usado à
# vontade pra dar variedade — exceto (17,2), que é um slot vazio (sem arte).
# Colunas 0..11 ficam de fora (são as paredes e outras peças com significado próprio).
const GROUND_ATLAS_MIN_X = 12
const GROUND_ATLAS_MAX_X = 17
const GROUND_ATLAS_MAX_Y = 7
const GROUND_EMPTY_TILE = Vector2i(17, 2)

# Preenchido em _ready() por build_ground_variants() — não dá pra ser const
# porque é montado com um loop.
var ground_variants: Array[Vector2i] = []

func build_ground_variants() -> void:
	ground_variants.clear()
	# Algumas peças de FLUID_DETAIL (ex: (13,7), (14,7)) caem dentro da faixa
	# de coordenadas de chão — exclui elas daqui pra não virarem "chão" aleatório
	# num tile que na verdade é fluido (água/lava/buraco, depende do
	# BattleTileset sorteado — ver current_battle_tileset).
	var fluid_detail_positions := {}
	for entry in FLUID_DETAIL:
		fluid_detail_positions[entry["pos"]] = true
	for x in range(GROUND_ATLAS_MIN_X, GROUND_ATLAS_MAX_X + 1):
		for y in range(GROUND_ATLAS_MAX_Y + 1):
			var coord = Vector2i(x, y)
			if coord == GROUND_EMPTY_TILE:
				continue
			if fluid_detail_positions.has(coord):
				continue
			ground_variants.append(coord)

# Bloco de parede 3x3 (autotile "de mão"): cantos + bordas retas + preenchimento.
# Coordenadas descritas pelo usuário olhando o tileset.
const WALL_TOP_LEFT = Vector2i(0, 0)
const WALL_TOP = Vector2i(1, 0)
const WALL_TOP_RIGHT = Vector2i(2, 0)
const WALL_LEFT = Vector2i(0, 1)
const WALL_FILL = Vector2i(1, 1)      # parede sólida (cercada nos 4 lados) — reservada pra obstáculos internos

const WALL_RIGHT = Vector2i(2, 1)
const WALL_BOTTOM_LEFT = Vector2i(0, 2)
const WALL_BOTTOM = Vector2i(1, 2)
const WALL_BOTTOM_RIGHT = Vector2i(2, 2)

# Mesmo bloco 3x3 acima, mas como array — na mesma ordem de papel que
# FLUID_SET_A (índices ROLE_*), pra poder usar pick_role()/pick_detail_tile()
# genéricos com parede também.
const WALL_SET_A: Array[Vector2i] = [
	WALL_TOP_LEFT, WALL_TOP, WALL_TOP_RIGHT,
	WALL_LEFT, WALL_FILL, WALL_RIGHT,
	WALL_BOTTOM_LEFT, WALL_BOTTOM, WALL_BOTTOM_RIGHT,
]

# Peças de detalhe da parede (cantos côncavos, T-junctions, pontas soltas,
# isolada) — mesmo formato de FLUID_DETAIL. A arte da parede é a mesma
# disposição do fluido, só que 6 colunas mais à esquerda (fluido ocupa
# x=6..11, parede ocupa x=0..5) — por isso é montada em build_wall_detail()
# a partir de FLUID_DETAIL, em vez de escrita à mão de novo (evita
# duplicar/errar as 38 peças). Não pode ser const porque precisa de um loop
# pra montar.
var wall_detail: Array[Dictionary] = []

func build_wall_detail() -> void:
	wall_detail.clear()
	for entry in FLUID_DETAIL:
		wall_detail.append({
			"pos": entry["pos"] - Vector2i(6, 0),
			"up": entry["up"], "down": entry["down"],
			"left": entry["left"], "right": entry["right"],
			"diag": entry["diag"].duplicate(),
		})

# Blocos de fluido 3x3 (mesmo esquema autotile do bloco de parede: cantos,
# bordas retas e preenchimento) — é o terço central do atlas (água na
# tinyWoods, lava na mtBlaze, buraco num futuro terceiro tileset: MESMA
# coordenada em qualquer um deles, ver comentário grande em
# BattleTileset/current_battle_tileset). Cada array segue sempre a mesma
# ordem de papéis:
# [topo-esq, topo, topo-dir, esq, preenchimento, dir, base-esq, base, base-dir]
# — ROLE_* abaixo indexa essa ordem.
const FLUID_SET_A: Array[Vector2i] = [
	Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0),
	Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1),
	Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2),
]

const ROLE_TOP_LEFT = 0
const ROLE_TOP = 1
const ROLE_TOP_RIGHT = 2
const ROLE_LEFT = 3
const ROLE_FILL = 4
const ROLE_RIGHT = 5
const ROLE_BOTTOM_LEFT = 6
const ROLE_BOTTOM = 7
const ROLE_BOTTOM_RIGHT = 8

# Conjunto "detalhado" em (9..11, 0..4): tiles específicos pra cantos côncavos,
# pontas soltas (conectadas a só 1 vizinho) e a peça isolada — casos que o
# esquema simples de 9 peças (FLUID_SET_A, só cantos convexos + borda reta +
# preenchimento) não cobre. Descrito pelo usuário tile a tile: up/down/left/
# right são os 4 vizinhos ortogonais; "diag" só lista uma diagonal quando os
# DOIS lados vizinhos a ela são true (nos outros casos already é falsa/irrelevante).
# (9,0) e (11,0) são espelhadas: canto côncavo baixo-direita vs baixo-esquerda.
const FLUID_DETAIL: Array[Dictionary] = [
	{"pos": Vector2i(9, 0), "up": false, "down": true, "left": false, "right": true,
		"diag": {"down_right": false}},
	{"pos": Vector2i(11, 0), "up": false, "down": true, "left": true, "right": false,
		"diag": {"down_left": false}},
	{"pos": Vector2i(10, 0), "up": false, "down": false, "left": true, "right": true, "diag": {}},
	{"pos": Vector2i(9, 1), "up": true, "down": true, "left": false, "right": false, "diag": {}},
	{"pos": Vector2i(10, 1), "up": false, "down": false, "left": false, "right": false, "diag": {}},
	{"pos": Vector2i(11, 1), "up": true, "down": false, "left": true, "right": false,
		"diag": {"up_left": false}},
	{"pos": Vector2i(9, 2), "up": true, "down": false, "left": false, "right": true,
		"diag": {"up_right": false}},
	{"pos": Vector2i(10, 2), "up": false, "down": true, "left": false, "right": false, "diag": {}},
	{"pos": Vector2i(9, 3), "up": false, "down": false, "left": false, "right": true, "diag": {}},
	{"pos": Vector2i(11, 3), "up": false, "down": false, "left": true, "right": false, "diag": {}},
	{"pos": Vector2i(10, 3), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": false, "down_left": false, "down_right": false}},
	{"pos": Vector2i(10, 4), "up": true, "down": false, "left": false, "right": false, "diag": {}},

	# Lote novo: interior de lagos grandes, cercado nos 4 lados, variando só
	# 1-2 cantos côncavos (a peça de preenchimento total, sem nenhum canto
	# côncavo, é FLUID_SET_A[ROLE_FILL] — não precisa entrada aqui).
	# Coordenadas com X-3 em relação à descrição original (usuário corrigiu).
	# IMPORTANTE: aqui os 4 cantos são sempre listados (true E false) — como
	# os 4 lados já são todos true, os 4 cantos são geometricamente relevantes,
	# então deixar um implícito (por omissão) criaria ambiguidade no match
	# contra outras peças dessa mesma família que só diferem num canto.
	{"pos": Vector2i(6, 3), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": false, "down_left": true, "down_right": false}},
	{"pos": Vector2i(7, 3), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": true, "down_left": false, "down_right": true}},
	{"pos": Vector2i(6, 4), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": false, "down_left": true, "down_right": true}},
	{"pos": Vector2i(7, 4), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": true, "down_left": false, "down_right": false}},
	{"pos": Vector2i(6, 5), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": true, "down_left": true, "down_right": false}},
	{"pos": Vector2i(7, 5), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": true, "down_left": false, "down_right": true}},
	{"pos": Vector2i(6, 6), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": false, "down_left": true, "down_right": true}},
	{"pos": Vector2i(7, 6), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": true, "down_left": true, "down_right": true}},
	{"pos": Vector2i(6, 7), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": false, "down_left": false, "down_right": true}},
	{"pos": Vector2i(7, 7), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": false, "down_left": true, "down_right": false}},
	{"pos": Vector2i(8, 7), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": true, "down_left": false, "down_right": false}},
	{"pos": Vector2i(9, 7), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": false, "down_left": false, "down_right": false}},
	{"pos": Vector2i(10, 7), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": true, "down_left": true, "down_right": false}},
	{"pos": Vector2i(11, 7), "up": true, "down": true, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": false, "down_left": false, "down_right": true}},

	# Lote 3: peças em T (3 lados abertos, 1 fechado) com cantos côncavos.
	# Só os 2 cantos do lado aberto são relevantes aqui (o lado fechado nunca
	# forma canto), então só esses 2 ficam listados — mas sempre os 2, true
	# ou false, pelo mesmo motivo do lote 2 (evitar ambiguidade no match).
	{"pos": Vector2i(8, 3), "up": false, "down": true, "left": true, "right": true,
		"diag": {"down_left": false, "down_right": false}},
	{"pos": Vector2i(10, 5), "up": false, "down": true, "left": true, "right": true,
		"diag": {"down_left": true, "down_right": false}},
	{"pos": Vector2i(11, 5), "up": false, "down": true, "left": true, "right": true,
		"diag": {"down_left": false, "down_right": true}},
	{"pos": Vector2i(8, 4), "up": true, "down": false, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": false}},
	{"pos": Vector2i(10, 6), "up": true, "down": false, "left": true, "right": true,
		"diag": {"up_left": true, "up_right": false}},
	{"pos": Vector2i(11, 6), "up": true, "down": false, "left": true, "right": true,
		"diag": {"up_left": false, "up_right": true}},
	{"pos": Vector2i(9, 4), "up": true, "down": true, "left": false, "right": true,
		"diag": {"up_right": false, "down_right": false}},
	{"pos": Vector2i(8, 5), "up": true, "down": true, "left": false, "right": true,
		"diag": {"up_right": true, "down_right": false}},
	{"pos": Vector2i(8, 6), "up": true, "down": true, "left": false, "right": true,
		"diag": {"up_right": false, "down_right": true}},
	{"pos": Vector2i(9, 5), "up": true, "down": true, "left": true, "right": false,
		"diag": {"up_left": true, "down_left": false}},
	{"pos": Vector2i(11, 4), "up": true, "down": true, "left": true, "right": false,
		"diag": {"up_left": false, "down_left": false}},
	{"pos": Vector2i(9, 6), "up": true, "down": true, "left": true, "right": false,
		"diag": {"up_left": false, "down_left": true}},
]

# Parede + Fluido (água/lava/buraco) JUNTOS nunca passam de 1/8 do total de
# tiles jogáveis — antes cada um tinha um limite INDEPENDENTE (só fluido, só
# parede), mas isso deixava o mapa sufocado quando os DOIS cresciam perto do
# próprio teto ao mesmo tempo (zona de deploy pequena demais, pathing da IA
# sem saída).
#
# BUG antigo (corrigido aqui): generate_fluid() usava esse MESMO valor como
# teto pra si só (fluido gera primeiro), então sempre que o fluido crescia até
# o próprio teto — o que acontecia com frequência, já que o meio do mapa não
# tem limite de quadrante — ele consumia o orçamento COMBINADO inteiro
# sozinho, e generate_interior_walls() (que só usa o que sobra, ver
# max_walls = max_combined - fluid_cells.size()) ficava sempre com 0 pra
# desenhar. Corrigido limitando o próprio fluido a METADE do orçamento
# combinado (ver max_fluid em generate_fluid) — isso garante que sempre sobra
# pelo menos a outra metade pra parede, não importa quanto fluido nasceu.
const WALL_OR_FLUID_MAX_FRACTION = 8

# Onde as unidades do jogador esperam antes de serem posicionadas.
# Fica numa coluna única fora do mapa, à ESQUERDA (x negativo) — espaço que
# fica livre durante a fase de deploy, já que o HUD de batalha (ActionSlots,
# Pass/Undo/Flee, UnitSummary) só aparece quando start_turn_order() roda no
# início da Phase.BATTLE (ver linhas ~337-341 e ~863-867). x=-3 cai dentro
# dessa faixa livre em tela, perto o suficiente da borda do mapa pra não
# parecer "perdida" no vazio (calculado a partir da Camera2D em (240,192) e
# viewport base 1152x648 — a mesma conta de screen = world - camera +
# viewport/2 usada no resto do arquivo). Espaçamento de 2 tiles (48px) entre
# cada unidade na vertical evita sobrepor sprites.
#
# check_deploy_complete() usa grid_pos.x < 0 (não mais grid_pos.y >=
# MAP_HEIGHT) pra saber quem ainda não foi posicionado — precisa ser algo que
# NENHUMA posição real dentro do grid jogável possa produzir. Antigamente a
# staging ficava abaixo do mapa (y = MAP_HEIGHT + 1) e um fallback antigo
# Vector2i(-2, i*2) já causou esse exato bug uma vez (índice alto empurrava
# y pra dentro do range válido e a unidade era contada como "já deployada"
# sem o jogador ter feito nada) — x negativo é seguro porque a zona de
# deploy real (get_deploy_zone_empty_tiles) nunca usa x < 0.
func get_staging_position(index: int) -> Vector2i:
	return Vector2i(-3, index * 2)

enum Phase { DEPLOY, BATTLE, ENDED }

@onready var tilemap: TileMapLayer = $TileMapLayer
@onready var highlight_layer: TileMapLayer = $HighlightLayer
@onready var attack_highlight_layer: TileMapLayer = $AttackHighlightLayer
@onready var fog_layer: TileMapLayer = $FogLayer

# Todo BattleTileset disponível pra sortear (ver comentário grande na classe
# BattleTileset) — preload em vez de @export porque não tem nenhum node de
# cena pra arrastar isso: é sorteado sozinho em _ready(), sem intervenção do
# Inspector. "Apenas para teste" (pedido explícito do usuário) — mais pra
# frente isso provavelmente passa a depender do bioma da EncounterArea (ver
# GameState.current_area) em vez de sortear entre TODOS sem critério nenhum.
const BATTLE_TILESETS: Array[BattleTileset] = [
	preload("res://data/battle_tilesets/tiny_woods.tres"),
	preload("res://data/battle_tilesets/mt_blaze.tres"),
]

# Sorteado em _ready() (ver _pick_battle_tileset()) — guardado aqui pra
# can_cross_fluid()/_on_unit_tile_entered() lerem fluid_pass_type/
# fluid_status_on_enter na hora de decidir quem atravessa e quem se queima.
var current_battle_tileset: BattleTileset

@onready var unit_summary: HBoxContainer = $HUD/UnitSummary
# Só existe/fica visível durante Phase.DEPLOY — ao contrário de
# end_turn_button/undo_button/flee_button (escondidos até start_turn_order()),
# start_button faz o caminho OPOSTO: começa visível e desabilitado (ver
# refresh_start_button()) e some assim que a batalha começa (start_battle()).
# Permite ao jogador postar SÓ PARTE do roster em campo — quem ficar na
# coluna de staging (grid_pos.x < 0, ver get_staging_position) é removido de
# player_units antes da batalha começar, então nunca luta e nunca ganha EXP
# (award_experience() só itera player_units).
@onready var start_button: Button = $HUD/StartButton
@onready var end_turn_button: Button = $HUD/EndTurnButton
@onready var undo_button: Button = $HUD/UndoButton
@onready var flee_button: Button = $HUD/FleeButton
@onready var action_slots: HBoxContainer = $HUD/ActionSlots
# Sétimo "slot" de ação, fora da grade normal de 6 (ver ACTION_SLOT_COUNT) —
# só aparece quando NENHUM dos 6 slots reais tem uma ação clicável agora
# (loadout vazio, todo Ataque sem uso restante, ou só Habilidade/Item passivo
# — ver has_usable_slot_action()). Pedido do usuário: "a Seventh attack
# option that is always the same attack for every unit and just appears IF
# and ONLY IF the unit has no available actions".
@onready var struggle_button: Button = $HUD/StruggleButton
@onready var battle_log_panel: PanelContainer = $HUD/BattleLog
@onready var battle_log: RichTextLabel = $HUD/BattleLog/BattleLogText
# Referência direta à CanvasLayer HUD inteira (não só um filho dela, como
# todo outro @onready deste bloco) — usado por play_weather_anim() pra
# instanciar a animação de entrada de clima como filho DELA (não de Battle),
# ver comentário grande lá sobre por que isso importa (posição em pixel de
# tela, não de mundo).
@onready var hud: CanvasLayer = $HUD

# À DIREITA do mapa (ver comentário grande de get_staging_position sobre a
# conta screen = world - camera + viewport/2 — o mapa cai exatamente em
# x:[336,816]/y:[132,468] na tela, é dessa conta que TODOS os offsets do
# .tscn relacionados ao campo de batalha vêm) — mostra o nome do clima ativo
# + quantas rodadas faltam, se houver (ver refresh_weather_label). Pedido do
# usuário: "Move the weather name from above the battlefield to the right
# with a turn counter (if there is one)". Escondido (visible = false, ver
# .tscn) sem clima nenhum ativo.
@onready var weather_label: Label = $HUD/WeatherLabel

# ColorRect do MESMO tamanho exato do mapa em tela (x:[336,816]/y:[132,468],
# ver comentário de weather_label acima) — pinta o campo de batalha inteiro
# (mapa E unidades por cima, já que HUD é uma CanvasLayer, sempre desenhada
# por cima do World2D) com a cor do clima ativo, um pouco transparente
# (ver WEATHER_MASK_COLORS/refresh_weather_mask). Pedido do usuário: "Mask
# the whole battlefield with the according colors, slightly" — e, pros
# climas de Sol especificamente, só depois da animação de entrada terminar
# (ver play_weather_anim/try_set_weather: "play this animation... and THEN
# apply the mask"). mouse_filter = 2 (MOUSE_FILTER_IGNORE, ver .tscn) é
# OBRIGATÓRIO aqui — sem isso este Control cobriria o mapa inteiro e
# engoliria todo clique do jogador nele ANTES de chegar em
# _unhandled_input (que é quem move/mira unidade), já que Control por
# padrão BLOQUEIA mouse (MOUSE_FILTER_STOP), mesmo sem nenhum sinal
# conectado.
@onready var weather_mask: ColorRect = $HUD/WeatherMask

# Só os 4 climas com cor pedida pelo usuário — Strong Winds fica de fora de
# propósito (nenhuma cor foi pedida pra ele), refresh_weather_mask() esconde
# a máscara nesse caso (e sem clima nenhum). Harsh Sunlight/Heavy Rain
# reusam a cor do clima normal correspondente (Sunny/Rain) — o usuário só
# listou as 4 formas normais, e visualmente são "a mesma coisa, só mais
# forte", não uma cor à parte.
const WEATHER_MASK_COLORS := {
	WEATHER_SUNNY: Color(1.0, 0.9, 0.1, 0.18),
	WEATHER_HARSH_SUNLIGHT: Color(1.0, 0.9, 0.1, 0.18),
	WEATHER_RAIN: Color(0.2, 0.4, 1.0, 0.18),
	WEATHER_HEAVY_RAIN: Color(0.2, 0.4, 1.0, 0.18),
	WEATHER_SANDSTORM: Color(0.55, 0.35, 0.15, 0.22),
	WEATHER_SNOW: Color(1.0, 1.0, 1.0, 0.22),
}

const WEATHER_ANIM_SCENE: PackedScene = preload("res://scenes/effects/weather_anim.tscn")

# Quadros da animação de ENTRADA de cada clima de Sol — sprites em
# assets/sprites/weather/sun (13 arquivos, 000.png a 024.png de 2 em 2,
# mesmo formato "vários arquivos separados" de STATUS_EMOTE_FRAME_ARRAYS/
# BURNED_EMOTE_FRAMES em unit.gd). Harsh Sunlight reusa os MESMOS quadros de
# Sunny — o usuário pediu só "an animation for the sun weathers", sem
# distinguir a forma extrema (visualmente são o mesmo sol, só mais forte).
const SUN_WEATHER_ANIM_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/weather/sun/000.png"),
	preload("res://assets/sprites/weather/sun/002.png"),
	preload("res://assets/sprites/weather/sun/004.png"),
	preload("res://assets/sprites/weather/sun/006.png"),
	preload("res://assets/sprites/weather/sun/008.png"),
	preload("res://assets/sprites/weather/sun/010.png"),
	preload("res://assets/sprites/weather/sun/012.png"),
	preload("res://assets/sprites/weather/sun/014.png"),
	preload("res://assets/sprites/weather/sun/016.png"),
	preload("res://assets/sprites/weather/sun/018.png"),
	preload("res://assets/sprites/weather/sun/020.png"),
	preload("res://assets/sprites/weather/sun/022.png"),
	preload("res://assets/sprites/weather/sun/024.png"),
]

# Clima -> quadros da animação de entrada dele (formato "vários arquivos
# separados", ver WeatherAnim.play()). Ausente daqui (Sandstorm/Snow/Strong
# Winds hoje) = sem animação DESSE FORMATO pra esse clima — pode ainda
# assim ter uma no formato "tira única" (ver WEATHER_STRIP_ANIM_TEXTURES
# logo abaixo); sem entrada em NENHUM dos dois dicionários, play_weather_anim()
# retorna na hora, sem segurar nada, e o mask aparece junto com o nome,
# exatamente como antes desta feature existir.
const WEATHER_ANIM_FRAMES := {
	WEATHER_SUNNY: SUN_WEATHER_ANIM_FRAMES,
	WEATHER_HARSH_SUNLIGHT: SUN_WEATHER_ANIM_FRAMES,
}

# Chuva: tira única 80x16 (5 quadros de 16x16, ver WeatherAnim.play_strip())
# — formato DIFERENTE do Sol de propósito (o usuário mandou a arte já nesse
# formato). Heavy Rain reusa a MESMA tira (mesmo espírito de Harsh Sunlight
# reusando os quadros de Sunny logo acima — "a mesma chuva, só mais forte").
const RAIN_ANIM_TEXTURE: Texture2D = preload("res://assets/sprites/weather/rain/Rain.None.png")
const WEATHER_STRIP_ANIM_TEXTURES := {
	WEATHER_RAIN: RAIN_ANIM_TEXTURE,
	WEATHER_HEAVY_RAIN: RAIN_ANIM_TEXTURE,
}

# Pedido do usuário: "1 animation in a random location for each 2x2 tile"
# — divide o grid jogável (MAP_WIDTH x MAP_HEIGHT tiles, TILE_SIZE px cada)
# em blocos de até RAIN_ANIM_TILE_BLOCK x RAIN_ANIM_TILE_BLOCK tiles e
# sorteia uma posição DENTRO de cada bloco (ver _get_rain_anim_anchors
# abaixo) — bem mais denso que a versão anterior (blocos de 4x4). Blocos na
# borda direita/de baixo ficam MENORES que 2x2 quando MAP_WIDTH/MAP_HEIGHT
# não são múltiplos exatos (20x14 com blocos de 2 dá exatamente 10 colunas x
# 7 linhas = 70 instâncias por rodada, sem sobra nenhuma dessa vez), mas
# ainda ganham uma âncora própria, só que sorteada dentro do bloco menor.
const RAIN_ANIM_TILE_BLOCK = 2

# Uma posição ALEATÓRIA (não mais fixa no centro) dentro de CADA bloco de
# RAIN_ANIM_TILE_BLOCK x RAIN_ANIM_TILE_BLOCK tiles do grid jogável, em
# pixel de TELA (336.0/132.0 = canto superior esquerdo do MAPA em tela,
# mesma conta de sempre — ver get_staging_position). Chamada de novo a cada
# RODADA (ver play_weather_anim) — como é tudo sorteado na hora, cada
# chamada já devolve posições DIFERENTES sozinha, sem precisar de nenhum
# parâmetro extra: é assim que "choose new locations when replaying the
# animation" funciona.
func _get_rain_anim_anchors() -> Array[Vector2]:
	var anchors: Array[Vector2] = []
	var x0 = 0
	while x0 < MAP_WIDTH:
		var block_w = mini(RAIN_ANIM_TILE_BLOCK, MAP_WIDTH - x0)
		var y0 = 0
		while y0 < MAP_HEIGHT:
			var block_h = mini(RAIN_ANIM_TILE_BLOCK, MAP_HEIGHT - y0)
			anchors.append(Vector2(
				336.0 + (x0 + randf_range(0.0, block_w)) * TILE_SIZE,
				132.0 + (y0 + randf_range(0.0, block_h)) * TILE_SIZE,
			))
			y0 += RAIN_ANIM_TILE_BLOCK
		x0 += RAIN_ANIM_TILE_BLOCK
	return anchors

# Pedido do usuário: "start each instance of the animation with a delay of
# 0 to 0.2 seconds" — substituiu a abordagem anterior (começar cada cópia
# num QUADRO diferente, ver WeatherAnim.play_strip). Cada instância (uma
# por âncora de _get_rain_anim_anchors) sorteia seu PRÓPRIO delay dentro
# deste intervalo.
const RAIN_ANIM_MAX_START_DELAY = 0.2

# Pedido do usuário: "3 times total" — em vez de cada instância dar várias
# voltas PARADA no mesmo lugar, RAIN_ANIM_ROUNDS rodadas INTEIRAS rodam em
# sequência, cada uma chamando _get_rain_anim_anchors() de novo (posições
# NOVAS a cada rodada, ver comentário lá) e esperando a rodada terminar
# antes de sortear a próxima — "choose new locations when replaying the
# animation (3 times total)".
const RAIN_ANIM_ROUNDS = 3

# Toca a animação de entrada de `weather` (se houver uma, ver
# WEATHER_ANIM_FRAMES/WEATHER_STRIP_ANIM_TEXTURES) e só RETORNA quando ela
# termina (mesmo padrão de fire_projectile esperando Projectile.arrived).
# Instanciada como filho de `hud` (a CanvasLayer, não Battle) de propósito
# — ver comentário grande no @onready var hud. Chamada por try_set_weather()
# ANTES de refresh_weather_mask() — pedido do usuário: "play this
# animation... and THEN apply the mask".
func play_weather_anim(weather: String) -> void:
	if WEATHER_ANIM_FRAMES.has(weather):
		# Sol: UMA cópia só, sempre no mesmo canto — ver comentário grande
		# de weather_label sobre x:[336,816]/y:[132,468] em tela.
		var anim = WEATHER_ANIM_SCENE.instantiate()
		hud.add_child(anim)
		anim.position = Vector2(336.0, 132.0)
		anim.play(WEATHER_ANIM_FRAMES[weather])
		await anim.finished
		return
	if WEATHER_STRIP_ANIM_TEXTURES.has(weather):
		var texture: Texture2D = WEATHER_STRIP_ANIM_TEXTURES[weather]
		var frame_size = int(texture.get_height())
		var frame_count = max(1, int(texture.get_width()) / frame_size)
		var round_duration = RAIN_ANIM_MAX_START_DELAY + frame_count * WeatherAnim.FRAME_DURATION
		for round_index in RAIN_ANIM_ROUNDS:
			# Um por bloco de RAIN_ANIM_TILE_BLOCK x RAIN_ANIM_TILE_BLOCK
			# tiles (ver _get_rain_anim_anchors) — chamado de novo A CADA
			# rodada, então as posições mudam de rodada pra rodada.
			for anchor in _get_rain_anim_anchors():
				var anim = WEATHER_ANIM_SCENE.instantiate()
				hud.add_child(anim)
				# clamp garante que o quadro INTEIRO continua dentro do
				# campo de batalha, mesmo pras âncoras sorteadas rente à
				# borda de um bloco de canto/borda.
				anim.position = Vector2(
					clampf(anchor.x - frame_size / 2.0, 336.0, 816.0 - frame_size),
					clampf(anchor.y - frame_size / 2.0, 132.0, 468.0 - frame_size),
				)
				anim.play_strip(texture, randf_range(0.0, RAIN_ANIM_MAX_START_DELAY))
			# Espera essa rodada terminar (pior caso: maior delay possível +
			# o ciclo INTEIRO de quadros) antes de sortear a rodada
			# seguinte — só assim faz sentido chamar _get_rain_anim_anchors()
			# de novo (rodada anterior já sumiu da tela).
			await get_tree().create_timer(round_duration).timeout

# Caixa de log: no estado normal (colapsado) só mostra as últimas
# BATTLE_LOG_COLLAPSED_LINES mensagens, bem rente ao mapa. Um clique nela
# expande pra ver o histórico inteiro, crescendo PRA CIMA (o topo sobe, o
# fundo fica fixo — ver _on_battle_log_gui_input). O fundo (offset_bottom,
# BATTLE_LOG_BOTTOM abaixo é só documentação do valor fixo no .tscn — o
# script nunca escreve nele) nunca muda; só o topo alterna entre as duas
# constantes abaixo. COLLAPSED_TOP fica logo abaixo do fundo do mapa (y=468,
# ver battle_window_dims no histórico do projeto) — só o suficiente pra não
# invadir o mapa. EXPANDED_TOP sobe até quase a fileira de portraits, o que
# faz a caixa cobrir boa parte do mapa temporariamente — aceitável, é uma
# consulta sob demanda, não o estado padrão.
const BATTLE_LOG_COLLAPSED_LINES = 3
const BATTLE_LOG_BOTTOM = 572.0
const BATTLE_LOG_COLLAPSED_TOP = 502.0
const BATTLE_LOG_EXPANDED_TOP = 96.0

var battle_log_history: Array[String] = []
var battle_log_expanded: bool = false

# ActionSlots agora tem os 6 botões divididos em duas colunas (ColumnLeft com
# os slots 0-2, ColumnRight com 3-5 — ver battle.tscn) em vez de um
# HBoxContainer com os 6 direto. ACTION_SLOT_COUNT substitui o antigo
# action_slots.get_child_count() (que agora devolveria 2, as colunas, não os
# botões) como o número de slots lógicos. Ver _get_action_slot_button().
const ACTION_SLOT_COUNT = 6

# O ataque de Struggle (ver struggle_button acima e data/attacks/struggle.tres)
# é o MESMO AttackData pra toda unidade, sem tipo, Físico, 50 de poder, 100%
# de accuracy, encosta (makes_contact=true) e tem self_max_hp_recoil_fraction
# = 0.25 (perde 1/4 do próprio hp_max depois de bater — ver AttackData e
# execute_attack). max_uses = -1 nele (sem contador de PP) é o que permite
# reaproveitar TODO o pipeline normal de Ataque (handle_targeting_input,
# _run_player_attack, execute_attack) sem nenhum "if is struggle" espalhado:
# passando slot_index = STRUGGLE_SLOT_INDEX (nunca um índice real de
# UnitData.slots), o "attack.max_uses > 0" que guarda o desconto de
# slot_uses em execute_attack já dá false sozinho, então esse índice nunca é
# de fato usado pra indexar nada.
const STRUGGLE_ATTACK: AttackData = preload("res://data/attacks/struggle.tres")
const STRUGGLE_SLOT_INDEX = -1

# Habilidade que Worry Seed "planta" no lugar de uma aleatória do alvo (ver
# AttackData.replaces_target_ability, pedido do usuário: "replace with
# Insomnia (Can't sleep)") — mesma instância de Resource compartilhada por
# todo mundo que sofrer isso, igual qualquer outro preload de dado deste
# arquivo (ROCKET_BALL_ITEM/STRUGGLE_ATTACK acima).
const INSOMNIA_ABILITY: AbilityData = preload("res://data/abilities/insomnia.tres")

# UnitSummary (a fileira de portraits em cima do mapa, ver battle.tscn) agora
# É a visualização da fila de turnos inteira — jogador E inimigo juntos, na
# ordem de turn_queue (ver build_unit_summary_hud()). O node no .tscn é bem
# mais largo que o mapa (1104px, de x=24 a x=1128) e usa alignment=CENTER —
# de propósito: 24+1128 tem o mesmo ponto médio (576) que os limites antigos
# do mapa (336 a 816), então a fileira fica sempre SIMÉTRICA ao centro do
# mapa não importa quantos slots tenham, sem precisar calcular offset_left/
# right na mão aqui — o BoxContainer já centraliza os filhos sozinho dentro
# dessa área larga. UNIT_SUMMARY_WIDTH só entra como teto de segurança: com
# até ~18 unidades ao mesmo tempo (bem mais que o realista: 6 do time +
# alguns inimigos) o slot fica no tamanho máximo de sempre; só encolhe se
# passar muito disso, pra nunca vazar pra fora da tela (1152 de largura
# base, ver window/stretch em project.godot).
const UNIT_SUMMARY_WIDTH = 1104.0
const UNIT_SUMMARY_SLOT_SEP = 6.0
const UNIT_SUMMARY_SLOT_MAX_WIDTH = 75.0
const UNIT_SUMMARY_SLOT_MIN_WIDTH = 48.0

# Unit -> PanelContainer/Label do slot dele no resumo de unidades do HUD.
var unit_slots: Dictionary = {}
var unit_hp_labels: Dictionary = {}

# O time do jogador (roster) e MAX_TEAM_SIZE agora moram em GameState (ver
# game_state.gd) — precisavam ficar acessíveis fora da batalha também, pra
# tela de Party (aberta do menu de pausa no overworld) poder mostrar e
# reordenar o mesmo time que vai lutar. battle.gd só LÊ GameState.roster /
# GameState.get_active_roster() a partir de agora, não guarda mais cópia
# própria.

var phase: Phase = Phase.DEPLOY

var player_units: Array = []
var enemy_units: Array = []
var units: Array = []   # player_units + enemy_units, usado por get_unit_at()

var highlighted_tiles: Array[Vector2i] = []
var selected_unit: Node = null

# Célula alcançável -> distância REAL do caminho até ela (em passos, contando
# o desvio em volta de fluido/parede). Preenchido por get_reachable_tiles() e
# usado por move_selected_unit() pra descontar o custo certo do turno — sem
# isso, um movimento em linha reta através de um lago (ou lago de lava)
# intransponível "gastava" só a distância direta, como se a unidade tivesse
# atravessado o fluido.
var move_distances: Dictionary = {}

# Ação sendo mirada no momento (null = não está mirando nada, modo normal de
# seleção/movimento). Setado por _on_slot_pressed(), lido por
# update_attack_highlight() (segue o mouse) e handle_targeting_input()
# (confirma ou cancela o alvo ao clicar).
var targeting_action: ActionData = null
var targeting_slot_index: int = -1

# ---------- Sistema de turnos ----------
# Fila de quem joga essa batalha, ordenada por speed (maior primeiro).
# Só as unidades do jogador entram na fila por enquanto — inimigos ainda
# não têm IA, então não "jogam" ainda.
var turn_queue: Array = []
var current_turn_index: int = 0

# Quanto de movimento a unidade da vez ainda tem sobrando nesse turno.
# Cada movimento gasta a distância (Chebyshev — diagonal conta como 1 passo,
# igual nas 8 direções) percorrida; o turno pode ser quebrado em vários
# movimentos até isso chegar a 0.
var move_budget_left: int = 0

# Onde a unidade da vez estava quando o turno começou — usado pelo Undo.
# "Debug" por enquanto: sem armadilhas/terreno especial, desfazer sempre
# volta pra cá inteiro, não move-a-move.
var turn_start_pos: Vector2i = Vector2i.ZERO

# true enquanto um ataque/item do JOGADOR está rodando (entre o clique em
# handle_targeting_input e o fim da animação) — execute_attack/
# execute_status_attack/execute_ball_throw são disparados SEM await ali (fire
# and forget, pra não travar o input enquanto a animação toca), então sem
# essa flag o jogador podia apertar Flee no meio da própria animação de
# ataque e crashar do mesmo jeito que apertar Flee no meio do turno do
# inimigo já crashava (ver o guard de is_enemy em begin_current_turn/
# _on_flee_pressed) — a cena de batalha era trocada enquanto a corrotina do
# ataque ainda estava suspensa num await, e ela quebrava ao retomar contra
# nós já destruídos. Setada/desligada pelos wrappers _run_player_*() logo
# abaixo de execute_ball_throw; ver uso em _on_flee_pressed().
var action_in_progress: bool = false

# Células (dentro do grid jogável) que viraram fluido nessa batalha — água,
# lava ou (futuramente) buraco, dependendo de qual BattleTileset foi
# sorteado (ver current_battle_tileset/BATTLE_TILESETS). A REGRA de quem
# atravessa muda por tileset (ver can_cross_fluid), mas o CONJUNTO de
# células em si é um só, não importa o fluido — por isso um único
# Dictionary serve pros três casos.
var fluid_cells: Dictionary = {}

# Células (dentro do grid jogável) que viraram parede interna nessa batalha.
# Diferente do fluido, parede bloqueia TODO MUNDO (não tem unidade "voadora"
# que atravesse parede) — por isso é excluída sem condição em deploy/movimento,
# ao contrário de fluid_cells que depende de can_unit_cross_fluid().
var wall_cells: Dictionary = {}

# ---------- Clima (Weather) ----------
# Só existe UM efeito de clima ativo por vez (pedido do usuário: "There can
# only be 1 weather effect active, so if another one activates, it overrides
# the active one") — current_weather guarda o NOME dele ("" = nenhum, ver
# WEATHER_NONE). As 4 formas "normais" duram WEATHER_BASE_DURATION rodadas
# (WEATHER_EXTENDED_DURATION se quem ativou carregar o item certo — ver
# ItemData.extends_weather/try_set_weather), contadas em RODADAS INTEIRAS
# (decremento em _on_end_turn_pressed, no mesmo ponto onde a fila de turnos
# reinicia do topo — ver comentário lá), não por turno individual de cada
# unidade, senão um time de 6 gastaria o clima todo numa única rodada. As 3
# formas "extremas" nascem permanentes (weather_turns_left = -1, nunca
# descontam sozinhas) e só terminam trocadas por outra — ver
# can_override_weather() logo abaixo.
const WEATHER_NONE = ""
const WEATHER_SUNNY = "Sunny"
const WEATHER_RAIN = "Rain"
const WEATHER_SANDSTORM = "Sandstorm"
const WEATHER_SNOW = "Snow"
const WEATHER_HARSH_SUNLIGHT = "Harsh Sunlight"
const WEATHER_HEAVY_RAIN = "Heavy Rain"
const WEATHER_STRONG_WINDS = "Strong Winds"

# As 3 formas extremas têm regra de override PRÓPRIA (fixa, ver
# can_override_weather) — cada uma só aceita ser substituída pelas OUTRAS
# DUAS desta lista, Strong Winds nem isso. Fora dessas 3, qualquer clima
# "normal" (Sunny/Rain/Sandstorm/Snow) só pode ser substituído por outro
# clima se weather_overridable (setado por quem ativou o clima ATUAL)
# permitir — pedido do usuário: "Some battles may activate permanent weather
# effects at the start, but it can be overridden (or not, we need a flag for
# it)".
const EXTREME_WEATHERS = [WEATHER_HARSH_SUNLIGHT, WEATHER_HEAVY_RAIN, WEATHER_STRONG_WINDS]

# "Está ensolarado" (normal OU extremo) — extraído porque essa MESMA checagem
# (`current_weather == WEATHER_SUNNY or current_weather == WEATHER_HARSH_
# SUNLIGHT`) já se repetia solta em vários lugares (Fire x1.5 em
# calculate_damage_modifiers, Frozen imune a Sol em _try_apply_secondary_
# status) antes de Chlorophyll (attacks_remaining bônus, ver has_chlorophyll/
# begin_current_turn) e Growth (+2/+2 em vez de +1/+1 em Sol, ver
# AttackData.stat_change_doubles_in_sun) precisarem da mesma pergunta de
# novo. Só um helper de leitura, não mexe em nada.
func is_sun_weather() -> bool:
	return current_weather == WEATHER_SUNNY or current_weather == WEATHER_HARSH_SUNLIGHT

# Fração de hp_max a curar de VERDADE (ver AttackData.self_heal_fraction/
# _in_sun/_in_bad_weather — Synthesis é o primeiro caso) — pedido do usuário:
# "Strong winds or no weather, 1/2 hp. Sun 2/3 hp. Any other weather, 1/4
# hp". Sol tem prioridade (se algum dia um golpe tivesse os dois >= 0.0 ao
# mesmo tempo, o que não acontece hoje); "sem clima" e Strong Winds usam a
# fração PADRÃO (self_heal_fraction), não a de "clima ruim" — só
# Rain/Heavy Rain/Sandstorm/Snow contam como "clima ruim" pra este cálculo.
func get_effective_self_heal_fraction(attack: AttackData) -> float:
	if is_sun_weather() and attack.self_heal_fraction_in_sun >= 0.0:
		return attack.self_heal_fraction_in_sun
	var is_baseline_weather = current_weather == WEATHER_NONE or current_weather == WEATHER_STRONG_WINDS
	if not is_baseline_weather and attack.self_heal_fraction_in_bad_weather >= 0.0:
		return attack.self_heal_fraction_in_bad_weather
	return attack.self_heal_fraction

const WEATHER_BASE_DURATION = 4
const WEATHER_EXTENDED_DURATION = 7

var current_weather: String = WEATHER_NONE
# -1 = permanente (nunca desconta sozinho, só troca via can_override_weather).
# >0 = quantas RODADAS inteiras ainda faltam antes do clima acabar sozinho.
var weather_turns_left: int = 0
# Só é consultado quando current_weather NÃO é uma das 3 formas extremas
# (essas ignoram isso por completo, regra fixa) — controla se o clima
# "normal" ativo agora pode ser substituído por outro clima normal depois.
# true (padrão) = pode; uma batalha com clima permanente "travado" no início
# (ver EncounterArea.starting_weather_overridable/Trainer.
# starting_weather_overridable) põe isto false.
var weather_overridable: bool = true

# true se `new_weather` puder se tornar o clima ativo agora (current_weather).
# Vazio ("" — current_weather nenhum) sempre aceita, e re-ativar o MESMO
# clima que já está ativo também sempre aceita (é assim que um golpe que
# "reforça" o próprio clima, ex: usar Sunny Day de novo já em Sunny, teria
# efeito — recomeça a contagem em vez de ser recusado). Fora isso, a regra
# depende de qual clima está ativo AGORA: as 3 formas extremas usam a lista
# fixa EXTREME_WEATHERS (match abaixo); qualquer clima normal usa o flag
# weather_overridable guardado por quem o ativou.
func can_override_weather(new_weather: String) -> bool:
	if current_weather == WEATHER_NONE or current_weather == new_weather:
		return true
	match current_weather:
		WEATHER_STRONG_WINDS:
			return false
		WEATHER_HARSH_SUNLIGHT:
			return new_weather == WEATHER_HEAVY_RAIN or new_weather == WEATHER_STRONG_WINDS
		WEATHER_HEAVY_RAIN:
			return new_weather == WEATHER_HARSH_SUNLIGHT or new_weather == WEATHER_STRONG_WINDS
		_:
			return weather_overridable

# API pública do sistema de clima — ninguém ainda chama isto com um
# `activator` de verdade (nenhum golpe/Habilidade que ATIVE clima foi
# implementado ainda, só o clima "de fábrica" de início de batalha via
# start_battle()/_apply_starting_weather(), que chama permanent=true e
# activator=null), mas a regra do item que estende a duração (ver
# ItemData.extends_weather) já está pronta e correta pra quando esse golpe
# existir — mesmo espírito de Unit.modify_stat_stage ("o cano" pronto antes
# do primeiro efeito secundário que o usa).
#
# activator: unidade que causou a troca (null = evento de batalha, sem
# "dono" — nunca ganha a duração estendida do item, ver abaixo).
# permanent: true força weather_turns_left = -1 (não desconta sozinho,
# usado por clima de início de batalha) — ignorado (sempre permanente de
# qualquer jeito) se new_weather for uma das 3 formas extremas.
# overridable: só faz sentido pra clima normal (ver weather_overridable
# acima); ignorado pras 3 formas extremas, que têm regra fixa própria.
# Devolve false sem mudar nada se can_override_weather() recusar a troca.
func try_set_weather(new_weather: String, activator: Node = null, permanent: bool = false, overridable: bool = true) -> bool:
	if not can_override_weather(new_weather):
		return false
	current_weather = new_weather
	weather_overridable = overridable
	if new_weather == WEATHER_NONE:
		weather_turns_left = 0
	elif permanent or EXTREME_WEATHERS.has(new_weather):
		weather_turns_left = -1
	else:
		weather_turns_left = WEATHER_EXTENDED_DURATION if _activator_extends_weather(new_weather, activator) else WEATHER_BASE_DURATION
	if new_weather != WEATHER_NONE:
		log_message(WEATHER_START_MESSAGES.get(new_weather, "The weather changed to %s!" % new_weather))
	# Nome/contador aparecem NA HORA — só o mask (o "tingir a tela") espera a
	# animação de entrada, quando o clima tiver uma (ver play_weather_anim/
	# WEATHER_ANIM_FRAMES) — pedido do usuário: "play this animation on top
	# left of the battlefield and THEN apply the mask". Sem animação
	# registrada pro clima, play_weather_anim() retorna na mesma linha (sem
	# ceder o frame), então refresh_weather_mask() roda praticamente junto
	# com refresh_weather_label(), igual sempre foi antes desta feature.
	refresh_weather_label()
	await play_weather_anim(new_weather)
	refresh_weather_mask()
	return true

const WEATHER_START_MESSAGES := {
	WEATHER_SUNNY: "The sunlight got harsh!",
	WEATHER_RAIN: "It started to rain!",
	WEATHER_SANDSTORM: "A sandstorm kicked up!",
	WEATHER_SNOW: "It started to snow!",
	WEATHER_HARSH_SUNLIGHT: "The sunlight turned extremely harsh!",
	WEATHER_HEAVY_RAIN: "A heavy rain began to fall!",
	WEATHER_STRONG_WINDS: "Mysterious strong winds are protecting Flying-type Pokémon!",
}

# ItemData.extends_weather (ver comentário lá) precisa bater com o NOME
# exato do clima sendo ativado — um Heat Rock (extends_weather = "Sunny")
# não estende Rain, por exemplo. activator == null (evento de batalha, sem
# unidade "dona") nunca estende nada: só faz sentido perguntar "quem
# carrega o item" quando existe alguém que de fato ativou o clima.
func _activator_extends_weather(new_weather: String, activator: Node) -> bool:
	if activator == null or activator.data == null:
		return false
	for action in activator.data.slots:
		if action is ItemData and action.extends_weather == new_weather:
			return true
	return false

func _ready() -> void:
	if GameState.roster.size() > GameState.MAX_TEAM_SIZE:
		push_warning("roster tem %d entradas, mais que o time máximo (%d) — as excedentes serão ignoradas." % [GameState.roster.size(), GameState.MAX_TEAM_SIZE])
	randomize()
	_pick_battle_tileset()   # ANTES de qualquer paint_*/set_cell — as 4 layers precisam do tile_set certo já atribuído
	build_ground_variants()
	build_wall_detail()
	# O terreno inteiro já é gerado de uma vez — "revelar" depois não gera
	# nada novo, só tira a névoa de cima do que já existe.
	paint_area(0, MAP_WIDTH)
	generate_fluid()
	generate_interior_walls()   # depende de fluid_cells já preenchido (não sobrepõe fluido)
	paint_wall_border()         # depende de wall_cells já populado (se conecta com paredes internas)
	paint_fog(DEPLOY_ZONE_WIDTH, MAP_WIDTH)
	spawn_player_units_staged()
	battle_log.gui_input.connect(_on_battle_log_gui_input)
	log_message("Battle tileset: %s" % current_battle_tileset.display_name)   # só pra teste, ver comentário de BATTLE_TILESETS
	log_message("Deploy your units!")

	start_button.pressed.connect(_on_start_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	undo_button.pressed.connect(_on_undo_pressed)
	flee_button.pressed.connect(_on_flee_pressed)
	struggle_button.pressed.connect(_on_struggle_pressed)
	for i in ACTION_SLOT_COUNT:
		var button: Button = _get_action_slot_button(i)
		button.pressed.connect(_on_slot_pressed.bind(i))
	unit_summary.visible = false
	end_turn_button.visible = false
	undo_button.visible = false
	flee_button.visible = false
	action_slots.visible = false
	struggle_button.visible = false
	refresh_start_button()

# Sorteia um BATTLE_TILESETS e aplica o .tile_set dele nas 4 TileMapLayer da
# cena (TileMapLayer de verdade + HighlightLayer/AttackHighlightLayer/
# FogLayer, que só usam a coordenada (13,1) como "preenchimento" tintado por
# modulate — ver highlight_tiles()/update_attack_highlight()/paint_fog(), mas
# mesmo assim precisam de UM TileSet válido registrado com essa coordenada,
# por isso recebem o mesmo tile_set que o chão de verdade). Roda ANTES de
# qualquer paint_*/set_cell em _ready() de propósito.
func _pick_battle_tileset() -> void:
	current_battle_tileset = BATTLE_TILESETS[randi() % BATTLE_TILESETS.size()]
	tilemap.tile_set = current_battle_tileset.tile_set
	highlight_layer.tile_set = current_battle_tileset.tile_set
	attack_highlight_layer.tile_set = current_battle_tileset.tile_set
	fog_layer.tile_set = current_battle_tileset.tile_set

# Anexa uma linha ao HISTÓRICO da caixa de eventos da batalha (ver
# HUD/BattleLog em battle.tscn) e redesenha o texto visível. É o único ponto
# de escrita nessa caixa — cada evento novo (ataque usado, efetividade,
# status aplicado, derrota/exp, etc.) chama isso em vez de mexer direto no
# RichTextLabel. Vamos adicionando mais chamadas aos poucos conforme novos
# tipos de evento aparecem no jogo.
func log_message(text: String) -> void:
	battle_log_history.append(text)
	_refresh_battle_log_display()

# Redesenha o RichTextLabel a partir do histórico: só as últimas
# BATTLE_LOG_COLLAPSED_LINES quando colapsado, ou tudo quando expandido (ver
# _on_battle_log_gui_input). scroll_following=true (battle.tscn) já rola pro
# final sozinho sempre que o texto muda.
func _refresh_battle_log_display() -> void:
	var lines = battle_log_history
	if not battle_log_expanded:
		var from = max(0, battle_log_history.size() - BATTLE_LOG_COLLAPSED_LINES)
		lines = battle_log_history.slice(from)
	battle_log.text = "\n".join(lines)

# Clique em qualquer lugar da caixa alterna colapsado/expandido. Só o topo
# (offset_top) do painel se move — o fundo é fixo (ver comentário de
# BATTLE_LOG_BOTTOM acima), então a caixa sempre cresce PRA CIMA, nunca por
# cima do que já tem embaixo dela.
func _on_battle_log_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		battle_log_expanded = not battle_log_expanded
		battle_log_panel.offset_top = BATTLE_LOG_EXPANDED_TOP if battle_log_expanded else BATTLE_LOG_COLLAPSED_TOP
		_refresh_battle_log_display()

# Pinta as colunas [from_x, to_x) inteiras (todas as linhas) com um tile
# sorteado de GROUND_VARIANTS pra cada célula.
func paint_area(from_x: int, to_x: int) -> void:
	for x in range(from_x, to_x):
		for y in MAP_HEIGHT:
			tilemap.set_cell(Vector2i(x, y), 0, ground_variants.pick_random())

# Cresce uma (ou mais) mancha de fluido (água/lava/buraco, ver
# current_battle_tileset) a partir de sementes aleatórias, sempre andando pra
# uma célula vizinha de fluido já existente — isso forma manchas agrupadas em
# vez de espalhado pelo mapa inteiro. Para quando bate no limite do
# ORÇAMENTO COMBINADO com parede (ver WALL_OR_FLUID_MAX_FRACTION — fluido
# gera PRIMEIRO, então é ele quem usa o orçamento cheio; generate_interior_
# walls() usa só o que sobrar) ou não sobra mais vizinho livre.
func generate_fluid() -> void:
	fluid_cells.clear()

	@warning_ignore("integer_division")
	var max_combined = (MAP_WIDTH * MAP_HEIGHT) / WALL_OR_FLUID_MAX_FRACTION
	# Fluido usa só METADE do orçamento combinado (não o combinado inteiro) —
	# garante que sempre sobra espaço de verdade pra generate_interior_walls()
	# desenhar parede depois (ver comentário grande de WALL_OR_FLUID_MAX_
	# FRACTION acima sobre o bug que isso corrige).
	@warning_ignore("integer_division")
	var max_fluid = max_combined / 2

	# Nem o primeiro quadrante (zona de deploy do jogador) nem o último (zona
	# de deploy do "jogador 2", quando tivermos multiplayer) podem ficar mais
	# de 1/4 cobertos de PAREDE+FLUIDO somados — senão a área de
	# posicionamento fica pequena demais. Fluido gera primeiro, então só
	# precisa respeitar essa fração aqui; generate_interior_walls() é
	# quem desconta o que o fluido já gastou de cada quadrante (ver lá).
	@warning_ignore("integer_division")
	var max_fluid_per_deploy_quadrant = (DEPLOY_ZONE_WIDTH * MAP_HEIGHT) / 4
	var first_quadrant_fluid = 0
	var last_quadrant_fluid = 0

	var frontier: Array[Vector2i] = []
	var seed_count = randi_range(1, 3)
	for i in seed_count:
		if fluid_cells.size() >= max_fluid:
			break
		var seed_cell = Vector2i(randi_range(0, MAP_WIDTH - 1), randi_range(0, MAP_HEIGHT - 1))
		if fluid_cells.has(seed_cell):
			continue
		if not can_add_fluid_cell(seed_cell, first_quadrant_fluid, last_quadrant_fluid, max_fluid_per_deploy_quadrant):
			continue
		fluid_cells[seed_cell] = true
		frontier.append(seed_cell)
		if seed_cell.x < DEPLOY_ZONE_WIDTH:
			first_quadrant_fluid += 1
		elif seed_cell.x >= MAP_WIDTH - DEPLOY_ZONE_WIDTH:
			last_quadrant_fluid += 1

	while fluid_cells.size() < max_fluid and not frontier.is_empty():
		var idx = randi_range(0, frontier.size() - 1)
		var cell = frontier[idx]
		var neighbors = [
			cell + Vector2i(1, 0), cell + Vector2i(-1, 0),
			cell + Vector2i(0, 1), cell + Vector2i(0, -1),
		]
		neighbors.shuffle()

		var grew = false
		for n in neighbors:
			if n.x < 0 or n.x >= MAP_WIDTH or n.y < 0 or n.y >= MAP_HEIGHT:
				continue
			if fluid_cells.has(n):
				continue
			if not can_add_fluid_cell(n, first_quadrant_fluid, last_quadrant_fluid, max_fluid_per_deploy_quadrant):
				continue
			fluid_cells[n] = true
			frontier.append(n)
			if n.x < DEPLOY_ZONE_WIDTH:
				first_quadrant_fluid += 1
			elif n.x >= MAP_WIDTH - DEPLOY_ZONE_WIDTH:
				last_quadrant_fluid += 1
			grew = true
			break
		if not grew:
			frontier.remove_at(idx)   # essa célula não tem mais vizinho livre válido — sai da fronteira

		if fluid_cells.size() >= max_fluid:
			break

	paint_fluid()

# Impede que o fluido passe de metade de um quadrante de deploy (primeiro ou
# último). O meio do mapa não tem esse limite.
func can_add_fluid_cell(cell: Vector2i, first_quadrant_fluid: int, last_quadrant_fluid: int, max_per_quadrant: int) -> bool:
	if cell.x < DEPLOY_ZONE_WIDTH and first_quadrant_fluid >= max_per_quadrant:
		return false
	if cell.x >= MAP_WIDTH - DEPLOY_ZONE_WIDTH and last_quadrant_fluid >= max_per_quadrant:
		return false
	return true

func paint_fluid() -> void:
	for cell in fluid_cells.keys():
		var has_up = fluid_cells.has(cell + Vector2i(0, -1))
		var has_down = fluid_cells.has(cell + Vector2i(0, 1))
		var has_left = fluid_cells.has(cell + Vector2i(-1, 0))
		var has_right = fluid_cells.has(cell + Vector2i(1, 0))
		var has_up_left = fluid_cells.has(cell + Vector2i(-1, -1))
		var has_up_right = fluid_cells.has(cell + Vector2i(1, -1))
		var has_down_left = fluid_cells.has(cell + Vector2i(-1, 1))
		var has_down_right = fluid_cells.has(cell + Vector2i(1, 1))

		var detail_tile = pick_detail_tile(
			FLUID_DETAIL,
			has_up, has_down, has_left, has_right,
			has_up_left, has_up_right, has_down_left, has_down_right
		)
		if detail_tile != Vector2i(-1, -1):
			tilemap.set_cell(cell, 0, detail_tile)
			continue

		var role = pick_role(has_up, has_down, has_left, has_right)
		tilemap.set_cell(cell, 0, FLUID_SET_A[role])

# Cresce uma mancha de parede interna a partir de uma célula na BORDA do grid
# jogável (x==0, x==MAP_WIDTH-1, y==0 ou y==MAP_HEIGHT-1) — isso garante que
# a mancha sempre nasce encostada na moldura externa, então nunca fica
# desconexa dela (todo o resto cresce a partir dessa semente, célula a célula
# vizinha). Mesmo algoritmo de frontier/seed do fluido, só que sem invadir
# fluido e usando o que SOBROU do orçamento combinado (ver
# WALL_OR_FLUID_MAX_FRACTION/generate_fluid, que roda antes e gera primeiro)
# — tanto no total quanto em cada quadrante de deploy: se o fluido já ocupou
# metade de um quadrante sozinho, parede não ganha mais espaço NENHUM ali.
func generate_interior_walls() -> void:
	wall_cells.clear()

	@warning_ignore("integer_division")
	var max_combined = (MAP_WIDTH * MAP_HEIGHT) / WALL_OR_FLUID_MAX_FRACTION
	var max_walls = max(0, max_combined - fluid_cells.size())

	@warning_ignore("integer_division")
	var max_per_deploy_quadrant = (DEPLOY_ZONE_WIDTH * MAP_HEIGHT) / 4
	var first_quadrant_fluid = 0
	var last_quadrant_fluid = 0
	for cell in fluid_cells.keys():
		if cell.x < DEPLOY_ZONE_WIDTH:
			first_quadrant_fluid += 1
		elif cell.x >= MAP_WIDTH - DEPLOY_ZONE_WIDTH:
			last_quadrant_fluid += 1
	var first_quadrant_walls = 0
	var last_quadrant_walls = 0

	var edge_cells: Array[Vector2i] = []
	for x in MAP_WIDTH:
		edge_cells.append(Vector2i(x, 0))
		edge_cells.append(Vector2i(x, MAP_HEIGHT - 1))
	for y in MAP_HEIGHT:
		edge_cells.append(Vector2i(0, y))
		edge_cells.append(Vector2i(MAP_WIDTH - 1, y))
	edge_cells.shuffle()

	var frontier: Array[Vector2i] = []
	var seed_count = randi_range(1, 2)
	for cell in edge_cells:
		if frontier.size() >= seed_count or wall_cells.size() >= max_walls:
			break
		if wall_cells.has(cell) or fluid_cells.has(cell):
			continue
		if not can_add_wall_cell(cell, first_quadrant_walls, last_quadrant_walls, max_per_deploy_quadrant, first_quadrant_fluid, last_quadrant_fluid):
			continue
		wall_cells[cell] = true
		frontier.append(cell)
		if cell.x < DEPLOY_ZONE_WIDTH:
			first_quadrant_walls += 1
		elif cell.x >= MAP_WIDTH - DEPLOY_ZONE_WIDTH:
			last_quadrant_walls += 1

	while wall_cells.size() < max_walls and not frontier.is_empty():
		var idx = randi_range(0, frontier.size() - 1)
		var cell = frontier[idx]
		var neighbors = [
			cell + Vector2i(1, 0), cell + Vector2i(-1, 0),
			cell + Vector2i(0, 1), cell + Vector2i(0, -1),
		]
		neighbors.shuffle()

		var grew = false
		for n in neighbors:
			if n.x < 0 or n.x >= MAP_WIDTH or n.y < 0 or n.y >= MAP_HEIGHT:
				continue
			if wall_cells.has(n) or fluid_cells.has(n):
				continue
			if not can_add_wall_cell(n, first_quadrant_walls, last_quadrant_walls, max_per_deploy_quadrant, first_quadrant_fluid, last_quadrant_fluid):
				continue
			wall_cells[n] = true
			frontier.append(n)
			if n.x < DEPLOY_ZONE_WIDTH:
				first_quadrant_walls += 1
			elif n.x >= MAP_WIDTH - DEPLOY_ZONE_WIDTH:
				last_quadrant_walls += 1
			grew = true
			break
		if not grew:
			frontier.remove_at(idx)   # sem vizinho livre válido — sai da fronteira

		if wall_cells.size() >= max_walls:
			break

	paint_interior_walls()

# Mesma ideia de can_add_fluid_cell, mas somando parede+fluido já colocados
# no quadrante (ver comentário grande de generate_interior_walls acima) —
# parede não pode fazer o quadrante passar de max_per_quadrant CONTANDO o que
# o fluido já ocupou ali.
func can_add_wall_cell(
	cell: Vector2i,
	first_quadrant_walls: int, last_quadrant_walls: int, max_per_quadrant: int,
	first_quadrant_fluid: int, last_quadrant_fluid: int
) -> bool:
	if cell.x < DEPLOY_ZONE_WIDTH and first_quadrant_walls + first_quadrant_fluid >= max_per_quadrant:
		return false
	if cell.x >= MAP_WIDTH - DEPLOY_ZONE_WIDTH and last_quadrant_walls + last_quadrant_fluid >= max_per_quadrant:
		return false
	return true

# Trata qualquer célula FORA do grid jogável (0..MAP_WIDTH-1, 0..MAP_HEIGHT-1)
# como parede — é a moldura externa, pintada por paint_wall_border() usando
# essa mesma função. Isso faz a moldura e as paredes internas se conectarem
# visualmente: os dois lados enxergam um ao outro através da mesma checagem,
# então pegam o tile côncavo/reto/T certo em vez de um tile fixo genérico.
func is_wall_or_border(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
		return true
	return wall_cells.has(cell)

func paint_interior_walls() -> void:
	for cell in wall_cells.keys():
		paint_wall_cell(cell)

# Pinta UMA célula de parede (interna ou da moldura externa — não importa,
# as duas usam a mesma função) olhando os 8 vizinhos via is_wall_or_border().
# É isso que faz a moldura e as paredes internas se conectarem: os dois lados
# enxergam um ao outro através da mesma checagem, em vez de a moldura usar
# tiles fixos que não sabem se tem parede interna encostando nela.
func paint_wall_cell(cell: Vector2i) -> void:
	var has_up = is_wall_or_border(cell + Vector2i(0, -1))
	var has_down = is_wall_or_border(cell + Vector2i(0, 1))
	var has_left = is_wall_or_border(cell + Vector2i(-1, 0))
	var has_right = is_wall_or_border(cell + Vector2i(1, 0))
	var has_up_left = is_wall_or_border(cell + Vector2i(-1, -1))
	var has_up_right = is_wall_or_border(cell + Vector2i(1, -1))
	var has_down_left = is_wall_or_border(cell + Vector2i(-1, 1))
	var has_down_right = is_wall_or_border(cell + Vector2i(1, 1))

	var detail_tile = pick_detail_tile(
		wall_detail,
		has_up, has_down, has_left, has_right,
		has_up_left, has_up_right, has_down_left, has_down_right
	)
	if detail_tile != Vector2i(-1, -1):
		tilemap.set_cell(cell, 0, detail_tile)
		return

	var role = pick_role(has_up, has_down, has_left, has_right)
	tilemap.set_cell(cell, 0, WALL_SET_A[role])

# Genérico — usado tanto por fluido quanto por parede (mesmo esquema de
# autotile "de mão", só muda a tabela de peças e as coordenadas reais).
# Procura numa tabela de detalhe (FLUID_DETAIL, wall_detail, etc.) uma peça
# cuja vizinhança bata exatamente (4 lados + só as diagonais que a peça se
# importa). Se mais de uma peça bater (variação visual da mesma vizinhança,
# ex: os pares côncavos de fluido), sorteia entre elas. Se nenhuma bater,
# devolve (-1,-1) e quem chamou cai pro esquema simples de 9 peças (SET_A
# correspondente) — que cobre cantos convexos, borda reta e preenchimento.
func pick_detail_tile(
	detail_table: Array[Dictionary],
	has_up: bool, has_down: bool, has_left: bool, has_right: bool,
	has_up_left: bool, has_up_right: bool, has_down_left: bool, has_down_right: bool
) -> Vector2i:
	var actual_diag = {
		"up_left": has_up_left, "up_right": has_up_right,
		"down_left": has_down_left, "down_right": has_down_right,
	}
	var candidates: Array[Vector2i] = []
	for entry in detail_table:
		if entry["up"] != has_up or entry["down"] != has_down:
			continue
		if entry["left"] != has_left or entry["right"] != has_right:
			continue
		var diag_ok = true
		for corner in entry["diag"].keys():
			if entry["diag"][corner] != actual_diag[corner]:
				diag_ok = false
				break
		if diag_ok:
			candidates.append(entry["pos"])
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates.pick_random()

# Genérico também — olha os 4 vizinhos ortogonais de uma célula pra decidir
# se ela é canto convexo, borda reta ou preenchimento. Devolve o ÍNDICE do
# papel (ROLE_*), não o Vector2i direto — quem chama busca o tile no SET_A
# correspondente (FLUID_SET_A, WALL_SET_A). Só é usado como fallback quando
# pick_detail_tile() não acha peça específica pra vizinhança.
func pick_role(has_up: bool, has_down: bool, has_left: bool, has_right: bool) -> int:
	if has_up and has_down and has_left and has_right:
		return ROLE_FILL
	if has_down and has_right and not has_up and not has_left:
		return ROLE_TOP_LEFT
	if has_down and has_left and not has_up and not has_right:
		return ROLE_TOP_RIGHT
	if has_up and has_right and not has_down and not has_left:
		return ROLE_BOTTOM_LEFT
	if has_up and has_left and not has_down and not has_right:
		return ROLE_BOTTOM_RIGHT
	if has_left and has_right and has_down and not has_up:
		return ROLE_TOP
	if has_left and has_right and has_up and not has_down:
		return ROLE_BOTTOM
	if has_up and has_down and has_right and not has_left:
		return ROLE_LEFT
	if has_up and has_down and has_left and not has_right:
		return ROLE_RIGHT
	# Combinações que esse conjunto de 9 tiles não cobre (cantos côncavos,
	# pontas finas) — usa o preenchimento como fallback, é o que menos destoa.
	return ROLE_FILL

# Cobre as colunas [from_x, to_x) com névoa. A aparência escura vem só do
# modulate do FogLayer (veja battle.tscn) — o tile em si é irrelevante,
# igual já fazíamos com o destaque azul do HighlightLayer.
func paint_fog(from_x: int, to_x: int) -> void:
	for x in range(from_x, to_x):
		for y in MAP_HEIGHT:
			fog_layer.set_cell(Vector2i(x, y), 0, Vector2i(13, 1))

# Desenha a moldura de parede em volta do grid jogável, uma coluna/linha
# por FORA de 0..MAP_WIDTH/HEIGHT — não come nenhum tile andável.
# Precisa rodar DEPOIS de generate_interior_walls() (wall_cells já populado),
# senão a moldura não sabe quais paredes internas estão encostando nela.
# Cada célula é resolvida dinamicamente via paint_wall_cell() — é isso que
# garante a conexão visual com paredes internas (ver comentário lá).
func paint_wall_border() -> void:
	paint_wall_cell(Vector2i(-1, -1))
	paint_wall_cell(Vector2i(MAP_WIDTH, -1))
	paint_wall_cell(Vector2i(-1, MAP_HEIGHT))
	paint_wall_cell(Vector2i(MAP_WIDTH, MAP_HEIGHT))

	for x in MAP_WIDTH:
		paint_wall_cell(Vector2i(x, -1))
		paint_wall_cell(Vector2i(x, MAP_HEIGHT))

	for y in MAP_HEIGHT:
		paint_wall_cell(Vector2i(-1, y))
		paint_wall_cell(Vector2i(MAP_WIDTH, y))

func spawn_player_units_staged() -> void:
	# Filtra desmaiados (current_hp <= 0) ANTES de calcular as posições de
	# staging — assim as posições ficam compactas (sem "buraco" na fila) e a
	# unidade desmaiada simplesmente não aparece pra deploy, nem sua imagem
	# (ver Party screen pra checar o time inteiro, incluindo quem ficou de fora).
	var deployable: Array[UnitData] = []
	for data in GameState.get_active_roster():
		if data.current_hp > 0:
			deployable.append(data)
	for i in deployable.size():
		var data = deployable[i]
		var pos = get_staging_position(i)
		var u = UNIT_SCENE.instantiate()
		add_child(u)          # precisa vir antes de apply_persisted_data(), que usa @onready var anim
		u.apply_persisted_data(data)
		u.init(pos, "right")   # coluna de staging fica à esquerda, olhando pro mapa
		player_units.append(u)
		# Sempre que a Speed de QUALQUER unidade mudar (ver Unit.speed_changed/
		# modify_stat_stage), a fila de turnos pode precisar reordenar quem
		# ainda não jogou nesta rodada — ver reorder_turn_queue_by_speed().
		u.speed_changed.connect(reorder_turn_queue_by_speed)
		# Pisou numa célula nova (ver Unit.tile_entered/move_along_path) — NÃO
		# dispara aqui no spawn de staging (init() só posiciona, não passa por
		# move_along_path), só quando o jogador de fato POSICIONA a unidade
		# (place_selected_unit -> move_to, ver handle_deploy_input) ou ela anda
		# de verdade em batalha — inclusive deployar em cima de lava já queima.
		u.tile_entered.connect(_on_unit_tile_entered.bind(u))
	units = player_units

func get_unit_at(cell: Vector2i) -> Node:
	# is_instance_valid é uma segunda trava, por segurança — o certo é
	# remove_defeated_unit() já ter tirado a unidade morta de `units` antes
	# disso, mas checar aqui evita crash caso algum caminho futuro esqueça.
	for u in units:
		if is_instance_valid(u) and u.grid_pos == cell:
			return u
	return null

# Só atravessa o fluido do mapa atual (água/lava/buraco — ver
# current_battle_tileset) quem é do tipo que aquele tileset libera
# (current_battle_tileset.fluid_pass_type — "Water" na tinyWoods, "Fire" na
# mtBlaze, "" no futuro tileset de buraco, onde nenhum tipo dá esse direito
# sozinho), quem tem a flag grounded desligada (voa/flutua e ignora o
# terreno) na própria UnitData, ou quem tem uma Habilidade equipada que
# concede isso dinamicamente (ex: Levitate, ver AbilityData.
# grants_levitation) — Chimecho é o primeiro caso disso. Nenhuma dessas
# regras garante estar A SALVO do fluido (ver current_battle_tileset.
# fluid_status_on_enter/_on_unit_tile_entered): mtBlaze ainda queima quem
# atravessa a lava sem ser Fire.
func can_cross_fluid(data: UnitData) -> bool:
	if data == null:
		return false
	var pass_type = current_battle_tileset.fluid_pass_type
	if not data.grounded or (pass_type != "" and data.types.has(pass_type)):
		return true
	for action in data.slots:
		if action is AbilityData and action.grants_levitation:
			return true
	return false

func can_unit_cross_fluid(u: Node) -> bool:
	if u == null:
		return false
	return can_cross_fluid(u.data)

# Ligado ao Unit.tile_entered de TODA unidade (ver spawn_player_units_staged/
# spawn_enemies) — se a célula em que ela acabou de pisar é fluido E o
# tileset atual tem um status pra isso (current_battle_tileset.
# fluid_status_on_enter, ex: "Burned" na mtBlaze), tenta aplicar. Sempre
# tenta em QUALQUER unidade que pise ali (não só quem não é do fluid_pass_
# type) de propósito — quem É do tipo que o tileset libera (Fire na mtBlaze)
# já é naturalmente imune via Unit.STATUS_TYPE_IMMUNITIES, então não precisa
# checar tipo nenhum aqui, apply_status_condition() já se recusa sozinha.
func _on_unit_tile_entered(cell: Vector2i, u: Node) -> void:
	if current_battle_tileset.fluid_status_on_enter == "":
		return
	if not fluid_cells.has(cell):
		return
	if u.apply_status_condition(current_battle_tileset.fluid_status_on_enter):
		log_message("%s was %s!" % [u.data.unit_name, current_battle_tileset.fluid_status_on_enter])

# Atalhos de teclado da fase de batalha — pensados desde já como INPUT
# ACTIONS (ver [input] em project.godot), não como keycode cru, porque uma
# Input Action pode ganhar um evento de CONTROLE além do de teclado mais
# pra frente (ver comentário do pedido do usuário: "importante muito
# futuramente quando adicionarmos suporte para controle") sem precisar
# mexer em battle.gd de novo — só adicionar o evento de joypad na mesma
# action lá no project.godot. Loadout 1-6 -> teclas 1-6 (action_slot_1..6),
# Pass -> Space (pass), Flee -> Esc (reaproveita "menu", já existe e não é
# usado em batalha nenhuma outra hora).
const ACTION_SLOT_ACTIONS = [
	"action_slot_1", "action_slot_2", "action_slot_3",
	"action_slot_4", "action_slot_5", "action_slot_6",
]

func _unhandled_input(event: InputEvent) -> void:
	# Só durante Phase.BATTLE — é exatamente quando os botões Pass/Flee/
	# ActionSlots ficam visíveis (ver start_turn_order()), então os atalhos
	# só existem quando o botão equivalente também existiria pra clicar.
	# Turno de inimigo (is_enemy) é tocado sozinho por run_enemy_turn(), sem
	# nenhum atalho do jogador valendo por cima — Pass/Flee/1-6 ficariam
	# escondidos mesmo (ver begin_current_turn), mas a tecla "pass" não passa
	# por button.disabled nenhum, então essa guarda aqui é quem realmente
	# impede o jogador de encerrar o turno da IA no meio de uma animação.
	if phase == Phase.BATTLE and (get_current_unit() == null or get_current_unit().is_enemy):
		return
	if phase == Phase.BATTLE:
		# set_input_as_handled() ANTES de chamar a ação (não depois) de
		# propósito — _on_flee_pressed() troca de cena
		# (get_tree().change_scene_to_file), o que tira este nó da árvore.
		# Chamar get_viewport() DEPOIS disso retorna null e crasha
		# ("Cannot call method 'set_input_as_handled' on a null value").
		# Marcando como tratado primeiro, a troca de cena pode fazer o que
		# quiser depois sem essa call depender do nó ainda estar vivo.
		if event.is_action_pressed("pass"):
			get_viewport().set_input_as_handled()
			_on_end_turn_pressed()
			return
		if event.is_action_pressed("menu"):
			get_viewport().set_input_as_handled()
			_on_flee_pressed()
			return
		for i in ACTION_SLOT_ACTIONS.size():
			if event.is_action_pressed(ACTION_SLOT_ACTIONS[i]):
				get_viewport().set_input_as_handled()
				_trigger_action_slot_shortcut(i)
				return

	# _unhandled_input (em vez de _input) porque agora temos UI de verdade
	# (o botão de passar turno) — assim um clique no botão não é também
	# interpretado como clique no mapa.
	if event is InputEventMouseMotion:
		if targeting_action != null:
			update_attack_highlight()
		return

	if not (event is InputEventMouseButton and event.pressed):
		return

	# Botão direito = "Cancelar" (pedido do usuário, 2026-07-24: "Right mouse
	# button to be a 'Cancel' button, just like Left mouse button is Confirm
	# or Select") — sempre disponível, não depende de estar em cima de
	# nenhuma célula específica. Em modo de mira, cancela a mira (mesmo
	# cancel_targeting() que um clique esquerdo fora do alcance já dispara,
	# ver handle_targeting_input); fora de mira, desseleciona a unidade atual
	# (mesmo deselect() do "else" de handle_deploy_input/handle_battle_input).
	# Os dois são seguros de chamar mesmo sem nada selecionado (viram no-op).
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if targeting_action != null:
			cancel_targeting()
		else:
			deselect()
		return

	# Antes desta correção, QUALQUER botão do mouse (inclusive o direito, e o
	# do meio) caía no fluxo de Confirmar/Selecionar abaixo — só o botão
	# esquerdo deveria fazer isso agora que o direito virou Cancelar.
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var clicked_cell = tilemap.local_to_map(tilemap.to_local(get_global_mouse_position()))
	var clicked_unit = get_unit_at(clicked_cell)

	if targeting_action != null:
		handle_targeting_input(clicked_cell)
		return

	if phase == Phase.DEPLOY:
		handle_deploy_input(clicked_cell, clicked_unit)
	elif phase == Phase.BATTLE:
		handle_battle_input(clicked_cell, clicked_unit)
	# Phase.ENDED: a batalha já acabou (ver check_battle_end) e a troca de
	# cena está a caminho — ignora qualquer clique até lá.

# ---------- Fase de deploy ----------

func handle_deploy_input(clicked_cell: Vector2i, clicked_unit: Node) -> void:
	if clicked_unit and clicked_unit in player_units:
		select_unit_for_deploy(clicked_unit)
	elif selected_unit and clicked_cell in highlighted_tiles:
		place_selected_unit(clicked_cell)
	else:
		deselect()

func select_unit_for_deploy(u: Node) -> void:
	clear_highlights()
	selected_unit = u
	highlighted_tiles = get_deploy_zone_empty_tiles()
	highlight_tiles()

# Todas as células da zona de deploy que estão vazias — ou ocupadas pela
# própria unidade selecionada, pra permitir reposicionar sem travar.
func get_deploy_zone_empty_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var allow_fluid = can_unit_cross_fluid(selected_unit)
	for x in range(DEPLOY_ZONE_WIDTH):
		for y in MAP_HEIGHT:
			var cell = Vector2i(x, y)
			if fluid_cells.has(cell) and not allow_fluid:
				continue
			if wall_cells.has(cell):
				continue
			var occupant = get_unit_at(cell)
			if occupant == null or occupant == selected_unit:
				tiles.append(cell)
	return tiles

func place_selected_unit(target: Vector2i) -> void:
	selected_unit.move_to(target)
	deselect()
	refresh_start_button()
	check_deploy_complete()

func check_deploy_complete() -> void:
	for u in player_units:
		if u.grid_pos.x < 0:
			return   # ainda tem gente esperando pra ser posicionada (coluna de staging, ver get_staging_position)
	start_battle()

# Habilita start_button assim que PELO MENOS UMA unidade estiver fora da
# coluna de staging (grid_pos.x >= 0) — permite ao jogador escolher lutar
# com menos que o roster inteiro. Chamada em _ready() (estado inicial, todo
# mundo em staging = desabilitado) e de novo em place_selected_unit() toda
# vez que alguém é posicionado/reposicionado.
func refresh_start_button() -> void:
	for u in player_units:
		if u.grid_pos.x >= 0:
			start_button.disabled = false
			return
	start_button.disabled = true

func _on_start_pressed() -> void:
	if phase != Phase.DEPLOY:
		return
	start_battle()

func start_battle() -> void:
	phase = Phase.BATTLE
	start_button.visible = false
	# Quem ainda estiver esperando na coluna de staging (grid_pos.x < 0,
	# ver get_staging_position) NÃO entra na batalha — o jogador escolheu
	# deixar essa unidade de fora ao apertar Start antes de posicionar todo
	# mundo. Remover daqui, ANTES de spawn_enemies() recalcular `units` (=
	# player_units + enemy_units) e de start_turn_order()/build_unit_summary_hud()
	# montarem fila de turnos e HUD (ambos rodam DEPOIS, olhando pro
	# player_units já filtrado), é o que garante que ela nunca luta, nunca
	# aparece no HUD e nunca entra no loop de award_experience() (que só
	# itera player_units).
	var deployed: Array[Node] = []
	for u in player_units:
		if u.grid_pos.x < 0:
			u.queue_free()
		else:
			deployed.append(u)
	player_units = deployed
	fog_layer.clear()
	spawn_enemies()
	_apply_starting_weather()
	_trigger_start_of_battle_abilities()
	start_turn_order()

# Clima "de fábrica" desta batalha, se houver um configurado (pedido do
# usuário: "Some battles may activate permanent weather effects at the
# start") — Trainer (GameState.current_trainer_starting_weather, copiado por
# world.gd::start_trainer_battle ANTES da troca de cena, ver comentário lá)
# ou selvagem (GameState.current_area.starting_weather, a mesma EncounterArea
# que spawn_enemies() acima já usou pra sortear os inimigos). permanent=true
# sempre — um clima de início de batalha nunca conta rodada sozinho, só
# termina se algo mais tarde o substituir (ver weather_overridable/
# can_override_weather). activator=null: ninguém "carrega item" por um
# clima que nasce com a batalha, então extends_weather nunca entra em jogo
# aqui (ver try_set_weather/_activator_extends_weather).
func _apply_starting_weather() -> void:
	var weather := ""
	var overridable := true
	if GameState.is_trainer_battle:
		weather = GameState.current_trainer_starting_weather
		overridable = GameState.current_trainer_starting_weather_overridable
	elif GameState.current_area != null:
		weather = GameState.current_area.starting_weather
		overridable = GameState.current_area.starting_weather_overridable
	if weather != "":
		try_set_weather(weather, null, true, overridable)

# Habilidades "de entrada" que ativam clima sozinhas (ver AbilityData.
# sets_weather_on_battle_start — Desolate Land, do Groudon, é a primeira) —
# checado uma vez só aqui, DEPOIS de spawn_enemies() (jogador E inimigo já
# existem, `units` já está preenchido) e DEPOIS de _apply_starting_weather()
# (clima "de fábrica" do mapa/Trainer, se houver, já ativo — uma Habilidade
# pode perfeitamente substituir isso, sujeita às mesmas regras de sempre em
# can_override_weather, incluindo starting_weather_overridable=false
# travando até uma Habilidade). Ordenado por Speed, do maior pro menor —
# pedido do usuário: "When multiple units have Start of Battle abilities,
# they resolve in speed order, from highest to lowest". Não precisa de
# nenhum tratamento especial pra conflito entre duas Habilidades diferentes
# (ex: uma futura "Primordial Sea" mais lenta tentando substituir Desolate
# Land de um Groudon mais rápido): como cada uma chama try_set_weather() na
# ORDEM em que é processada, quem processa DEPOIS já usa a regra normal de
# override (Harsh Sunlight só cede pra Heavy Rain/Strong Winds, ver
# EXTREME_WEATHERS) — a própria ordem de chamada resolve o conflito sozinha.
func _trigger_start_of_battle_abilities() -> void:
	var ordered: Array = units.duplicate()
	ordered.sort_custom(func(a, b): return a.get_effective_stat("speed") > b.get_effective_stat("speed"))
	for u in ordered:
		if u.data == null:
			continue
		for action in u.data.slots:
			if action is AbilityData and action.sets_weather_on_battle_start != "":
				try_set_weather(action.sets_weather_on_battle_start, u)

# Sorteia UM grupo da EncounterArea ativa (GameState.current_area,
# setada por world.gd antes da troca de cena — ver encounter_area.gd/
# encounter_group.gd) e spawna EXATAMENTE as entries daquele grupo, uma
# unidade por entrada, na ordem em que estão no grupo, CADA UMA no nível da
# sua própria EncounterEntry (não é mais um GameState.STARTING_LEVEL fixo
# pra todo mundo — ex: <0473,54> + <0220,2> sempre traz um Mamoswine nível
# 54 e um Swinub nível 2 juntos). Repetir a mesma espécie em entries
# diferentes é o jeito de ter "N cópias dela nessa batalha", ex:
# <0158,5>+<0158,5>+<0158,5> sempre traz 3 Totodile nível 5 juntos — não é
# mais um número aleatório de inimigos de espécie aleatória, é o grupo
# inteiro sorteado que aparece. Cada inimigo usa apply_fresh_data (HP cheio,
# sem ler/escrever level/xp/hp de verdade) — várias unidades inimigas podem
# apontar pro mesmo UnitData sem conflito nenhum, já que ninguém escreve nele.
func spawn_enemies() -> void:
	var hidden_cells: Array[Vector2i] = []
	for x in range(DEPLOY_ZONE_WIDTH, MAP_WIDTH):
		for y in MAP_HEIGHT:
			hidden_cells.append(Vector2i(x, y))
	hidden_cells.shuffle()

	# Trainer (ver trainer.gd/GameState.is_trainer_battle) spawna do time
	# JÁ RESOLVIDO que world.gd::start_trainer_battle() copiou pra
	# GameState.current_trainer_team antes de trocar de cena — Trainer.
	# get_active_team() já escolheu o tier certo (número de badges) e cada
	# entrada já traz seu loadout (vazio = automático, ver TrainerTeamEntry).
	# Sem isso NÃO teria como spawn_enemies() ler o node Trainer de volta:
	# change_scene_to_file() já destruiu a cena de overworld inteira, Trainer
	# incluso, antes de battle.tscn sequer existir.
	# Times "Rocket" (ver Trainer.iq) ganham 1 Rocket Ball automática em CADA
	# unidade, além do loadout já configurado/automático de cada uma — ver
	# comentário grande em Unit.apply_fresh_data::extra_loadout.
	#
	# NÃO dá pra escrever isso como uma linha só (`[ROCKET_BALL_ITEM] if ...
	# else []`) — um literal de array dentro de um ternário sai como Array
	# comum (sem tipo nenhum), e GDScript recusa atribuir isso a uma variável
	# declarada Array[ActionData] ("Trying to assign an array of type
	# 'Array' to a variable of type 'Array[ActionData]'", erro visto ao
	# iniciar batalha contra um treinador Rocket). Declarar vazio e usar
	# append() condicional mantém o array já tipado o tempo todo.
	var extra_loadout: Array[ActionData] = []
	if GameState.current_trainer_iq == "Rocket":
		extra_loadout.append(ROCKET_BALL_ITEM)

	if GameState.is_trainer_battle:
		for entry in GameState.current_trainer_team:
			_spawn_enemy_unit(entry.species, entry.level, entry.loadout, hidden_cells, extra_loadout)
	else:
		# current_encounter_source ("Grass"/"Water"/"Fishing", ver
		# EncounterGroup.source) — quem chamou world.gd::_start_encounter()
		# antes de trocar de cena pra cá já escreveu o valor certo em
		# GameState (grama alta = "Grass" de sempre; surfando em cima
		# d'água = "Water", ver world.gd::_on_player_tile_entered).
		var group = GameState.current_area.pick_group(GameState.current_encounter_source) if GameState.current_area != null else null
		var entries: Array[EncounterEntry] = group.entries if group != null else []
		for entry in entries:
			_spawn_enemy_unit(entry.species, entry.level, [], hidden_cells, [])

	units = player_units + enemy_units

# Extraído de spawn_enemies() pra servir os dois caminhos (selvagem E
# Trainer) sem duplicar a parte de posicionar/marcar/conectar sinais —
# forced_loadout vazio reproduz exatamente o comportamento selvagem de
# sempre (ver Unit.apply_fresh_data).
func _spawn_enemy_unit(species: UnitData, level: int, forced_loadout: Array[ActionData], hidden_cells: Array[Vector2i], extra_loadout: Array[ActionData] = []) -> void:
	var pos = pop_valid_cell(hidden_cells, species)
	if pos == null:
		return   # não sobrou nenhuma célula válida pra essa unidade (raro)
	var e = UNIT_SCENE.instantiate()
	add_child(e)
	e.apply_fresh_data(species, level, forced_loadout, extra_loadout)
	# GameState.current_trainer_iq (ver Trainer.iq) sobrescreve o iq da
	# ESPÉCIE pra TODA unidade deste Trainer — "" (batalha selvagem, ou
	# Trainer sem iq preenchido, nunca acontece hoje já que o padrão é
	# "Medium") deixa cada UnitData.iq valer sozinho, sem sobrescrever nada.
	if GameState.current_trainer_iq != "":
		e.iq = GameState.current_trainer_iq
	e.mark_as_enemy()
	e.init(pos)
	enemy_units.append(e)
	# Inimigo agora entra em turn_queue igual jogador (ver start_turn_order),
	# então isso passa a valer de verdade: se algum efeito mudar a Speed de
	# um inimigo no meio da rodada, a fila reordena do mesmo jeito.
	e.speed_changed.connect(reorder_turn_queue_by_speed)
	# Mesmo raciocínio de spawn_player_units_staged() — init() acima é só
	# posicionamento instantâneo (não conta como "entrar" em lugar nenhum,
	# mesmo espírito de Player.teleport_to() no overworld), então um
	# inimigo não se queima só por NASCER em cima de lava; só ao andar pra
	# lá de verdade depois.
	e.tile_entered.connect(_on_unit_tile_entered.bind(e))

# Tira da lista `cells` (in-place) e devolve a primeira célula que essa
# unidade consegue ocupar — pula o fluido se ela não puder atravessar.
func pop_valid_cell(cells: Array[Vector2i], data: UnitData):
	var allow_fluid = can_cross_fluid(data)
	for idx in cells.size():
		var cell = cells[idx]
		if fluid_cells.has(cell) and not allow_fluid:
			continue
		if wall_cells.has(cell):
			continue
		cells.remove_at(idx)
		return cell
	return null

# ---------- Fase de batalha ----------

func start_turn_order() -> void:
	# player_units + enemy_units, intercalados por Speed — antes só o time do
	# jogador entrava aqui (inimigo não tinha IA pra jogar seu turno, ver
	# comentário antigo em spawn_enemies()). Agora que run_enemy_turn() existe,
	# inimigo participa da fila normalmente; begin_current_turn() é quem
	# decide, pelo is_enemy da unidade da vez, se espera clique do jogador ou
	# chama a IA sozinha.
	turn_queue = player_units + enemy_units
	# get_effective_stat("speed") em vez do stat cru: já nasce certo mesmo se
	# alguém entrar em campo com um estágio de Speed alterado (não acontece
	# hoje, mas não custa nada usar o valor "de verdade" desde o início).
	turn_queue.sort_custom(func(a, b): return a.get_effective_stat("speed") > b.get_effective_stat("speed"))
	current_turn_index = 0
	build_unit_summary_hud()
	unit_summary.visible = true
	end_turn_button.visible = true
	undo_button.visible = true
	flee_button.visible = true
	action_slots.visible = true
	begin_current_turn()

func get_current_unit() -> Node:
	if turn_queue.is_empty():
		return null
	return turn_queue[current_turn_index]

# Chamado (via o sinal Unit.speed_changed) toda vez que a Speed de alguém
# muda durante a batalha — reordena SÓ quem ainda não jogou nesta rodada
# pela velocidade ATUAL, sem mexer em quem já jogou nem em quem está jogando
# agora. É assim que "sem repetir turno de ninguém" e "não quebra se 3 ficar
# mais rápida que 1" (mesmo que 1 já tenha jogado) ficam garantidos ao mesmo
# tempo: current_turn_index nunca muda aqui, só o que vem DEPOIS dele.
#
# Exemplo: fila 1,2,3 (1 mais rápida). No turno de 1 (current_turn_index=0),
# ela usa um efeito que aumenta a Speed de 3 além da de 2. acted = [] (1
# ainda está jogando, não "já jogou"), current_unit = 1, pending = [2,3] ->
# reordenado por Speed atual -> [3,2]. Fila vira 1,3,2 — quando o turno de 1
# terminar, quem joga a seguir é 3, não 2, sem repetir ninguém.
func reorder_turn_queue_by_speed() -> void:
	if phase != Phase.BATTLE or turn_queue.is_empty():
		return
	var acted = turn_queue.slice(0, current_turn_index)
	var current_unit = turn_queue[current_turn_index]
	var pending = turn_queue.slice(current_turn_index + 1, turn_queue.size())
	pending.sort_custom(func(a, b): return a.get_effective_stat("speed") > b.get_effective_stat("speed"))
	turn_queue = acted + [current_unit] + pending
	# A fileira de portraits em cima do mapa É a fila — se a ordem mudou de
	# verdade (alguém ficou mais rápido/lento no meio da rodada), ela precisa
	# refletir isso na hora, não só na próxima vez que begin_current_turn()
	# rodar.
	build_unit_summary_hud()

func begin_current_turn() -> void:
	deselect()
	cancel_targeting()
	var u = get_current_unit()
	if u == null:
		return
	turn_start_pos = u.grid_pos

	# Paralyzed: rolamento de "trava total" deste turno (pedido do usuário:
	# "be a random roll to be fully paralyzed at the start of turn (cant
	# move nor attack) 1/8 chance") — resetado E rolado de novo A CADA
	# início de turno desta unidade, nunca herdado do turno anterior. Fora
	# desse rolamento, Paralyzed não trava nada sozinha (só reduz Speed pela
	# metade, ver Unit.get_effective_stat) — por isso ela NÃO está em
	# MOVEMENT_BLOCKING_STATUS/ATTACK_BLOCKING_STATUS (ver comentário grande
	# das duas em unit.gd). Roda ANTES do ramo de Flinched abaixo: os dois
	# são independentes (uma unidade Flinched não está mais em turno
	# nenhum mesmo, então o valor de fully_paralyzed_this_turn dela não
	# importa neste turno, mas fica certo pro próximo já que só é lido por
	# can_move/can_attack quando o turno de verdade começa a valer, no ramo
	# `else` logo abaixo).
	u.fully_paralyzed_this_turn = u.has_status("Paralyzed") and randf() < 1.0 / 8.0
	if u.fully_paralyzed_this_turn:
		log_message("%s is fully paralyzed!" % u.data.unit_name)

	# Protected (ver AttackData.inflicts_status_on_self/Protect, pedido do
	# usuário: "full immunity until its next turn") — mesmo espírito de
	# Flinched logo abaixo (cura NA HORA aqui, não por contador decrescente),
	# só que Protected NUNCA trava movimento nem ataque desta unidade (por
	# isso não entra em MOVEMENT_BLOCKING_STATUS/ATTACK_BLOCKING_STATUS) —
	# ela só bloqueia ataques ALHEIOS enquanto ativa (ver has_status(
	# "Protected") em execute_attack/execute_attack_burst/
	# execute_status_attack). "Até o próximo turno" = literalmente até bem
	# aqui, no início do PRÓXIMO begin_current_turn desta mesma unidade,
	# então isso precisa rodar ANTES do resto da função decidir
	# move_budget_left/attacks_remaining (embora Protected não mude nenhum
	# dos dois, diferente de Flinched).
	if u.has_status("Protected"):
		u.cure_status_condition("Protected")

	# Flinched é diferente das outras Status Conditions com duração: ela só
	# deveria custar UM turno inteiro (movimento e ataque zerados) e sumir
	# "no começo do turno seguinte" — ou seja, bem aqui, agora, no início
	# deste turno que ela acabou de travar. Por isso ela é curada NA HORA,
	# em vez de decrementar o contador no fim do turno como as demais
	# condições com prazo (ver apply_end_of_turn_status).
	if u.has_status("Flinched"):
		u.cure_status_condition("Flinched")
		move_budget_left = 0
		u.attacks_remaining = 0
	else:
		move_budget_left = u.move_range if u.can_move() else 0
		u.attacks_remaining = 1 if u.can_attack() else 0
		# Chlorophyll (ver AbilityData.chlorophyll/has_chlorophyll): "extra
		# action point" enquanto Sunny/Harsh Sunlight estiver ativo — soma
		# +1 em cima do 1 normal, reaproveitando de propósito o comentário
		# antigo de Unit.attacks_remaining sobre esse campo já ser um int
		# (não bool) só de olho num efeito assim. `u.can_attack()` de novo
		# aqui (não só `else` acima) porque uma unidade travada por status
		# (Frozen/Asleep/Flinched/paralisia total do turno) não deveria
		# ganhar NENHUM ataque extra — 0 + 1 seria um bug, não um bônus.
		if u.can_attack() and has_chlorophyll(u) and is_sun_weather():
			u.attacks_remaining += 1
		# Tailwind (ver Unit.STATUS_DURATIONS, pedido do usuário, Butterfree:
		# "For 2 turns, gain 2x speed and extra action point") — mesmo padrão
		# de Chlorophyll acima, só que checando a Status Condition da própria
		# unidade em vez do clima da batalha. O 2x Speed já é lido à parte em
		# Unit.get_effective_stat(), sem precisar de nada aqui.
		if u.can_attack() and u.has_status("Tailwind"):
			u.attacks_remaining += 1

	# Golpe de carga pendente (ver Unit.charging_attack/AttackData.
	# is_charge_move — Solar Beam) — "as soon as the unit has another action
	# point, it fires... at the start of the user's next turn, they will
	# fire before being able to do anything else" (pedido do usuário). Por
	# isso mora bem aqui, DEPOIS de attacks_remaining já estar com o valor
	# final do turno (incluindo bônus de Chlorophyll acima) e ANTES de
	# qualquer HUD/IA rodar. `u.attacks_remaining > 0` cobre os dois casos:
	# unidade travada (Frozen/Asleep/paralisia total) não dispara nada este
	# turno — o golpe continua guardado, tenta de novo no turno seguinte —
	# e uma unidade com Chlorophyll ainda gasta só 1 dos possíveis 2 Action
	# Points no disparo, sobrando o outro pra agir normalmente depois.
	if u.charging_attack != null and u.attacks_remaining > 0:
		var charged_attack: AttackData = u.charging_attack
		var charged_dir: Vector2i = u.charging_dir
		var charged_slot: int = u.charging_slot_index
		u.charging_attack = null
		u.charging_dir = Vector2i.ZERO
		u.charging_slot_index = -1
		await execute_attack_burst(u, charged_attack, charged_dir, charged_slot, true)
		# execute_attack_burst() pode ter encadeado check_auto_end_turn() ->
		# _on_end_turn_pressed() -> begin_current_turn() da PRÓXIMA unidade
		# (ou até encerrado a batalha) enquanto este await estava suspenso —
		# mesmo padrão de recursão que o resto do arquivo já usa (ver
		# check_auto_end_turn no fim desta função). Se isso aconteceu, quem
		# dera continuar preenchendo HUD/IA pra ESTA unidade com estado
		# velho: sai na hora, a chamada mais interna da recursão já deixou
		# tudo certo pra unidade de verdade atual.
		if phase != Phase.BATTLE or get_current_unit() != u:
			return

	refresh_unit_summary_hud()

	# Turno de inimigo: nenhum HUD de ação do jogador faz sentido pra unidade
	# que não é dele (ver comentário de run_enemy_turn), então escondemos em
	# vez de preencher com o loadout do inimigo. A IA decide sozinha e chama
	# _on_end_turn_pressed() no final — não passa por check_auto_end_turn().
	if u.is_enemy:
		action_slots.visible = false
		end_turn_button.visible = false
		undo_button.visible = false
		# flee_button também precisa sumir aqui — ficava visível E CLICÁVEL
		# durante o turno do inimigo (só os outros 3 botões eram escondidos),
		# então dava pra apertar Flee no meio de run_enemy_turn() enquanto ele
		# está suspenso num await (movimento/ataque da IA). _on_flee_pressed()
		# troca de cena (change_scene_to_file), que libera a árvore inteira —
		# quando o await da IA retomava depois disso, ele tentava mexer em
		# nós (attacker/defender/tilemap) já destruídos e crashava. Ver também
		# a guarda extra dentro de _on_flee_pressed() logo abaixo.
		flee_button.visible = false
		struggle_button.visible = false
		run_enemy_turn(u)
		return

	action_slots.visible = true
	end_turn_button.visible = true
	undo_button.visible = true
	flee_button.visible = true
	refresh_action_slots_hud()

	# Se a unidade começou o turno já sem movimento NEM ataque (travada por
	# status), passa o turno dela sozinha em vez de deixar a batalha "parada"
	# esperando o jogador apertar Pass à toa — mesmo gancho usado depois de
	# mover/atacar (ver check_auto_end_turn). Encadeia normalmente se a
	# PRÓXIMA unidade também estiver travada.
	check_auto_end_turn()

# Monta um slot (portrait + HP) por unidade EM turn_queue, jogador e
# inimigo juntos, na MESMA ordem em que vão jogar — a fileira em cima do
# mapa é a visualização da fila de turnos inteira, não só o time do
# jogador. Chamado quando a batalha começa (start_turn_order()) e de novo
# toda vez que a ordem muda de verdade (ver reorder_turn_queue_by_speed()) —
# reconstruir do zero é mais simples que mover/inserir nós um a um, e
# batalha é turn-based (a fila não muda a cada frame), então o custo de
# recriar uns poucos Control por chamada é irrelevante.
#
# Portrait de inimigo sai ESPELHADA (TextureRect.flip_h) só aqui, na
# fileira — não mexe no sprite dele no mapa (Unit usa AnimatedSprite2D
# próprio) — é só reforço visual de "este lado é o time adversário".
func build_unit_summary_hud() -> void:
	for child in unit_summary.get_children():
		child.queue_free()
	unit_slots.clear()
	unit_hp_labels.clear()

	# Largura de cada slot depende de QUANTOS estão na fila agora (time
	# parcial + N inimigos de uma vez não é sempre 6) — encolhe até
	# UNIT_SUMMARY_SLOT_MIN_WIDTH em vez de vazar pra fora do HUD.
	var count = max(turn_queue.size(), 1)
	var slot_width = clamp((UNIT_SUMMARY_WIDTH - (count - 1) * UNIT_SUMMARY_SLOT_SEP) / count, UNIT_SUMMARY_SLOT_MIN_WIDTH, UNIT_SUMMARY_SLOT_MAX_WIDTH)
	var portrait_size = max(slot_width - 27.0, 20.0)   # -27 no slot_width máximo (75) dá exatamente os 48px de sempre

	for u in turn_queue:
		var slot = PanelContainer.new()
		slot.custom_minimum_size = Vector2(slot_width, 72)

		var box = VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_child(box)

		var portrait = TextureRect.new()
		portrait.texture = u.data.portrait
		portrait.custom_minimum_size = Vector2(portrait_size, portrait_size)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.flip_h = u.is_enemy
		box.add_child(portrait)

		var hp_label = Label.new()
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hp_label)

		unit_summary.add_child(slot)
		unit_slots[u] = slot
		unit_hp_labels[u] = hp_label

	refresh_unit_summary_hud()

# Chamada por try_set_weather() (ativou/trocou clima) e _advance_weather_turn()
# (desconta rodada, ou encerra o clima) — nunca precisa ser chamada de mais
# nenhum outro lugar, essas duas cobrem toda mudança possível de
# current_weather/weather_turns_left. Separada de refresh_weather_mask()
# logo abaixo (que antes era a MESMA função, refresh_weather_hud) porque o
# nome/contador aparecem NA HORA, enquanto o mask pode esperar a animação de
# entrada terminar primeiro (ver play_weather_anim/try_set_weather) — pedido
# do usuário: "play this animation on top left of the battlefield and THEN
# apply the mask". weather_turns_left < 0 (permanente, ver comentário
# grande na declaração) mostra só o nome, sem contador — não faz sentido
# escrever "turns left" de algo que não desconta sozinho.
func refresh_weather_label() -> void:
	if current_weather == WEATHER_NONE:
		weather_label.visible = false
		return
	weather_label.visible = true
	if weather_turns_left < 0:
		weather_label.text = current_weather
	else:
		weather_label.text = "%s\n%d turn%s left" % [current_weather, weather_turns_left, "" if weather_turns_left == 1 else "s"]

# Ver comentário grande de refresh_weather_label acima sobre por que isto é
# uma função separada agora. Sem entrada em WEATHER_MASK_COLORS (só Strong
# Winds hoje, ver comentário lá) = sem máscara nenhuma, mesmo com clima
# ativo — só o texto de refresh_weather_label aparece.
func refresh_weather_mask() -> void:
	if current_weather == WEATHER_NONE or not WEATHER_MASK_COLORS.has(current_weather):
		weather_mask.visible = false
		return
	weather_mask.color = WEATHER_MASK_COLORS[current_weather]
	weather_mask.visible = true

# Atualiza o texto de nível/HP de todo mundo e a borda de quem está na vez —
# AZUL se for a vez de uma unidade do jogador, VERMELHA se for a vez de um
# inimigo (antes a borda era sempre azul e só existia pra player_units, já
# que unit_slots não tinha inimigo nenhum; agora que build_unit_summary_hud()
# monta slot pra turn_queue inteira, dá pra diferenciar de quem é a vez só
# olhando a cor). Chamar sempre que o turno mudar, o HP de alguém mudar, ou
# alguém subir de nível. Mostra nível aqui só por debug por enquanto — xp não
# aparece ainda (vamos precisar disso no futuro, ver ExpGroups.exp_to_next_level).
func refresh_unit_summary_hud() -> void:
	var current = get_current_unit()
	for u in unit_slots.keys():
		var slot: PanelContainer = unit_slots[u]
		var hp_label: Label = unit_hp_labels[u]
		# Só HP aqui embaixo do portrait — Status Condition JÁ tem indicador
		# visual próprio (o emote animado em cima do sprite no mapa, ver
		# Unit._start_status_emote), então repetir como texto aqui era
		# redundante e deixava o label pequeno demais poluído. O resto
		# (nível, Speed, exp, status) mora só no tooltip agora.
		# Pedido do usuário: "remove the currentHP/maxHP for enemy units
		# shown below their portraits" — só o time do jogador mostra o
		# número exato agora; texto vazio (não hide) pra manter a mesma
		# altura de slot entre as duas fileiras, sem espaço em branco
		# "pulando" quando a vez passa de um time pro outro.
		hp_label.text = "%d/%d" % [u.hp_current, u.hp_max] if not u.is_enemy else ""

		# Tooltip do portrait: nível, Speed (já com estágio alterado, se
		# tiver — ver Unit.get_effective_stat), Status Condition (se tiver
		# alguma ativa) e quanto falta de exp pro próximo nível
		# (ExpGroups.exp_to_next_level já existia, só não era mostrado em
		# lugar nenhum até agora).
		var tooltip_lines = [
			"Nv. %d" % u.level,
			"Speed: %d" % u.get_effective_stat("speed"),
		]
		# Empilhável agora (ver Unit.status_conditions) — junta todas as
		# condições ativas numa linha só, separadas por vírgula. "Charged"
		# (Flash Fire, ver comentário grande dela em unit.gd) fica DE FORA
		# de propósito: é um estado interno pra lógica de dano, não algo
		# que o design queria expor pro jogador como "Status" visível.
		var visible_statuses: Array = []
		for status_name in u.status_conditions.keys():
			if status_name != "Charged":
				visible_statuses.append(status_name)
		if not visible_statuses.is_empty():
			tooltip_lines.append("Status: %s" % ", ".join(visible_statuses))
		if u.level >= ExpGroups.MAX_LEVEL:
			tooltip_lines.append("Nível máximo")
		else:
			var exp_missing = ExpGroups.exp_to_next_level(u.level, u.xp, u.data.growth_group)
			tooltip_lines.append("Exp até o próximo nível: %d" % exp_missing)
		slot.tooltip_text = "\n".join(tooltip_lines)

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
		style.set_content_margin_all(4)
		if u == current:
			style.border_color = Color(0.9, 0.2, 0.2) if current.is_enemy else Color(0.2, 0.6, 1.0)
			style.set_border_width_all(3)
		slot.add_theme_stylebox_override("panel", style)

# Cor de borda por tipo elemental de AttackData (mesmo vocabulário de
# UnitData.types/AttackData.element_type) — usada por _apply_slot_border() em
# refresh_action_slots_hud(). ABILITY_BORDER_COLOR/ITEM_BORDER_COLOR cobrem
# os outros dois "tipos" de ação possíveis num slot (só existe UM valor fixo
# pra cada, não varia igual os elementos de ataque).
const TYPE_BORDER_COLORS := {
	"Bug": Color("#94bc4a"),
	"Dark": Color("#736c75"),
	"Dragon": Color("#6a7baf"),
	"Electric": Color("#e5c531"),
	"Fairy": Color("#e397d1"),
	"Fighting": Color("#cb5f48"),
	"Fire": Color("#ea7a3c"),
	"Flying": Color("#7da6de"),
	"Ghost": Color("#846ab6"),
	"Grass": Color("#71c558"),
	"Ground": Color("#cc9f4f"),
	"Ice": Color("#70cbd4"),
	"Normal": Color("#aab09f"),
	"Poison": Color("#b468b7"),
	"Psychic": Color("#e5709b"),
	"Rock": Color("#b2a061"),
	"Steel": Color("#89a1b0"),
	"Water": Color("#539ae2"),
}
const ABILITY_BORDER_COLOR = Color("#81a596")
const ITEM_BORDER_COLOR = Color("#e4e3e9")
const BALL_BORDER_COLOR = Color("#d94f4f")

const SLOT_BORDER_WIDTH = 3
const SLOT_BG_COLOR = Color(0.1, 0.1, 0.12, 0.85)
# Multiplicador de alpha (fundo E borda) usado no estado "disabled" do botão
# — é o que preserva a "transparência" de quem não pode ser usado (item
# passivo, ataque sem uso/já usado no turno) mesmo com a borda colorida.
const SLOT_DISABLED_ALPHA = 0.35

# true se `u` tem PELO MENOS UM slot clicável agora — mesmas 3 regras que
# refresh_action_slots_hud() já aplica slot por slot (Habilidade nunca é
# clicável; Item só conta se for Ball/TM com carga > 0; Ataque só conta se
# max_uses <= 0 ou ainda sobrar uso), só que aqui sem mexer em nenhum botão,
# usado só pra decidir se struggle_button deve aparecer (ver
# refresh_action_slots_hud logo abaixo). Pedido do usuário: Struggle
# "appears IF and ONLY IF the unit has no available actions", que ele mesmo
# resume em 3 casos — loadout vazio, todo Ataque sem uso, ou só Habilidade/
# Item passivo no loadout. Os 3 casos são, na prática, o MESMO caso: nenhum
# slot passa em nenhuma das checagens abaixo.
func has_usable_slot_action(u: Node) -> bool:
	for i in u.data.slots.size():
		var action: ActionData = u.data.slots[i]
		if action == null or action is AbilityData:
			continue
		if action is ItemData:
			if action.category == "Ball" or action.category == "TM":
				if u.data.get_slot_quantity(i) > 0:
					return true
			continue   # Held Item/Medicine/Berry: nunca clicável em batalha
		if action is AttackData:
			if action.max_uses <= 0 or (i < u.slot_uses.size() and u.slot_uses[i] > 0):
				return true
	return false

# Atualiza o texto/estado dos 6 botões de ação com o loadout da unidade da
# vez. Caixa pequena, conteúdo mínimo: Ataque mostra Nome + usos; Habilidade
# só o Nome (toda Habilidade é passiva, marcar isso no texto virou redundante
# — ver AbilityData); Item só o ícone, sem nome nenhum (ver ItemData.icon).
# A borda de cada botão também é colorida por tipo/categoria (ver
# _apply_slot_border) pra ficar fácil de reconhecer de relance.
# Apertar o botão ainda não faz o ataque de verdade, isso vem na próxima
# etapa (lógica de combate).
func refresh_action_slots_hud() -> void:
	var current = get_current_unit()
	for i in ACTION_SLOT_COUNT:
		var button: Button = _get_action_slot_button(i)
		button.icon = null            # limpa ícone de Item de um refresh anterior (ver bloco ItemData abaixo)
		button.tooltip_text = ""      # idem pro tooltip de Ataque (ver bloco AttackData abaixo)

		if current == null or i >= current.data.slots.size() or current.data.slots[i] == null:
			button.text = "Vazio"
			button.disabled = true
			_reset_slot_border(button)   # slot vazio não é ataque/habilidade/item — sem borda colorida
			continue

		var action: ActionData = current.data.slots[i]

		# Habilidade é passiva — nunca é "usada" pelo jogador (ver comentário
		# em AbilityData), então o botão só mostra o nome dela e fica sempre
		# desabilitado, sem entrar nas checagens de uso/ataque abaixo.
		if action is AbilityData:
			button.text = action.action_name
			button.disabled = true
			button.tooltip_text = _build_ability_tooltip(action, current.data)
			_apply_slot_border(button, ABILITY_BORDER_COLOR)
			continue

		# Ball e TM são as ÚNICAS categorias de Item clicáveis NA BATALHA —
		# usá-las conta como a ação do turno (mesmo attacks_remaining que
		# Ataque usa, ver AttackData abaixo). As duas são Stackable (ver
		# ItemData.stackable), então o botão SEMPRE mostra quanto ainda resta
		# nesse slot (UnitData.get_slot_quantity) — sem isso o jogador não
		# tinha como saber se ainda tinha bola/TM sobrando sem abrir tooltip
		# nenhum.
		if action is ItemData and action.category == "Ball":
			var quantity = current.data.get_slot_quantity(i)
			button.text = "%dx" % quantity
			button.icon = action.icon
			button.disabled = current.attacks_remaining <= 0 or quantity <= 0
			button.tooltip_text = _build_item_tooltip(action) + "\nQuantidade: %d" % quantity
			_apply_slot_border(button, BALL_BORDER_COLOR)
			continue

		# TM: se comporta como um Ataque na HUD (nome + contagem, borda na
		# cor do TIPO do ataque que ele ensina — ver tm_attack) só que a
		# "contagem" mostrada é quantas cargas do ITEM ainda restam nesse
		# slot, não o max_uses/PP do ataque em si (ver execute_tm_attack:
		# usar TM 10 não gasta PP de Ice Fang, gasta 1 unidade de TM 10).
		if action is ItemData and action.category == "TM":
			var tm_attack: AttackData = action.tm_attack
			var quantity = current.data.get_slot_quantity(i)
			button.text = "%s\n%dx" % [action.action_name, quantity]
			button.disabled = current.attacks_remaining <= 0 or quantity <= 0
			if tm_attack != null:
				# "Status" (ver AttackData.is_status) igual _build_attack_tooltip
				# já faz pro ramo de Ataque comum logo abaixo — sem isso, TM
				# 11/Sunny Day (Status) aparecia rotulado "Físico" por engano
				# (era só um "else" sem terceira opção antes desta correção).
				var kind = "Status" if tm_attack.is_status else ("Especial" if tm_attack.is_special else "Físico")
				button.tooltip_text = "%s\nTipo: %s (%s)\nPoder: %d\nCargas restantes: %d" % [
					tm_attack.action_name,
					tm_attack.element_type,
					kind,
					tm_attack.power,
					quantity,
				]
				_apply_slot_border(button, TYPE_BORDER_COLORS.get(tm_attack.element_type, TYPE_BORDER_COLORS["Normal"]))
			else:
				_apply_slot_border(button, ITEM_BORDER_COLOR)
			continue

		# Qualquer OUTRO Item (Held Item equipado, ou Medicine/Berry que por
		# algum motivo esteja no loadout) não é clicável NA BATALHA — Use/
		# Give só acontecem pela Bag, fora de combate (ver
		# item_list_screen.gd). Sem esse continue, cairia no bloco de
		# AttackData logo abaixo e quebraria lendo action.is_special/
		# element_type, que ItemData não tem.
		if action is ItemData:
			button.text = ""
			button.icon = action.icon
			button.disabled = true
			button.tooltip_text = _build_item_tooltip(action)
			_apply_slot_border(button, ITEM_BORDER_COLOR)
			continue

		# Ataque: nome + usos, só isso — a caixa ficou compacta demais pra
		# também mostrar Físico/Especial-Tipo ou "já atacou"; o estado
		# desabilitado do botão já comunica isso visualmente. O tipo ainda
		# aparece, só que na cor da borda (ver TYPE_BORDER_COLORS) em vez de
		# escrito por extenso.
		var label = action.action_name

		# max_uses > 0 = ação com contador (todo ataque, alguns itens). -1 =
		# sem contador — nunca fica sem uso (não é o caso de nenhum Ataque).
		var out_of_uses = action.max_uses > 0 and current.slot_uses[i] <= 0
		if action.max_uses > 0:
			label += "\n%d/%d" % [current.slot_uses[i], action.max_uses]

		# Ataque só pode ser usado 1x por turno (ver Unit.attacks_remaining).
		# Taunted (ver Unit.status_conditions/Rage Powder, pedido do usuário,
		# 2026-07-23, Butterfree: "They gain Taunt status. For 3 turns can't
		# use any Status moves") — trava só golpe is_status=true, ataque comum
		# continua liberado normalmente.
		# Disabled (ver Unit.disabled_attack/STATUS_DURATIONS["Disabled"],
		# pedido do usuário, Venonat: "disables it for 3 turns") — trava só
		# ESSE slot específico (o AttackData que Disable travou), diferente
		# de Taunted (trava TODO golpe de Status de uma vez).
		var attack_locked = action is AttackData and (current.attacks_remaining <= 0 or (action.is_status and current.has_status("Taunted")) or current.disabled_attack == action)

		button.disabled = out_of_uses or attack_locked
		button.text = label
		button.tooltip_text = _build_attack_tooltip(action, current.slot_uses[i])
		var border_color: Color = TYPE_BORDER_COLORS.get(action.element_type, TYPE_BORDER_COLORS["Normal"])
		_apply_slot_border(button, border_color)

	# struggle_button (ver comentário grande onde é declarada) — só aparece
	# pra unidade do JOGADOR (inimigo nem chega a montar esse HUD, ver
	# begin_current_turn), com ataque ainda disponível neste turno E nenhum
	# dos 6 slots reais clicável agora (has_usable_slot_action). Sempre
	# habilitado quando visível — Struggle não tem PP pra "acabar" (max_uses
	# = -1 em struggle.tres), então não existe um estado "desabilitado, mas
	# visível" pra ele, diferente dos outros 6 botões.
	if current != null and not current.is_enemy and current.attacks_remaining > 0 and not has_usable_slot_action(current):
		struggle_button.visible = true
		struggle_button.disabled = false
		struggle_button.tooltip_text = _build_attack_tooltip(STRUGGLE_ATTACK, 0)
	else:
		struggle_button.visible = false

# Texto do tooltip (hover do mouse) de um Ataque — as informações mais
# importantes pra decidir se vale usar: tipo, físico/especial, poder,
# alcance, contato, accuracy e o efeito secundário (se tiver, ver
# AttackData.secondary_status). Usos entra por último, já que o próprio
# botão já mostra isso escrito.
func _build_attack_tooltip(action: AttackData, uses_current: int) -> String:
	var kind = "Status" if action.is_status else ("Especial" if action.is_special else "Físico")
	var area_suffix = ""
	if action.is_projectile:
		area_suffix = " (projétil)"
	elif action.area_shape == "Cone":
		area_suffix = " (cone)"
	elif action.area_shape == "Wide":
		area_suffix = " (frente)"
	var lines = [
		action.action_name,
		"Tipo: %s (%s)" % [action.element_type, kind],
		"Poder: %d" % action.power,
		"Alcance: %d%s" % [action.range, area_suffix],
		"Contato: %s" % ("Sim" if action.makes_contact else "Não"),
		"Accuracy: %d%%" % int(action.accuracy * 100),
	]
	if action.secondary_status != "":
		lines.append("Efeito: %d%% de %s" % [int(action.secondary_status_chance * 100), action.secondary_status])
	# Mudança de stat (ver AttackData.stat_change_stat/_amount) — só ataques
	# de Status usam isso hoje (Growl: -1 Attack em todo inimigo na área).
	if action.stat_change_stat != "":
		var stat_label: String = STAT_DISPLAY_NAMES.get(action.stat_change_stat, action.stat_change_stat)
		var sign_str = "+" if action.stat_change_amount > 0 else ""
		lines.append("Efeito: %s%d em %s (inimigos na área)" % [sign_str, action.stat_change_amount, stat_label])
	# Boost de stat no PRÓPRIO usuário (ver AttackData.self_stat_boost_chance/
	# _amount — Ancient Power é o primeiro caso, diferente de stat_change_stat
	# acima que só existe em ataques de Status mirando inimigo).
	if action.self_stat_boost_amount != 0:
		var boost_sign = "+" if action.self_stat_boost_amount > 0 else ""
		lines.append("Efeito: %d%% de %s%d em todos os stats (usuário)" % [int(action.self_stat_boost_chance * 100), boost_sign, action.self_stat_boost_amount])
	if action.max_uses > 0:
		lines.append("Usos: %d/%d" % [uses_current, action.max_uses])
	return "\n".join(lines)

# Texto do tooltip de uma Habilidade — diferente de Ataque, AbilityData não
# tem um campo de descrição livre (ver comentário na classe: são só campos
# mecânicos específicos, tipo damage_multiplier/immune_type/etc), então o
# texto é montado dinamicamente a partir de QUAIS desses campos estão
# configurados nesta Habilidade — só entra linha pra efeito que ela realmente
# tem. Cobre os 3 "padrões" que existem hoje (ver AbilityData): imunidade de
# tipo (Levitate), boost de dano condicional (Blaze) e supressão de efeito
# secundário por dano extra (Sheer Force).
#
# owner_data é a UnitData da unidade DONA dessa Habilidade nesta batalha —
# precisa dela (não só da Habilidade em si) pra saber se é Hidden PRA ESSA
# ESPÉCIE (ver UnitData.is_ability_hidden/LearnsetEntry.is_hidden_ability):
# a mesma Habilidade pode ser Hidden numa espécie e normal em outra, então
# essa informação não pode vir só de `action`. Mesmo padrão já usado em
# unit_loadout.gd::_display_name().
func _build_ability_tooltip(action: AbilityData, owner_data: UnitData) -> String:
	var title = action.action_name
	if owner_data.is_ability_hidden(action):
		title += " (Hidden)"
	var lines = [title]
	if action.immune_type != "":
		lines.append("Imunidade total a ataques do tipo %s" % action.immune_type)
	if action.grants_levitation:
		lines.append("Concede Levitação (atravessa fluido, ignora Ground)")
	if action.sheer_force:
		lines.append("Ataques com efeito secundário perdem o efeito, mas ganham +%d%% de dano" % int((SHEER_FORCE_MULTIPLIER - 1.0) * 100))
	if action.element_type != "" and action.damage_multiplier != 1.0:
		var condition = "sempre" if action.hp_threshold >= 1.0 else "com HP abaixo de %d%%" % int(action.hp_threshold * 100)
		lines.append("Dano de ataques do tipo %s x%.1f (%s)" % [action.element_type, action.damage_multiplier, condition])
	if not action.resist_types.is_empty() and action.resist_multiplier != 1.0:
		lines.append("Recebe dano x%.1f de ataques do tipo %s" % [action.resist_multiplier, ", ".join(action.resist_types)])
	if action.speed_boost:
		lines.append("Speed +1 ao final de cada turno próprio")
	if lines.size() == 1:
		lines.append("Sem efeito configurado.")
	return "\n".join(lines)

# Texto do tooltip de um Item — effect_description (texto livre, ver
# ItemData) entra primeiro quando existe, seguido dos campos mecânicos
# relevantes pra CADA categoria (Ball tem bônus/captura garantida; Medicine/
# Berry têm heal_amount; Held Item pode ter accuracy_multiplier). Campo no
# valor padrão (0, 1.0, false) não vira linha — só o que realmente muda algo
# aparece, mesmo padrão de _build_attack_tooltip só mostrando secondary_status
# quando ele existe.
func _build_item_tooltip(action: ItemData) -> String:
	var lines = [action.action_name]
	if action.effect_description != "":
		lines.append(action.effect_description)
	if action.category == "Ball":
		if action.guaranteed_capture:
			lines.append("Captura garantida (100%)")
		else:
			lines.append("Bônus de captura: x%.1f" % action.ball_bonus)
	if action.heal_amount > 0:
		lines.append("Cura: %d HP" % action.heal_amount)
	if action.accuracy_multiplier != 1.0:
		lines.append("Accuracy dos ataques de quem carrega: x%.2f" % action.accuracy_multiplier)
	if action.physical_damage_multiplier != 1.0:
		lines.append("Dano de ataques Físicos de quem carrega: x%.2f" % action.physical_damage_multiplier)
	return "\n".join(lines)

# Pinta a borda (+ um fundo escuro neutro, igual o resto do HUD — ver
# refresh_unit_summary_hud) de um botão de ação com `color`. Dois StyleBox
# separados: um pro estado normal (borda na cor cheia) e outro pro estado
# "disabled" (MESMA cor, mas com alpha reduzido — é isso que mantém a
# "transparência" de quem não pode ser usado, mesmo colorido).
func _apply_slot_border(button: Button, color: Color) -> void:
	var normal = StyleBoxFlat.new()
	normal.bg_color = SLOT_BG_COLOR
	normal.border_color = color
	normal.set_border_width_all(SLOT_BORDER_WIDTH)
	normal.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", normal)

	var disabled = StyleBoxFlat.new()
	disabled.bg_color = Color(SLOT_BG_COLOR.r, SLOT_BG_COLOR.g, SLOT_BG_COLOR.b, SLOT_BG_COLOR.a * SLOT_DISABLED_ALPHA)
	disabled.border_color = Color(color.r, color.g, color.b, color.a * SLOT_DISABLED_ALPHA)
	disabled.set_border_width_all(SLOT_BORDER_WIDTH)
	disabled.set_content_margin_all(6)
	button.add_theme_stylebox_override("disabled", disabled)

# Tira qualquer borda colorida de uma chamada anterior (slot ficou vazio —
# ver refresh_action_slots_hud) — volta pro visual padrão do tema, sem
# StyleBox nenhum sobrescrito.
func _reset_slot_border(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		if button.has_theme_stylebox_override(state):
			button.remove_theme_stylebox_override(state)

# Os 6 botões de ação ficam em duas colunas de 3 (ColumnLeft = slots 0-2,
# ColumnRight = slots 3-5, de cima pra baixo — ver battle.tscn) em vez de um
# único container com os 6 em fila. column = index/3 escolhe a coluna certa,
# row = index%3 a posição dentro dela — mantém a correspondência direta com
# UnitData.slots[index] que o resto do código (refresh_action_slots_hud,
# _on_slot_pressed, atalhos de teclado) já espera.
func _get_action_slot_button(index: int) -> Button:
	@warning_ignore("integer_division")
	var column = index / 3
	var row = index % 3
	return action_slots.get_child(column).get_child(row)

func _on_slot_pressed(index: int) -> void:
	var current = get_current_unit()
	if current == null or index >= current.data.slots.size() or current.data.slots[index] == null:
		return
	var action: ActionData = current.data.slots[index]
	# Habilidade é passiva, não clicável — botão já devia estar desabilitado,
	# mas confere de novo aqui por segurança (mesmo padrão do check abaixo).
	if action is AbilityData:
		return
	# Item que não é Ball nem TM também não é clicável na batalha — mesma
	# segurança, ver comentário equivalente em refresh_action_slots_hud().
	# Ball/TM são a exceção (caem direto pro mesmo gate de attacks_remaining
	# que Ataque usa, logo abaixo) — usá-los também conta como a ação do
	# turno.
	if action is ItemData and action.category != "Ball" and action.category != "TM":
		return
	# Slot sem carga nenhuma (Ball/TM stackable zerado) — não deveria nem
	# chegar aqui (get_slot_quantity <= 0 já desabilita o botão, ver
	# refresh_action_slots_hud), mas confere de novo por segurança.
	if action is ItemData and action.stackable and current.data.get_slot_quantity(index) <= 0:
		return
	# Ataque (ou Ball/TM) já usado neste turno — botão devia estar
	# desabilitado, mas confere de novo aqui por segurança.
	if current.attacks_remaining <= 0:
		return
	# Sair do modo de movimento (se tava selecionado) e entrar no modo de mira
	# dessa ação — o highlight vermelho passa a seguir o mouse a partir daqui.
	deselect()
	targeting_action = action
	targeting_slot_index = index

# Gêmeo de _on_slot_pressed() acima pro struggle_button — mais simples
# porque Struggle não vem de UnitData.slots (não existe índice real pra
# checar/travar): o próprio botão só fica visível quando já é legítimo usar
# Struggle (ver refresh_action_slots_hud()/has_usable_slot_action()), então
# as checagens de segurança aqui são só "por garantia", mesmo espírito das
# de _on_slot_pressed. targeting_action = STRUGGLE_ATTACK entra no MESMO
# handle_targeting_input()/_run_player_attack() que qualquer Ataque normal
# usa — Struggle não tem is_status nem is_projectile, então cai direto no
# ramo de ataque comum (mira 1 alvo adjacente).
func _on_struggle_pressed() -> void:
	var current = get_current_unit()
	if current == null or current.attacks_remaining <= 0:
		return
	deselect()
	targeting_action = STRUGGLE_ATTACK
	targeting_slot_index = STRUGGLE_SLOT_INDEX

# Atalho de teclado (1-6, ver ACTION_SLOT_ACTIONS/_unhandled_input) pro
# mesmo botão de ação — respeita EXATAMENTE o estado do botão (button.
# disabled já reúne out_of_uses/attack_locked/etc, ver
# refresh_action_slots_hud), então apertar a tecla nunca faz algo que o
# clique não deixaria fazer.
func _trigger_action_slot_shortcut(index: int) -> void:
	if index >= ACTION_SLOT_COUNT:
		return
	var button: Button = _get_action_slot_button(index)
	if button.disabled:
		return
	_on_slot_pressed(index)
	update_attack_highlight()

# Distância Chebyshev (mesma convenção do movimento — diagonal conta 1 passo,
# igual reto) entre origin e target, comparada com o alcance da ação.
# - Ataque normal (is_projectile falso, ou nem é AttackData): distância EXATA
#   (==), não "até" (<=) — um ataque de range 1 nunca acerta a própria célula
#   da unidade (distância 0), só o anel de tiles a 1 de distância.
# - Ataque-projétil (is_projectile true) OU Ball (category == "Ball"):
#   precisa estar numa linha reta de verdade (horizontal, vertical ou
#   diagonal de 45°) a partir de origin, e a distância só precisa ser <=
#   range (o range é o alcance MÁXIMO — o projétil/bola pode acertar algo
#   mais perto, ver find_projectile_target/find_ball_target). Ball sempre
#   cai aqui (nunca no ramo "distância exata") já que toda Ball se comporta
#   como projétil, sem exceção.
# - TM (category == "TM"): NÃO tem range/is_projectile própria — pra fins de
#   alcance, "é" o ataque que ensina (ver ItemData.tm_attack), então resolve
#   tudo em cima de tm_attack em vez de action (o `range`/`is_projectile` da
#   própria ItemData ficam sem uso nenhum pra TM, só existem por herdar de
#   ActionData).
# Um AttackData conta como "auto-alvo" (afeta só quem usou o golpe, nunca uma
# célula clicada) em TRÊS casos hoje: stat_change_target=="Self" (Growth,
# Defense Curl), self_heal_fraction > 0.0 (Synthesis), ou
# inflicts_status_on_self (Protect — nenhum dos outros dois cobre "aplica uma
# Status Condition em si mesmo", só stat/cura). Extraído como função própria
# (2026-07-23, correção do bug de range 1 vs range 0 apontado pelo Rodrigo)
# pra is_valid_target_cell e update_attack_highlight usarem exatamente o
# MESMO critério — antes, update_attack_highlight só olhava
# stat_change_target=="Self" e deixava Synthesis cair no destaque genérico
# (seguindo o mouse), inconsistente com o próprio golpe só afetar quem usou.
func is_self_target_status(action: ActionData) -> bool:
	return action is AttackData and action.is_status and (action.stat_change_target == "Self" or action.self_heal_fraction > 0.0 or action.inflicts_status_on_self)

func is_valid_target_cell(origin: Vector2i, target: Vector2i, action: ActionData, attacker: Node = null) -> bool:
	var effective_action: ActionData = action
	if action is ItemData and action.category == "TM" and action.tm_attack != null:
		effective_action = action.tm_attack

	# Auto-alvo (Growth/Synthesis/Defense Curl e afins — ver
	# is_self_target_status abaixo): quem é afetado é sempre quem ataca, nunca
	# uma célula vizinha. Rodrigo apontou (2026-07-23) que a UI pedia pra
	# clicar um tile de RANGE 1 (adjacente) pra confirmar esses golpes, o que
	# não fazia sentido — o único "alvo" válido pra esse tipo de ataque é o
	# PRÓPRIO tile de quem ataca (delta ZERO, "range 0"), então aqui a gente
	# ignora attack.range de propósito e só aceita target == origin. Isso
	# também corrige o caso de is_status com self_heal_fraction (Synthesis),
	# que antes caía no ramo genérico "dist == effective_range" lá embaixo
	# igual qualquer ataque normal (nunca dava match porque delta==ZERO
	# retornava false antes mesmo de chegar lá).
	if is_self_target_status(effective_action):
		return target == origin

	# Clima (sets_weather, ver Sunny Day/Rain Dance) e area_shape=="Team" (ver
	# Tailwind) não miram NADA de verdade — o clique só confirma o uso, igual
	# self-target-status acima, só que aqui QUALQUER célula do grid serve
	# (inclusive a própria, ver pedido do usuário 2026-07-23: "Weather moves
	# confirmation indicator should be entire battlefield"/"Tailwind highlight
	# should be all allies" — os dois efeitos não dependem de posição nenhuma,
	# então travar num "range" específico nunca fez sentido pra eles).
	if effective_action is AttackData and (effective_action.sets_weather != "" or effective_action.area_shape == "Team"):
		return true

	var delta = target - origin
	if delta == Vector2i.ZERO:
		return false
	var dist = max(abs(delta.x), abs(delta.y))

	# `attacker` (opcional, null = compatível com todo call site de antes
	# deste parâmetro existir) só importa pra AttackData.
	# scales_with_consecutive_use (ver Rollout) — o alcance de VERDADE (exato,
	# ver `return dist == ...` no fim da função) depende de quantos usos
	# seguidos essa unidade já deu, não do action.range estático (que aqui
	# vira só o teto teórico). Sem `attacker` (ex: alguns callers de IA que
	# ainda não foram atualizados), cai no range estático de sempre — só
	# imprecisão de PREVIEW/IA nesse caso, nunca crasha.
	var effective_range = effective_action.range
	if attacker != null and effective_action is AttackData and effective_action.scales_with_consecutive_use:
		effective_range = get_effective_attack_range(attacker, effective_action)

	var is_projectile_like = (effective_action is AttackData and effective_action.is_projectile) or (action is ItemData and action.category == "Ball")
	if is_projectile_like:
		var is_straight_line = delta.x == 0 or delta.y == 0 or abs(delta.x) == abs(delta.y)
		return is_straight_line and dist <= effective_range

	# Burst (ver AttackData.area_shape/execute_attack_burst/execute_status_
	# attack — Lava Plume, Poison Powder, Safeguard...): CENTRADO em quem
	# ataca, sem direção nenhuma — bug reportado pelo usuário (2026-07-24):
	# faltava esta checagem, então QUALQUER golpe Burst com range > 1 só
	# aceitava clicar EXATAMENTE na borda externa (caía no `return dist ==
	# effective_range` genérico lá embaixo), quando na verdade qualquer célula
	# DENTRO do raio (ou do anel, se area_min_range > 0 — ver Eruption)
	# deveria confirmar igual, já que todo mundo no raio é atingido de
	# qualquer jeito, não só quem está na ponta.
	if effective_action is AttackData and effective_action.area_shape == "Burst":
		return dist <= effective_range and dist >= effective_action.area_min_range

	# Cone (ver AttackData.area_shape/get_cone_cells): a direção do leque é a
	# mesma direção 8-way de sempre (sign do delta, igual find_projectile_target/
	# resolve_confused_target) — target só é válido se REALMENTE cair dentro do
	# leque calculado naquela direção, não só "dentro do range" (uma célula tipo
	# delta=(2,1), fora de qualquer uma das 8 direções puras, nunca vai estar
	# DE VERDADE dentro do cone, mesmo com dist=2 <= range).
	if effective_action is AttackData and effective_action.area_shape == "Cone":
		var dir = Vector2i(sign(delta.x), sign(delta.y))
		return dist <= effective_range and target in get_cone_cells(origin, dir, effective_range)

	# Line (ver AttackData.area_shape/execute_attack_burst — Flamethrower):
	# mesma checagem de "linha reta" de is_projectile_like acima, mas SEM
	# exigir dist == range — clicar em QUALQUER célula ao longo do feixe
	# (mesmo espírito de Cone aceitar qualquer célula dentro do leque, não só
	# a ponta) já confirma o uso na direção certa; o alcance de verdade do
	# feixe é sempre o range inteiro do golpe, não a distância clicada (ver
	# comentário grande em execute_attack_burst).
	if effective_action is AttackData and effective_action.area_shape == "Line":
		var is_straight_line = delta.x == 0 or delta.y == 0 or abs(delta.x) == abs(delta.y)
		return is_straight_line and dist <= effective_range

	# Wide (ver AttackData.area_shape/get_wide_cells — Rock Slide): diferente
	# de Cone/Line, só EXATAMENTE 3 células contam (a fila fixa a `range`
	# passos de distância) — sem checagem de dist <= range separada, só
	# membership mesmo, já que get_wide_cells nunca devolve nada fora dessas
	# 3 células.
	if effective_action is AttackData and effective_action.area_shape == "Wide":
		var dir = Vector2i(sign(delta.x), sign(delta.y))
		return target in get_wide_cells(origin, dir, effective_range)

	return dist == effective_range

# Todas as células dentro de um "leque" (cone) que se abre a partir de
# `origin` na direção `dir` (8-way, sign(delta) — nunca Vector2i.ZERO) até
# `max_range` passos. O usuário confirmou (com screenshots rotulados
# célula por célula) que CARDEAL e DIAGONAL crescem de jeitos DIFERENTES —
# não dá pra usar uma fórmula só pras 8 direções:
#
# - CARDEAL (ex: Direita): largura 1, 3, 5... a cada passo de distância —
#   confirmado exato pra Direita a partir de (5,5), range 3: 9 células
#   (6,5)(7,5)(8,5)(7,4)(7,6)(8,3)(8,4)(8,6)(8,7). `forward` = a distância
#   NA direção mirada (dx*dir.x + dy*dir.y); `lateral` = o quanto está FORA
#   da direção (perpendicular, via o "produto cruzado" 2D
#   dx*(-dir.y) + dy*dir.x). Entra no leque se forward > 0 (à FRENTE) e
#   abs(lateral) < forward — é essa comparação que dá a largura 1/3/5,
#   crescendo 2 células por passo. Total de células = max_range².
#
# - DIAGONAL (ex: Baixo-Direita): largura 1, 2, 3... a cada passo —
#   crescendo só 1 célula por passo, BEM mais estreito que o cardeal no
#   mesmo range. Confirmado exato pra Baixo-Direita a partir de (0,0),
#   range 3: 6 células (1,1)(2,1)(3,1)(1,2)(2,2)(1,3) — sempre com AMBOS os
#   eixos avançando pelo menos 1 passo na direção certa (`along_x`/
#   `along_y` abaixo, cada um = a componente de dx/dy JÁ multiplicada pelo
#   sinal de dir naquele eixo — >= 1 significa "avançou de verdade nesse
#   eixo, no sentido certo"), e a SOMA dos dois avanços limitada a
#   max_range + 1 (não max_range — é o "+1" que dá a largura 1/2/3 em vez
#   de pular direto pro range errado). Total de células = max_range *
#   (max_range + 1) / 2 (número triangular) — cresce mais devagar que o
#   cardeal (max_range²) conforme o range aumenta.
func get_cone_cells(origin: Vector2i, dir: Vector2i, max_range: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if dir == Vector2i.ZERO:
		return cells
	var is_diagonal = dir.x != 0 and dir.y != 0
	for dx in range(-max_range, max_range + 1):
		for dy in range(-max_range, max_range + 1):
			if dx == 0 and dy == 0:
				continue
			if max(abs(dx), abs(dy)) > max_range:
				continue
			if is_diagonal:
				var along_x = dx * dir.x
				var along_y = dy * dir.y
				if along_x >= 1 and along_y >= 1 and along_x + along_y <= max_range + 1:
					cells.append(origin + Vector2i(dx, dy))
			else:
				var forward = dx * dir.x + dy * dir.y
				var lateral = dx * -dir.y + dy * dir.x
				if forward > 0 and abs(lateral) < forward:
					cells.append(origin + Vector2i(dx, dy))
	return cells

# Área "Wide" (ver AttackData.area_shape — Rock Slide é o primeiro caso):
# 3 células NUMA FILA SÓ, perpendicular a `dir`, todas centradas em
# origin + dir*range (não um leque que cresce com a distância feito
# get_cone_cells acima). O vetor perpendicular a `dir` é sempre a rotação de
# 90° dele (Vector2i(-dir.y, dir.x)) — funciona igual pra direção cardeal ou
# diagonal, sem precisar de um `if is_diagonal` separado feito Cone (a
# assimetria cardeal/diagonal aqui é só uma CONSEQUÊNCIA natural da rotação
# de 90°, não precisa de fórmula própria pra cada caso). Exemplo confirmado
# pelo usuário: origin=(1,1), dir=(1,0) [direita], range=1 -> center=(2,1),
# perp=(0,1) -> células (2,0), (2,1), (2,2).
func get_wide_cells(origin: Vector2i, dir: Vector2i, range_value: int) -> Array[Vector2i]:
	if dir == Vector2i.ZERO:
		return []
	var center = origin + dir * range_value
	var perp = Vector2i(-dir.y, dir.x)
	return [center - perp, center, center + perp]

# Anda em linha reta de origin em direção a target (mesma direção 8-way do
# resto do jogo), célula por célula, até no máximo max_range passos, e
# devolve o primeiro INIMIGO encontrado no caminho (ou null se não achar
# nenhum). Para numa parede/borda do mapa (is_wall_or_border) igual
# find_ball_target — bug reportado pelo usuário: Powder Snow (e qualquer
# outro ataque-projétil) estava atravessando paredes por essa checagem não
# existir aqui antes. Aliados no meio do caminho continuam sendo ignorados
# (o projétil passa direto por eles em vez de ser bloqueado — simplificação:
# dá pra mudar isso depois se quisermos que aliados também bloqueiem).
func find_projectile_target(attacker: Node, origin: Vector2i, target: Vector2i, max_range: int) -> Node:
	var delta = target - origin
	var dir = Vector2i(sign(delta.x), sign(delta.y))
	var cell = origin
	for step in max_range:
		var next_cell = cell + dir
		if is_wall_or_border(next_cell):
			break
		cell = next_cell
		var u = get_unit_at(cell)
		if u != null and u.is_enemy != attacker.is_enemy:
			return u
	return null

# Variante de find_projectile_target() usada só por Ball (ver
# execute_ball_throw): mesma parada em parede/borda, só que devolve também
# stop_cell (a última célula andável alcançada) — usada por execute_ball_throw
# pra saber até onde animar o voo da bola mesmo quando ela erra. Ataque-
# projétil comum não precisa de stop_cell porque, ao errar (defender == null),
# execute_attack simplesmente não anima o projétil nenhum (ver comentário lá).
func find_ball_target(attacker: Node, origin: Vector2i, target: Vector2i, max_range: int) -> Dictionary:
	var delta = target - origin
	var dir = Vector2i(sign(delta.x), sign(delta.y))
	var cell = origin
	var stop_cell = origin
	for step in max_range:
		var next_cell = cell + dir
		if is_wall_or_border(next_cell):
			break
		cell = next_cell
		stop_cell = cell
		var u = get_unit_at(cell)
		if u != null and u.is_enemy != attacker.is_enemy:
			return {"unit": u, "stop_cell": stop_cell}
	return {"unit": null, "stop_cell": stop_cell}

# Recalcula o highlight vermelho a partir da posição atual do mouse — chamado
# a cada movimento do mouse enquanto targeting_action != null. Só destaca a
# célula sob o cursor, e só se ela estiver dentro do alcance da ação E dentro
# do grid jogável; fora disso, não mostra nada (não "gruda" no limite). Junto
# com o highlight, a unidade vira no próprio eixo pra encarar o tile mirado.
func update_attack_highlight() -> void:
	attack_highlight_layer.clear()
	var current = get_current_unit()
	if current == null or targeting_action == null:
		return

	var cell = tilemap.local_to_map(tilemap.to_local(get_global_mouse_position()))
	if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
		return
	if not is_valid_target_cell(current.grid_pos, cell, targeting_action, current):
		return

	# `attack`: o AttackData de verdade por trás da ação mirada — direto se
	# `targeting_action` já É um AttackData, ou o tm_attack de dentro se for
	# um ItemData de TM (mesmo desvio que is_valid_target_cell já faz pra
	# `effective_action`, ver comentário lá).
	var attack: AttackData = null
	if targeting_action is AttackData:
		attack = targeting_action
	elif targeting_action is ItemData and targeting_action.category == "TM":
		attack = targeting_action.tm_attack

	if is_self_target_status(attack):
		# Defense Curl/Growth/Synthesis e afins (ver is_self_target_status):
		# quem é afetado de verdade é QUEM ATACA, não a célula clicada —
		# destaca só o PRÓPRIO tile de quem ataca, sem seguir o mouse
		# (ainda precisa clicar uma célula válida pra confirmar — agora só o
		# próprio tile mesmo, "range 0", ver is_valid_target_cell acima).
		attack_highlight_layer.set_cell(current.grid_pos, 0, Vector2i(13, 1))
	elif attack != null and attack.sets_weather != "":
		# Clima (ver AttackData.sets_weather/is_valid_target_cell acima) —
		# pedido do usuário: "Weather moves confirmation indicator should be
		# entire battlefield". Não depende de direção nenhuma, então destaca
		# TODO o grid jogável de uma vez, sem seguir o mouse.
		for x in MAP_WIDTH:
			for y in MAP_HEIGHT:
				attack_highlight_layer.set_cell(Vector2i(x, y), 0, Vector2i(13, 1))
	elif attack != null and attack.area_shape == "Team":
		# Tailwind é o primeiro caso — pedido do usuário: "Tailwind highlight
		# should be all allies". Destaca só quem está do MESMO lado de quem usa
		# (incluindo quem usa), igual o alvo de verdade em execute_status_
		# attack (ver o ramo area_shape=="Team" lá).
		for u in player_units + enemy_units:
			if u.is_enemy == current.is_enemy:
				attack_highlight_layer.set_cell(u.grid_pos, 0, Vector2i(13, 1))
	elif attack != null and attack.area_shape == "Cone":
		# Cone: destaca o LEQUE inteiro (não só a célula sob o mouse) — comunica
		# de verdade que esse ataque cobre uma área, não só 1 tile (ver
		# AttackData.area_shape/get_cone_cells).
		var dir = Vector2i(sign(cell.x - current.grid_pos.x), sign(cell.y - current.grid_pos.y))
		for cone_cell in get_cone_cells(current.grid_pos, dir, attack.range):
			attack_highlight_layer.set_cell(cone_cell, 0, Vector2i(13, 1))
	elif attack != null and attack.area_shape == "Burst":
		# Burst: destaca TODO o raio ao redor de quem ataca (ou o ANEL, se
		# area_min_range > 0 — ver Eruption), igual mesma geometria de
		# execute_attack_burst — não depende de direção nenhuma, então não
		# segue o mouse (qualquer célula válida pra clicar mostra o mesmo
		# destaque cheio).
		for dx in range(-attack.range, attack.range + 1):
			for dy in range(-attack.range, attack.range + 1):
				if dx == 0 and dy == 0:
					continue
				var burst_dist = max(abs(dx), abs(dy))
				if burst_dist > attack.range or burst_dist < attack.area_min_range:
					continue
				var burst_cell = current.grid_pos + Vector2i(dx, dy)
				if burst_cell.x < 0 or burst_cell.x >= MAP_WIDTH or burst_cell.y < 0 or burst_cell.y >= MAP_HEIGHT:
					continue
				attack_highlight_layer.set_cell(burst_cell, 0, Vector2i(13, 1))
	elif attack != null and attack.area_shape == "Line":
		# Line: destaca o feixe inteiro na direção mirada, célula por célula,
		# parando em parede/borda — mesma geometria de execute_attack_burst.
		var dir = Vector2i(sign(cell.x - current.grid_pos.x), sign(cell.y - current.grid_pos.y))
		var line_cell = current.grid_pos
		for step in attack.range:
			var next_cell = line_cell + dir
			if is_wall_or_border(next_cell):
				break
			line_cell = next_cell
			attack_highlight_layer.set_cell(line_cell, 0, Vector2i(13, 1))
	elif attack != null and attack.area_shape == "Wide":
		# Wide: destaca as 3 células da fila inteira (não só a célula sob o
		# mouse) na direção mirada — mesma geometria de get_wide_cells.
		var dir = Vector2i(sign(cell.x - current.grid_pos.x), sign(cell.y - current.grid_pos.y))
		for wide_cell in get_wide_cells(current.grid_pos, dir, attack.range):
			if wide_cell.x < 0 or wide_cell.x >= MAP_WIDTH or wide_cell.y < 0 or wide_cell.y >= MAP_HEIGHT:
				continue
			attack_highlight_layer.set_cell(wide_cell, 0, Vector2i(13, 1))
	else:
		attack_highlight_layer.set_cell(cell, 0, Vector2i(13, 1))
	current.face_towards(cell)

# Clique enquanto mirando: se a célula clicada está dentro do alcance,
# resolve o alvo de verdade (a própria célula clicada pra ataque normal; o
# primeiro inimigo na linha, pra projétil — pode ser mais perto do que onde
# clicou) e executa o ataque se houver um inimigo válido ali. Clicar fora do
# alcance, sem alvo, ou só em aliados no caminho, cancela a mira sem efeito.
# De qualquer forma, um clique sempre sai do modo de mira.
func handle_targeting_input(clicked_cell: Vector2i) -> void:
	var current = get_current_unit()
	var action = targeting_action
	var index = targeting_slot_index
	if current != null and action is AttackData and action.is_status and current.attacks_remaining > 0 and is_valid_target_cell(current.grid_pos, clicked_cell, action):
		# Ataque de Status (ver AttackData.is_status/execute_status_attack): não
		# mira UM inimigo, mira uma DIREÇÃO — quem de fato é atingido só é
		# resolvido lá dentro (get_cone_cells/area_cells), então aqui só precisa
		# calcular `dir` a partir de onde o jogador clicou, mesma convenção
		# 8-way (sign do delta) do resto do jogo. Sem tratamento de Confused
		# especial: uma unidade confusa ainda mira a direção certa (só o alvo de
		# um ataque comum, mirado em 1 inimigo, é embaralhado — não faz muito
		# sentido "embaralhar direção" pra quem já é uma área inteira).
		var dir = Vector2i(sign(clicked_cell.x - current.grid_pos.x), sign(clicked_cell.y - current.grid_pos.y))
		_run_player_status_attack(current, action, dir, index)
	elif current != null and action is AttackData and (action.area_shape == "Burst" or action.area_shape == "Line" or action.area_shape == "Cone" or action.area_shape == "Wide") and current.attacks_remaining > 0 and is_valid_target_cell(current.grid_pos, clicked_cell, action):
		# Ataque de área "Burst", "Line" ou "Cone" QUE CAUSA DANO (ver
		# AttackData.area_shape/execute_attack_burst — Lava Plume,
		# Flamethrower e Overheat): mesmo raciocínio do ramo is_status logo
		# acima, o clique só CONFIRMA (precisa cair numa célula válida pro
		# golpe), quem é atingido de verdade é resolvido lá dentro (todo
		# mundo, aliado ou inimigo — ao redor de quem atacou pra Burst, ao
		# longo do feixe pra Line, no leque pra Cone) — por isso vem ANTES do
		# ramo de dano de 1 alvo só logo abaixo, senão cairia lá e exigiria
		# um inimigo bem em cima da célula clicada, coisa que nenhum dos três
		# precisa.
		var dir = Vector2i(sign(clicked_cell.x - current.grid_pos.x), sign(clicked_cell.y - current.grid_pos.y))
		_run_player_burst_attack(current, action, dir, index)
	elif current != null and action is AttackData and current.attacks_remaining > 0 and is_valid_target_cell(current.grid_pos, clicked_cell, action, current):
		var target: Node = null
		if action.is_projectile:
			# get_effective_attack_range() em vez de action.range direto: pra
			# quase todo ataque devolve a mesma coisa, mas pra golpes com
			# AttackData.scales_with_consecutive_use o alcance de VERDADE
			# depende de estado da unidade — action.range aqui é só o teto
			# teórico (usado por is_valid_target_cell pra decidir se o clique
			# é aceitável).
			target = find_projectile_target(current, current.grid_pos, clicked_cell, get_effective_attack_range(current, action))
		else:
			# Não-projétil (ex: Tackle, Quick Attack, Rollout): exige um
			# inimigo bem em cima da célula clicada — is_valid_target_cell já
			# garantiu acima que essa célula está na distância EXATA certa
			# (agora passando `current`, então pra Rollout já é o alcance
			# dinâmico de verdade, não o teto estático — ver comentário
			# grande em is_valid_target_cell).
			var clicked_unit = get_unit_at(clicked_cell)
			if clicked_unit != null and clicked_unit.is_enemy != current.is_enemy:
				target = clicked_unit
		if target != null:
			# Confused: pedido do usuário (2026-07-22) — "always attack a
			# random direction. (1/8 chance to attack the correct one,
			# still checks out)". Antes disso era um sorteio de 1/6 pra
			# decidir SE a mira embaralhava; agora SEMPRE embaralha
			# enquanto Confused estiver ativo, sem chance nenhuma aqui —
			# resolve_confused_target() já sorteia 1 das 8 direções (ver
			# lá), então por conta própria já dá ~1/8 de chance de calhar
			# de sortear a direção certa e acertar o alvo ORIGINAL de
			# qualquer jeito ("still checks out"), sem precisar de
			# nenhuma checagem extra aqui. O alvo MIRADO (target) só
			# decide se o ataque é disparado ou não — quem de fato é
			# atingido, com a mira embaralhada, pode ser um aliado,
			# ninguém, ou (por sorte) o próprio alvo original de novo.
			var actual_target = target
			if current.has_status("Confused"):
				actual_target = resolve_confused_target(current, action)
			_run_player_attack(current, actual_target, action, index)
	elif current != null and action is ItemData and action.category == "TM" and action.tm_attack != null and action.tm_attack.is_status and current.attacks_remaining > 0 and is_valid_target_cell(current.grid_pos, clicked_cell, action):
		# Gêmeo do primeiro ramo (AttackData.is_status) lá em cima, só que
		# pra um TM que ensina um ataque de Status (ver ItemData.tm_attack)
		# — TM 11/Sunny Day é o primeiro caso. Precisa vir ANTES do ramo de
		# TM comum logo abaixo (mesma ordem "is_status primeiro" do topo
		# desta função): sem isso, um TM de Status cairia no ramo de baixo,
		# que exige achar um INIMIGO na célula clicada antes de disparar —
		# Sunny Day nunca mira ninguém de verdade (ver AttackData.
		# sets_weather), então nunca acharia um "target" e o TM nunca
		# dispararia (nem gastaria carga, nem faria nada, sem aviso nenhum).
		var dir = Vector2i(sign(clicked_cell.x - current.grid_pos.x), sign(clicked_cell.y - current.grid_pos.y))
		_run_player_tm_status_attack(current, action, dir, index)
	elif current != null and action is ItemData and action.category == "TM" and action.tm_attack != null and current.attacks_remaining > 0 and is_valid_target_cell(current.grid_pos, clicked_cell, action):
		# Mesma lógica de resolução de alvo do ramo AttackData acima, só que
		# em cima de action.tm_attack (que TEM is_projectile/range de
		# verdade — a ItemData em si não). Confused TAMBÉM vale aqui,
		# diferente de Ball: usar um TM é a unidade executando um ataque de
		# verdade (Ice Fang), não o treinador agindo por conta própria.
		var tm_attack: AttackData = action.tm_attack
		var target: Node = null
		if tm_attack.is_projectile:
			target = find_projectile_target(current, current.grid_pos, clicked_cell, tm_attack.range)
		else:
			var clicked_unit = get_unit_at(clicked_cell)
			if clicked_unit != null and clicked_unit.is_enemy != current.is_enemy:
				target = clicked_unit
		if target != null:
			# Mesma regra "sempre embaralha" de cima (ver comentário grande
			# no ramo de AttackData comum) — sem chance nenhuma aqui, quem
			# decide se acerta o alvo certo por acaso é resolve_confused_
			# target() sozinha.
			var actual_target = target
			if current.has_status("Confused"):
				actual_target = resolve_confused_target(current, tm_attack)
			_run_player_tm_attack(current, actual_target, action, index)
	elif current != null and action is ItemData and action.category == "Ball" and current.attacks_remaining > 0 and is_valid_target_cell(current.grid_pos, clicked_cell, action):
		# Ball não sofre a mesma checagem de Confused que Ataque sofre acima
		# — de propósito: quem mira e arremessa a bola é o TREINADOR, não a
		# unidade em campo, então o "erro de mira" de Confused (que afeta a
		# unidade, não o jogador) não deveria valer aqui.
		_run_player_ball_throw(current, clicked_cell, action, index)
	cancel_targeting()

# Sorteia uma das 8 direções (a "direção errada" da confusão) e devolve quem
# estiver nela dentro do alcance da ação — SEM o filtro de "só inimigo" que
# find_projectile_target tem, de propósito: uma unidade confusa "deve ser
# capaz de atingir seus aliados". Pode devolver null (nenhuma das 8 direções
# tinha alguém) — nesse caso o ataque é disparado mesmo assim, só não acerta
# ninguém (ver execute_attack aceitando defender nulo).
#
# Ataque-projétil varre a linha inteira (primeira unidade que achar, igual
# find_projectile_target); ataque comum (melee) só olha a distância EXATA de
# action.range naquela direção — mesma convenção de is_valid_target_cell.
func resolve_confused_target(attacker: Node, action: ActionData) -> Node:
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
	]
	directions.shuffle()
	for dir in directions:
		if action is AttackData and action.is_projectile:
			var cell = attacker.grid_pos
			for step in action.range:
				var next_cell = cell + dir
				if is_wall_or_border(next_cell):
					break
				cell = next_cell
				var u = get_unit_at(cell)
				if u != null:
					return u
		else:
			var u = get_unit_at(attacker.grid_pos + dir * action.range)
			if u != null:
				return u
	return null

# Fórmula de dano (estilo Pokémon):
#   (((2*Nível/5 + 2) * Poder * Ataque/Defesa) / 50 + 2) * Modificadores
# Se o ataque for Especial, usa Ataque/Defesa Especial em vez dos normais.
# Modificadores por enquanto é efetividade de tipo (TypeChart), STAB (mesmo
# tipo do ataque e da unidade, x1.5), Habilidade tipo Blaze (ver
# calculate_damage_modifiers) e Acerto Crítico (x1.5, ver is_critical
# abaixo/CRITICAL_HIT_CHANCE) — aleatoriedade de dano (variação ±15%, como no
# jogo original) ainda não existe.
# Todas as divisões truncam (mesma convenção do resto do projeto): a parte
# de dentro trunca primeiro, DEPOIS multiplica pelos modificadores e trunca
# de novo — igual o jogo original faz (não dá pra multiplicar os
# modificadores antes de truncar a base, senão o resultado muda). Piso de 1
# de dano no final — EXCETO se a efetividade de tipo for x0 (imune), aí o
# dano é 0 mesmo (não faz sentido ter um "mínimo de 1" contra imunidade).
#
# is_critical vem PRONTO de quem chama (ver execute_attack, que rola
# CRITICAL_HIT_CHANCE uma vez só) em vez de rolar aqui dentro — assim quem
# chama pode logar "A critical hit!" usando o MESMO resultado do roll que
# decidiu o dano, sem sortear duas vezes (e sem dessincronizar as duas
# coisas). Chamadas que só querem ESTIMAR dano (ex: IA escolhendo o melhor
# alvo, ver choose_enemy_action) deixam is_critical no padrão (false) de
# propósito — uma avaliação de "qual alvo é melhor" não deve depender de
# sorte, sempre o mesmo resultado pro mesmo estado de jogo.
# ---------- Clima (Weather) x Dano ----------
# Strong Winds (pedido do usuário, com o exemplo do Skarmory): um ataque cujo
# tipo SERIA super efetivo contra um Pokémon puramente Flying (ex: Rock,
# Electric, Ice — qualquer tipo com multiplicador > 1.0 contra "Flying" na
# TypeChart) tem sua efetividade FINAL (já combinando todos os tipos do
# defensor, não só o "Flying" isolado) travada em 0.5x — não é "multiplica
# por 0.5", é "vira 0.5x", mesmo que a conta normal desse outro valor. É
# assim que o exemplo do usuário funciona: Rock em Skarmory (Steel/Flying)
# seria NEUTRO de qualquer jeito (2.0 de Flying x 0.5 de Steel = 1.0), mas em
# Strong Winds vira 0.5x mesmo assim, porque Rock "seria" super efetivo num
# Flying puro. Chamado no lugar de TypeChart.get_effectiveness() direto em
# TODO lugar que precisar da efetividade combinada de um ataque (dano E a
# mensagem "super effective"/"not very effective" — ver os dois usos abaixo).
func get_weather_adjusted_effectiveness(attack_element: String, defender: Node) -> float:
	var effectiveness = TypeChart.get_effectiveness(attack_element, defender.data.types)
	if current_weather == WEATHER_STRONG_WINDS and defender.data.types.has("Flying"):
		if TypeChart.get_multiplier(attack_element, "Flying") > 1.0:
			return 0.5
	return effectiveness

# Sandstorm: Rock ganha x1.5 de Special Defense. Snow: Ice ganha x1.5 de
# Defense (pedido do usuário). Os dois são bônus de CLIMA, não Altered Stats
# (stat_stages) — por isso entram como multiplicador direto em cima do stat
# já efetivo (ver calculate_damage), não como mais um estágio, e por isso
# valem MESMO num golpe crítico (crítico só ignora estágio desfavorável do
# defensor — ver Unit.get_defensive_stat_for_crit — nunca um bônus de clima).
func get_weather_defense_multiplier(def_key: String, defender: Node) -> float:
	if current_weather == WEATHER_SANDSTORM and def_key == "special_defense" and defender.data.types.has("Rock"):
		return 1.5
	if current_weather == WEATHER_SNOW and def_key == "defense" and defender.data.types.has("Ice"):
		return 1.5
	return 1.0

# Ver comentário grande no ponto de chamada (execute_attack, logo antes do
# roll de accuracy normal) — Water sempre falha em Harsh Sunlight, Fire
# sempre falha em Heavy Rain.
func _weather_blocks_attack(attack: AttackData) -> bool:
	if current_weather == WEATHER_HARSH_SUNLIGHT and attack.element_type == "Water":
		return true
	if current_weather == WEATHER_HEAVY_RAIN and attack.element_type == "Fire":
		return true
	return false

func calculate_damage(attacker: Node, defender: Node, attack: AttackData, is_critical: bool = false) -> int:
	var effectiveness = get_weather_adjusted_effectiveness(attack.element_type, defender)
	if effectiveness == 0.0:
		return 0

	if has_type_immunity_ability(defender, attack.element_type):
		return 0

	# get_effective_stat() em vez do stat cru: já aplica o estágio alterado
	# (Altered Stats, ver Unit.STAGE_STATS) — com todo mundo em estágio 0
	# (padrão), o resultado é idêntico ao stat cru de antes. Num crítico, os
	# estágios DESFAVORÁVEIS pro atacante são ignorados (ver Unit.
	# get_offensive_stat_for_crit/get_defensive_stat_for_crit e o comentário
	# grande lá): Attack/Sp.Atk rebaixado do atacante não conta, nem Defense/
	# Sp.Def aumentada do defensor.
	var atk_key = "special_attack" if attack.is_special else "attack"
	var def_key = "special_defense" if attack.is_special else "defense"
	var atk_stat: int
	var def_stat: int
	if is_critical:
		atk_stat = attacker.get_offensive_stat_for_crit(atk_key)
		def_stat = defender.get_defensive_stat_for_crit(def_key)
	else:
		atk_stat = attacker.get_effective_stat(atk_key)
		def_stat = defender.get_effective_stat(def_key)
	def_stat = int(round(def_stat * get_weather_defense_multiplier(def_key, defender)))

	@warning_ignore("integer_division")
	var level_factor = (2 * attacker.level) / 5 + 2

	# attack.power direto pra quase todo ataque — get_effective_power() só
	# desvia disso pra ataques com scales_with_consecutive_use=true (ver
	# comentário grande lá — Rollout é o primeiro caso).
	@warning_ignore("integer_division")
	var damage = (level_factor * get_effective_power(attacker, attack, defender) * atk_stat / def_stat) / 50 + 2

	var modifiers = calculate_damage_modifiers(attacker, defender, attack) * effectiveness
	# Tinted Lens (ver AbilityData.tinted_lens, pedido do usuário, 2026-07-23,
	# Butterfree Hidden: "Doubles the damage on not very effective moves
	# used") — só quando a efetividade combinada é "não muito eficaz" de
	# verdade (entre 0 exclusivo e 1.0 exclusivo). effectiveness == 0.0
	# (imunidade total) fica de fora de propósito: dobrar 0 continua 0, não faz
	# sentido gastar o bônus nesse caso.
	if effectiveness > 0.0 and effectiveness < 1.0 and has_tinted_lens(attacker):
		modifiers *= TINTED_LENS_MULTIPLIER
	if is_critical:
		modifiers *= CRITICAL_HIT_MULTIPLIER
		# Sniper (ver AbilityData.sniper, pedido do usuário, 2026-07-24,
		# Beedrill Hidden: "Critical hits landed are 2x multiplier instead of
		# 1.5x (easier to just make crits x4/3)") — multiplica o resultado
		# JÁ COM o x1.5 padrão por mais 4/3, dando exatamente 2.0 no final
		# (1.5 * 4/3 = 2.0), em vez de um valor fixo separado competindo com
		# CRITICAL_HIT_MULTIPLIER.
		if has_sniper(attacker):
			modifiers *= SNIPER_CRIT_MULTIPLIER
	damage = int(damage * modifiers)

	return max(1, damage)

# 1/16 = 6.25% — mesma fração clássica de acerto crítico dos jogos Pokémon
# (sem nenhum item que aumente a chance implementado ainda; se um dia existir
# um "Scope Lens" ou parecido, é aqui que ele multiplicaria).
const CRITICAL_HIT_CHANCE = 0.0625
const CRITICAL_HIT_MULTIPLIER = 1.5

# Ver AbilityData.sniper — 4/3 EXATO (não um multiplicador "fofo"), porque o
# pedido do usuário foi literal: "1.5x -> 2x", e 1.5 * (4/3) = 2.0 sem erro de
# arredondamento (4/3 period bate exato com float de qualquer jeito, já que
# GDScript usa double de 64 bits — a imprecisão de ponto flutuante aqui é
# desprezível pra fins de dano inteiro truncado).
const SNIPER_CRIT_MULTIPLIER = 4.0 / 3.0

func has_sniper(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.sniper:
			return true
	return false

# Pin Missile (ver AttackData.is_multi_hit, pedido do usuário, Beedrill:
# "randomly decide if they will fire 2 (37.5%), 3 (37.5%), 4 (12.5%) or 5
# (12.5%) times") — pesos EXATOS do pedido, somam 1.0 (0.375+0.375+0.125+0.125).
const MULTI_HIT_WEIGHTS := {2: 0.375, 3: 0.375, 4: 0.125, 5: 0.125}

# Sorteia quantas vezes um golpe multi-hit conecta, seguindo MULTI_HIT_WEIGHTS
# acima — soma cumulativa simples (2 primeiro, depois 3, 4, 5), já que a ORDEM
# das chaves do dicionário em GDScript é a ordem de inserção (garantida desde
# o Godot 4), então iterar `MULTI_HIT_WEIGHTS.keys()` dá sempre [2, 3, 4, 5].
func _roll_multi_hit_count() -> int:
	var roll = randf()
	var cumulative = 0.0
	for count in MULTI_HIT_WEIGHTS.keys():
		cumulative += MULTI_HIT_WEIGHTS[count]
		if roll < cumulative:
			return count
	return 5

# Resolve um golpe multi-hit (ver AttackData.is_multi_hit) inteiro: sorteia
# quantas vezes ele conecta (_roll_multi_hit_count) e repete a animação de
# hurt + efeito de impacto + roll de crítico + cálculo de dano UMA VEZ PRA
# CADA acerto — "Treat each one as a different attack" (pedido do usuário).
# Pedido do usuário (2026-07-24, correção depois do primeiro build): "Pin
# missile is only hitting 1 time, I think it stops shooting after killing a
# target, it should keep going" — DIFERENTE da série principal (que corta a
# rajada assim que o alvo desmaia no meio dela), aqui a rajada SEMPRE resolve
# os N acertos sorteados por _roll_multi_hit_count, mesmo que o alvo já
# tenha desmaiado num acerto anterior (acertos "de sobra" continuam
# acontecendo, só não tiram HP de quem já está com 0 — ver max(...,0) no
# hp_lost de cada rodada, pra não contar dano negativo no total). Retorna o
# total de HP realmente perdido pelo alvo (soma de cada acerto, já limitado
# pelo HP restante em cada rodada) — é isso que execute_attack usa como
# `hp_lost` pro recoil (ver comentário grande lá sobre por que hp_lost !=
# damage bruto).
#
# NÃO chama defender.face_towards/cure Asleep/toca "não teve efeito"/aplica
# efeito secundário/Bug Bite/checa morte — tudo isso continua acontecendo UMA
# vez só, em execute_attack, depois que esta função retorna (mesmo formato de
# sempre, só o "meio" da função — dano em si — que se repete).
func _resolve_multi_hit_damage(attacker: Node, defender: Node, attack: AttackData) -> int:
	var hit_count = _roll_multi_hit_count()
	var total_hp_lost = 0
	for i in range(hit_count):
		if i > 0:
			# O primeiro "hurt"/impacto já foi tocado por execute_attack antes
			# de chamar esta função (ver ali) — a partir do 2º acerto, cada
			# rodada toca a própria reação visual. play_hurt_animation() num
			# alvo já desmaiado simplesmente não anima nada de novo (ver
			# comentário de Unit._play_anim sobre estados que travam
			# animação) — seguro de chamar mesmo depois do alvo ter morrido
			# num acerto anterior.
			defender.play_hurt_animation()
			if attack.impact_texture != null or attack.impact_texture_2 != null or not attack.impact_frames.is_empty():
				play_impact_effect(attack.impact_texture, defender.position, attack.impact_texture_2, attack.impact_frames)
		var is_critical = randf() < get_effective_crit_chance(attack, attacker)
		var damage = calculate_damage(attacker, defender, attack, is_critical)
		var hp_lost = min(damage, max(defender.hp_current, 0))
		defender.take_damage(damage)
		total_hp_lost += hp_lost
		if is_critical:
			log_message("A critical hit!")
	log_message("Hit %d time(s)!" % hit_count)
	return total_hp_lost

# Chance de Acerto Crítico de VERDADE a usar no roll (ver AttackData.
# crit_chance_override) — CRITICAL_HIT_CHANCE global, A NÃO SER que o golpe
# tenha um valor próprio (>= 0.0) marcado, caso em que esse valor substitui
# o global por completo (não multiplica, SUBSTITUI). Razor Leaf é o primeiro
# caso, ver comentário grande do campo em attack_data.gd. `attacker` opcional
# (null = compatível com qualquer call site de antes deste parâmetro existir)
# — só usado pra checar Focus Energy (ver Unit.status_conditions/data/attacks/
# focus_energy.tres, pedido do usuário, Beedrill: "Doubles critical hit chance
# for 4 turns"), que DOBRA o resultado por cima (multiplica, não substitui —
# diferente de crit_chance_override, os dois efeitos compõem juntos se um
# golpe raro tiver os dois algum dia).
func get_effective_crit_chance(attack: AttackData, attacker: Node = null) -> float:
	var chance = CRITICAL_HIT_CHANCE
	if attack.crit_chance_override >= 0.0:
		chance = attack.crit_chance_override
	if attacker != null and attacker.has_status("Focus Energy"):
		chance *= 2.0
	return chance

# A parte "Modificadores" da fórmula acima que NÃO é efetividade de tipo
# (essa fica separada em calculate_damage, por causa do caso especial de
# imunidade x0 — ver comentário lá).
# - STAB ("Same Type Attack Bonus"): se o tipo do ataque é um dos tipos da
#   própria unidade (UnitData.types), dano x1.5 — vale pra QUALQUER ataque
#   que cause dano, não depende de Habilidade nenhuma.
# - Habilidade (AbilityData): percorre os slots equipados procurando
#   Habilidades cujo element_type bate com o do ataque E cuja condição de HP
#   (hp_current/hp_max < hp_threshold) está satisfeita, multiplicando um por
#   um — dá pra ter mais de uma Habilidade ativa ao mesmo tempo, mesmo que
#   hoje nenhuma unidade tenha isso. Blaze é a primeira: Fire, hp_threshold
#   0.25, damage_multiplier 1.3 (data/abilities/blaze.tres).
# Imunidade TOTAL de tipo vinda de uma Habilidade de QUEM DEFENDE (ex:
# Levitate x Ground) — separada da imunidade da TypeChart (baseada só no
# tipo da unidade) porque essa depende do loadout equipado, não é fixa da
# espécie. Chamada antes do resto da fórmula em calculate_damage(), pelo
# mesmo motivo: bypassa o piso de dano mínimo de 1.
func has_type_immunity_ability(defender: Node, element_type: String) -> bool:
	if element_type == "":
		return false
	for action in defender.data.slots:
		if action is AbilityData and action.immune_type == element_type:
			return true
	return false

func calculate_damage_modifiers(attacker: Node, defender: Node, attack: AttackData) -> float:
	var modifiers = 1.0

	# Sunny/Harsh Sunlight: Fire x1.5, Water x0.5. Rain/Heavy Rain: o
	# oposto. O "Water sempre falha em Harsh Sunlight"/"Fire sempre falha em
	# Heavy Rain" NÃO mora aqui — vira um golpe que erra de propósito (ver
	# _weather_blocks_attack() em execute_attack), então nem chega a rolar
	# dano pra multiplicar por nada.
	match attack.element_type:
		"Fire":
			if current_weather == WEATHER_SUNNY or current_weather == WEATHER_HARSH_SUNLIGHT:
				modifiers *= 1.5
			elif current_weather == WEATHER_RAIN or current_weather == WEATHER_HEAVY_RAIN:
				modifiers *= 0.5
		"Water":
			if current_weather == WEATHER_RAIN or current_weather == WEATHER_HEAVY_RAIN:
				modifiers *= 1.5
			elif current_weather == WEATHER_SUNNY or current_weather == WEATHER_HARSH_SUNLIGHT:
				modifiers *= 0.5

	if attacker.data.types.has(attack.element_type):
		modifiers *= 1.5

	# Burned: só ataques FÍSICOS de quem está queimado recebem o x0.5 (não
	# afeta ataques especiais nem o dano que essa unidade RECEBE).
	if attacker.has_status("Burned") and not attack.is_special:
		modifiers *= 0.5

	# Held Items com ItemData.physical_damage_multiplier (ex: Muscleband,
	# 1.1) — mesma restrição "só Físico" do Burned acima, mesmo padrão de
	# iteração de attacker.data.slots que Unit.get_accuracy_multiplier() já
	# usa pro multiplicador de precisão (ver comentário lá). Default 1.0 em
	# qualquer ItemData sem esse campo preenchido, então isso nunca afeta
	# quem não está carregando um item com esse efeito.
	if not attack.is_special:
		for action in attacker.data.slots:
			if action is ItemData:
				modifiers *= action.physical_damage_multiplier

	if attacker.hp_max > 0:
		var hp_ratio = float(attacker.hp_current) / float(attacker.hp_max)
		for action in attacker.data.slots:
			if action is AbilityData and action.element_type == attack.element_type and hp_ratio < action.hp_threshold:
				modifiers *= action.damage_multiplier

	# Flash Fire "Charged" (ver Unit.status_conditions/AbilityData.flash_fire
	# — virou uma Status Condition genérica em vez do bool flash_fire_armed
	# de antes, pedido do usuário: "this may unbloat attack logic") — só LÊ o
	# estado aqui, nunca cura (esta função também é chamada em previews/
	# decisão de IA fora de um ataque de verdade acontecendo, ver outras
	# chamadas de calculate_damage() em battle.gd) — quem consome de
	# verdade é execute_attack/execute_attack_burst, depois que o dano REAL
	# já foi calculado e aplicado (ver comentário lá).
	if attack.element_type == "Fire" and attacker.has_status("Charged") and has_flash_fire(attacker):
		modifiers *= FLASH_FIRE_MULTIPLIER

	# Sheer Force: só se o golpe TEM efeito secundário nenhum pra trocar (ver
	# AbilityData.sheer_force) — o efeito em si é cancelado à parte, em
	# execute_attack() (ver has_sheer_force ali), não aqui.
	if attack_has_secondary_effect(attack) and has_sheer_force(attacker):
		modifiers *= SHEER_FORCE_MULTIPLIER

	# Thick Fat e afins (ver AbilityData.resist_types/resist_multiplier): do
	# lado de QUEM DEFENDE, não de quem ataca — reduz (não zera, diferente de
	# immune_type/has_type_immunity_ability) o dano recebido de certos tipos,
	# sempre ativo (sem condição de HP nenhuma, diferente do bloco de
	# element_type/hp_threshold acima).
	for action in defender.data.slots:
		if action is AbilityData and action.resist_types.has(attack.element_type):
			modifiers *= action.resist_multiplier

	# Technician (ver AbilityData.technician, pedido do usuário, Breloom: "If
	# the base power of a move is less than or equal 60, multiply it by
	# x1,5") — usa get_effective_power() (não attack.power cru) pra golpes que
	# escalam (Rollout/Eruption/etc) serem julgados pelo poder REAL deste uso.
	if has_technician(attacker) and get_effective_power(attacker, attack, defender) <= TECHNICIAN_POWER_THRESHOLD:
		modifiers *= TECHNICIAN_MULTIPLIER

	return modifiers

# 1.3 = 30% a mais, valor fixo da Habilidade (não configurável por instância
# — diferente de AbilityData.damage_multiplier, que É por instância, porque
# Blaze/Torrent podem um dia ter valores diferentes entre si; Sheer Force é
# sempre 30%, então isso mora aqui como constante da REGRA, não do dado).
const SHEER_FORCE_MULTIPLIER = 1.3

# true se o attacker carrega uma Habilidade com sheer_force=true equipada
# (ver AbilityData.sheer_force) — usado tanto pra o bônus de dano
# (calculate_damage_modifiers) quanto pra cancelar o efeito secundário de
# verdade (ver execute_attack).
func has_sheer_force(attacker: Node) -> bool:
	for action in attacker.data.slots:
		if action is AbilityData and action.sheer_force:
			return true
	return false

# true se `u` carrega uma Habilidade com speed_boost=true equipada (ver
# AbilityData.speed_boost) — usado em _on_end_turn_pressed() pra saber se a
# Speed dela sobe sozinha ao final do turno.
func has_speed_boost(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.speed_boost:
			return true
	return false

# 1.5x, mesmo valor da série principal — constante de REGRA (ver comentário
# de SHEER_FORCE_MULTIPLIER acima pro mesmo raciocínio), não fica no dado
# porque Flash Fire só tem esse valor fixo.
const FLASH_FIRE_MULTIPLIER = 1.5

# true se `u` carrega uma Habilidade com flash_fire=true equipada (ver
# AbilityData.flash_fire) — mesmo padrão de has_sheer_force/has_speed_boost
# acima. Usado tanto pra decidir se aplica a Status Condition "Charged" (ver
# execute_attack/execute_attack_burst, quando `u` é quem DEFENDE um ataque
# Fire) quanto se CONSOME/aplica o bônus (calculate_damage_modifiers +
# execute_attack/execute_attack_burst, quando `u` é quem ATACA) — a
# Habilidade em si só HABILITA o mecanismo, quem guarda o estado "armado" É
# a Status Condition (ver Unit.status_conditions).
func has_flash_fire(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.flash_fire:
			return true
	return false

# true se `u` carrega uma Habilidade com chlorophyll=true equipada (ver
# AbilityData.chlorophyll) — mesmo padrão de has_sheer_force/has_speed_boost/
# has_flash_fire acima. Usado só em begin_current_turn(), pra decidir se soma
# +1 em attacks_remaining ("extra action point", pedido do usuário: "If the
# weather is Sun (either Sunny or Harsh Sunlight), this unit has an extra
# action point" — Ivysaur/Venusaur é o primeiro caso).
func has_chlorophyll(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.chlorophyll:
			return true
	return false

# true se `u` carrega uma Habilidade com shield_dust=true equipada (ver
# AbilityData.shield_dust) — usado em _try_apply_secondary_status/
# _try_apply_secondary_stat_change pra cancelar o efeito secundário de um
# golpe INIMIGO quando `u` é quem DEFENDE. Mesmo padrão de has_sheer_force
# acima, só que do lado de quem RECEBE o golpe, não de quem o usa.
func has_shield_dust(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.shield_dust:
			return true
	return false

# true se `u` carrega uma Habilidade com run_away=true equipada (ver
# AbilityData.run_away) — usado em _try_run_away, chamado depois que `u`
# (quem DEFENDE) sobrevive a um golpe que causa dano.
func has_run_away(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.run_away:
			return true
	return false

# true se `u` carrega uma Habilidade com compound_eyes=true equipada (ver
# AbilityData.compound_eyes) — usado em Unit.get_accuracy_multiplier().
func has_compound_eyes(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.compound_eyes:
			return true
	return false

# true se `u` carrega uma Habilidade com tinted_lens=true equipada (ver
# AbilityData.tinted_lens) — usado em calculate_damage().
func has_tinted_lens(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.tinted_lens:
			return true
	return false

# true se `u` carrega uma Habilidade com shed_skin=true equipada (ver
# AbilityData.shed_skin) — usado em apply_end_of_turn_status().
func has_shed_skin(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.shed_skin:
			return true
	return false

# true se `u` carrega uma Habilidade com wonder_skin=true equipada (ver
# AbilityData.wonder_skin) — usado em _status_move_hits_wonder_skin, chamado
# de dentro de execute_status_attack antes do roll de acerto.
func has_wonder_skin(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.wonder_skin:
			return true
	return false

# true se `u` carrega uma Habilidade com effect_spore=true equipada (ver
# AbilityData.effect_spore) — usado em _try_effect_spore, chamado quando `u`
# é quem DEFENDE um golpe de CONTATO.
func has_effect_spore(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.effect_spore:
			return true
	return false

# true se `u` carrega uma Habilidade com poison_heal=true equipada (ver
# AbilityData.poison_heal) — usado em apply_end_of_turn_status().
func has_poison_heal(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.poison_heal:
			return true
	return false

# 1/8 = 12.5%, valor fixo da Habilidade (ver AbilityData.poison_heal, pedido
# do usuário: "Heal 1/8 of its HP instead of taking Poison damage") —
# constante de REGRA, mesmo padrão de AQUA_RING_HEAL_FRACTION_DENOMINATOR e
# afins.
const POISON_HEAL_FRACTION = 1.0 / 8.0

# true se `u` carrega uma Habilidade com technician=true equipada (ver
# AbilityData.technician) — usado em calculate_damage_modifiers().
func has_technician(u: Node) -> bool:
	for action in u.data.slots:
		if action is AbilityData and action.technician:
			return true
	return false

# 1.5x fixo (ver AbilityData.technician, pedido do usuário, Breloom: "If the
# base power of a move is less than or equal 60, multiply it by x1,5") —
# constante de REGRA, mesmo padrão de SHEER_FORCE_MULTIPLIER/FLASH_FIRE_
# MULTIPLIER acima.
const TECHNICIAN_MULTIPLIER = 1.5
const TECHNICIAN_POWER_THRESHOLD = 60

# Effect Spore (ver AbilityData.effect_spore, pedido do usuário, Shroomish:
# "Counts as a Powder move, when taking contact attack, 30% chance to make
# target Paralyzed, Sleep or Poisoned. Status condition is chosen randomly")
# — chamado depois que `defender` (quem carrega a Habilidade) leva um golpe
# de CONTATO (ver AttackData.makes_contact), independente de `defender` ter
# sobrevivido ou não (o contato já aconteceu no instante do impacto, antes de
# resolver o destino do defensor — mesmo espírito de Run Away, que só olha
# "defender sobreviveu", mas aqui o efeito é em QUEM ATACOU, então nem
# precisa dessa checagem). "Counts as a Powder move" (pedido do usuário) =
# Grass é imune, mesma regra que os golpes tagged "Powder" já seguem (ver
# execute_status_attack) — aqui replicada manualmente porque não existe
# tag nenhuma num golpe QUE CAUSA DANO pra checar.
const EFFECT_SPORE_CHANCE = 0.3
const EFFECT_SPORE_STATUSES = ["Paralyzed", "Asleep", "Poisoned"]

func _try_effect_spore(attacker: Node, defender: Node, attack: AttackData) -> void:
	if not attack.makes_contact or not has_effect_spore(defender):
		return
	if attacker.data.types.has("Grass"):
		return
	if randf() >= EFFECT_SPORE_CHANCE:
		return
	var status_name: String = EFFECT_SPORE_STATUSES[randi() % EFFECT_SPORE_STATUSES.size()]
	if attacker.apply_status_condition(status_name, defender):
		log_message("%s's Effect Spore inflicted %s on %s!" % [defender.data.unit_name, status_name, attacker.data.unit_name])

# Run Away (ver AbilityData.run_away, pedido do usuário, 2026-07-23, Caterpie
# Hidden: "When damaged with an attack, the user moves 1 tile away from the
# enemy that damaged it") — chamado logo depois de defender.take_damage() nos
# dois caminhos de dano (execute_attack de alvo único, execute_attack_burst).
# `dir` = sinal do delta de `attacker` pra `defender` (mesma conta de sign()
# já usada noutros lugares pra reconstruir direção 8-way, ver run_enemy_turn) —
# empurra na direção OPOSTA, ou seja, continuando a reta que já vai de quem
# atacou até quem defendeu, 1 tile a mais. Só se move se a célula de destino
# estiver livre (sem parede/borda/outra unidade) — senão simplesmente não
# acontece nada, sem mensagem de falha (mesmo "silencioso" de Shield Dust
# acima). defender.hp_current <= 0 (morreu com esse golpe) sai de cara: não
# faz sentido mover um cadáver.
func _try_run_away(defender: Node, attacker: Node) -> void:
	if defender.hp_current <= 0 or not has_run_away(defender):
		return
	var dir = Vector2i(sign(defender.grid_pos.x - attacker.grid_pos.x), sign(defender.grid_pos.y - attacker.grid_pos.y))
	if dir == Vector2i.ZERO:
		return
	var target_cell = defender.grid_pos + dir
	# Pedido do usuário (2026-07-24): "Run away can't move units through fluid
	# tiles if they can't naturally move there" — mesma checagem de
	# can_unit_cross_fluid() que get_reachable_tiles()/movimento normal já usa
	# (ver comentário grande de can_cross_fluid): se o destino é fluido E esta
	# unidade não atravessa fluido (nem por tipo/grounded/Levitate), trata IGUAL
	# a esbarrar numa parede — simplesmente não se move, sem mensagem.
	if is_wall_or_border(target_cell) or get_unit_at(target_cell) != null or (fluid_cells.has(target_cell) and not can_unit_cross_fluid(defender)):
		return
	defender.move_to(target_cell)
	log_message("%s ran away from the attack!" % defender.data.unit_name)

# 1.3 fixo (ver AbilityData.compound_eyes) é aplicado direto em
# Unit.get_accuracy_multiplier() (não aqui) — essa função já mora em unit.gd e
# não tem acesso fácil às constantes deste arquivo, mesmo tratamento que Blind
# (0.5) já recebe lá, hardcoded local em vez de importar uma constante daqui.
const TINTED_LENS_MULTIPLIER = 2.0

# Chamado no INÍCIO de execute_attack/execute_status_attack/
# execute_attack_burst (cobre ataque comum, TM e Burst/Line, jogador e
# inimigo — ver comentário grande de Unit.consecutive_attack_uses) — decide
# se este uso é "consecutivo" (mesmo AttackData que da última vez, soma 1)
# ou não (reseta pra 1), e sempre marca `attack` como já usado nesta
# batalha (ver Unit.used_attacks_this_battle). Roda pra TODO ataque, não só
# os que leem esse estado depois (Rollout) — assim usar Rollout, Ember,
# Rollout de novo corretamente reseta a sequência do Rollout de volta pra 1
# no meio, sem precisar de nenhum código especial em Ember.
func _track_attack_use(attacker: Node, attack: AttackData) -> void:
	if attacker.last_attack_used == attack:
		attacker.consecutive_attack_uses += 1
	else:
		attacker.last_attack_used = attack
		attacker.consecutive_attack_uses = 1
	attacker.used_attacks_this_battle[attack] = true

# Power de verdade a usar em calculate_damage() — attack.power pra quase
# todo ataque, OU a fórmula de escala (ver AttackData.
# scales_with_consecutive_use/Rollout) quando marcado. `uses` vem de
# attacker.consecutive_attack_uses, que _track_attack_use já deixou
# atualizado ANTES de calculate_damage rodar pro golpe de verdade
# acontecendo — nas chamadas de PREVIEW/decisão de IA (calculate_damage
# calculado sem o golpe ter disparado ainda), `attacker.last_attack_used`
# pode não ser `attack` ainda (0 uses "reais" registrados), então usamos 1
# como chute conservador (a IA vê o power do 1º uso, não o real se já
# estiver numa sequência — imprecisão aceitável só de preview).
func get_effective_power(attacker: Node, attack: AttackData, defender: Node = null) -> int:
	if attack.scales_with_consecutive_use:
		var uses = attacker.consecutive_attack_uses if attacker.last_attack_used == attack else 1
		uses = max(1, uses)
		var boosted = attack.consecutive_use_boost_prerequisite != null and attacker.used_attacks_this_battle.has(attack.consecutive_use_boost_prerequisite)
		var base = attack.consecutive_use_boosted_base_power if boosted else attack.consecutive_use_base_power
		var cap = attack.consecutive_use_boosted_max_power if boosted else attack.consecutive_use_max_power
		return min(cap, base * int(pow(2, uses - 1)))
	if attack.power_scales_with_own_hp:
		# Eruption: "Base power = 150 x CurrentHP/Max HP" — attack.power
		# guarda o 150 (ver comentário grande em AttackData.
		# power_scales_with_own_hp). max(1, ...) mesma razão de sempre: 0 de
		# power "de mentirinha" seria confuso, e hp_max=0 nunca deveria
		# acontecer, mas divide por zero seria pior que isso.
		if attacker.hp_max <= 0:
			return attack.power
		var hp_ratio = float(attacker.hp_current) / float(attacker.hp_max)
		return max(1, int(round(attack.power * hp_ratio)))
	if attack.power_scales_with_speed_ratio and defender != null:
		# Gyro Ball: "25 x target speed/user speed, capped at 150" —
		# attack.power guarda o 25 (ver comentário grande em AttackData.
		# power_scales_with_speed_ratio). Speed já com estágio alterado
		# (Unit.get_effective_stat), mesmo stat lido pelo resto da fórmula de
		# dano. attacker.Speed <= 0 nunca deveria acontecer (stat base
		# sempre > 0), mas o guard evita dividir por zero de qualquer jeito.
		var attacker_speed = attacker.get_effective_stat("speed")
		if attacker_speed <= 0:
			return attack.power
		var defender_speed = defender.get_effective_stat("speed")
		var power = int(round(attack.power * float(defender_speed) / float(attacker_speed)))
		return max(1, min(attack.power_scales_with_speed_ratio_cap, power))
	if attack.power_doubles_if_target_has_status != "" and defender != null and defender.has_status(attack.power_doubles_if_target_has_status):
		# Infernal Parade: dobra se o alvo estiver EXATAMENTE com essa Status
		# Condition (ver comentário grande em AttackData.
		# power_doubles_if_target_has_status) — checado ANTES do golpe
		# aplicar seu próprio secondary_status (ver execute_attack: dano sai
		# primeiro, efeito secundário depois), então um Infernal Parade que
		# ELE MESMO acabou de queimar o alvo não conta em dobro nesse mesmo
		# golpe — só se o alvo JÁ chegou queimado.
		return attack.power * 2
	if attack.power_halved_in_rain_sand_snow and (current_weather == WEATHER_RAIN or current_weather == WEATHER_SANDSTORM or current_weather == WEATHER_SNOW):
		# Solar Beam (ver comentário grande em AttackData.
		# power_halved_in_rain_sand_snow) — só estes três, Sol/clima neutro
		# continuam com o power cheio.
		return max(1, attack.power / 2)
	return attack.power

# Range de verdade a usar na hora de RESOLVER o alvo (ver handle_targeting_
# input, chamado ANTES de _track_attack_use rodar pra este uso — por isso a
# "prévia": +1 se for continuar a mesma sequência, 1 se for começar uma
# nova). AttackData.range continua sendo o alcance MÁXIMO TEÓRICO (usado só
# pra decidir se o clique é válido, ver is_valid_target_cell) — este é o
# alcance de VERDADE, sempre <= isso.
func get_effective_attack_range(attacker: Node, attack: AttackData) -> int:
	if not attack.scales_with_consecutive_use:
		return attack.range
	var prospective_uses = attacker.consecutive_attack_uses + 1 if attacker.last_attack_used == attack else 1
	return min(prospective_uses, attack.consecutive_use_max_range)

# true se ESTE golpe tem pelo menos um efeito secundário configurado (ver
# AttackData.secondary_status/secondary_status_2) — Sheer Force só faz
# diferença nenhuma (nem bônus de dano, nem cancelamento) em golpes sem
# efeito secundário nenhum.
func attack_has_secondary_effect(attack: AttackData) -> bool:
	return attack.secondary_status != "" or attack.secondary_status_2 != ""

# "Priority", nesta conversão pra tactics, majoritariamente vira ALCANCE
# EXTRA em vez de furar a ordem de turno (pedido do usuário, decidido em cima
# de Quick Attack: "Priority will be, for the most part, giving extra range
# to attacks") — Quick Attack é o primeiro caso: is_projectile=false, range=2
# (em vez do 1 de sempre pra corpo-a-corpo). Esse alcance maior sozinho não
# bastava (a animação de ataque comum toca PARADA no lugar — ver
# Unit.play_attack_animation), então esta função cobre a parte visual: quem
# ataca de longe precisa fisicamente se aproximar primeiro ("During the
# animation the user must lunge 1 tile further if targeting at max range").
#
# GENÉRico de propósito (roda pra QUALQUER AttackData não-projétil com
# range > 1, não só Quick Attack — pedido explícito do usuário: "General
# mechanic ... future melee-range moves get this for free") — ataques com
# range=1 (o padrão) nunca disparam isso, porque `distance` já vem 1 sempre
# que a mira for válida (ver is_valid_target_cell).
#
# Regra decidida com o usuário: "snap back to starting place ONLY if the
# tile closest to target is occupied, if it is free, move unit to it" — ou
# seja, NÃO existe uma animação de "avança e volta" fake: se a célula mais
# perto do alvo (1 passo antes dele, na direção mirada) estiver LIVRE, quem
# ataca REALMENTE se move pra lá (grid_pos muda de verdade, via
# Unit.move_to() — mesmo mecanismo de movimento normal, ver
# move_unit_along_path acima); se estiver OCUPADA (por unidade OU parede/
# borda), a unidade simplesmente ataca do lugar de sempre, sem se mexer nem
# um pixel — "ficou no lugar de partida" nesse caso é literal, nunca chegou
# a sair.
func _try_melee_lunge(attacker: Node, defender: Node, attack: AttackData) -> void:
	if defender == null or attack.range <= 1:
		return
	# is_projectile normalmente NUNCA lunge (um golpe à distância de verdade,
	# tipo Ember, não devia fazer quem ataca correr pra cima do alvo) — o
	# único jeito de um projétil lunge é opt-in explícito (ver AttackData.
	# lunges_to_target/Rollout).
	if attack.is_projectile and not attack.lunges_to_target:
		return
	var delta = defender.grid_pos - attacker.grid_pos
	var distance = max(abs(delta.x), abs(delta.y))
	if distance <= 1:
		return   # já adjacente (mirou dentro do range, mas não no máximo) — sem lunge
	var dir = Vector2i(sign(delta.x), sign(delta.y))
	var lunge_cell = attacker.grid_pos + dir * (distance - 1)
	if is_wall_or_border(lunge_cell) or get_unit_at(lunge_cell) != null:
		return   # célula de destino ocupada — ataca do lugar de sempre
	attacker.move_to(lunge_cell)
	while attacker.is_moving:
		await get_tree().process_frame

# Aplica um ataque de verdade: calcula o dano, desconta do HP do alvo e gasta
# 1 uso do slot (só se a ação tiver contador — ver ActionData.max_uses).
# defender pode chegar null aqui — caso da Confusão, quando o ataque é
# disparado (gasta uso/attacks_remaining normalmente) mas a mira embaralhada
# não achou ninguém na direção sorteada (ver resolve_confused_target). Nesse
# caso o atacante ainda faz a animação de ataque, só não há reação de
# ninguém nem dano — ver o "if defender == null: return" logo depois do delay.
#
# consume_slot_use=false é usado por execute_tm_attack (ver mais abaixo): um
# TM executa o attack.max_uses/PP do ATAQUE REFERENCIADO (ex: Ice Fang), que
# não tem relação nenhuma com o estoque do próprio item TM — quem desconta a
# carga do TM é execute_tm_attack, via UnitData.slot_quantities, não aqui.
func execute_attack(attacker: Node, defender: Node, attack: AttackData, slot_index: int, consume_slot_use: bool = true) -> void:
	await _try_melee_lunge(attacker, defender, attack)
	attacker.face_towards(defender.grid_pos if defender != null else attacker.grid_pos)
	attacker.play_attack_animation(attack.is_special)
	# Cast effect (ver AttackData.cast_frames_by_direction): sai de 1 tile à
	# frente de quem ataca e viaja — sem await, é só reação visual do
	# "windup" do golpe, não deve atrasar o resto (mesma ideia de
	# play_impact_effect). execute_attack não tem um `dir` pronto (mira 1
	# alvo, não uma direção) — reconstrói a partir de attacker.facing, já
	# ajustado pelo face_towards() logo acima.
	if attack.cast_frames_by_direction != null:
		play_cast_effect(attack.cast_frames_by_direction, attacker, FACING_TO_DIR.get(attacker.facing, Vector2i.ZERO), attack.range)
	log_message("%s used %s." % [attacker.data.unit_name, attack.action_name])
	if consume_slot_use and attack.max_uses > 0:
		attacker.slot_uses[slot_index] -= 1
	attacker.attacks_remaining -= 1
	refresh_action_slots_hud()
	_track_attack_use(attacker, attack)

	# Espera até o golpe "conectar" (ver comentário de attack_hit_delay em
	# UnitData) antes de reagir — sem isso o defensor tomava dano e se
	# encolhia de dor antes mesmo do ataque encostar nele.
	var hit_delay = attacker.data.special_hit_delay if attack.is_special else attacker.data.attack_hit_delay
	await get_tree().create_timer(hit_delay).timeout

	if defender == null:
		# Confusão embaralhou a mira e não achou ninguém — não conecta, então
		# quebra qualquer sequência de uso consecutivo em andamento (ver
		# Unit.consecutive_attack_uses/Rollout: "has to reset after missing").
		attacker.consecutive_attack_uses = 0
		return   # ataque confuso que não achou ninguém na direção sorteada

	# Ataque-projétil: depois do "cast" do atacante, o projétil ainda precisa
	# viajar até o alvo antes de reagir — sem isso o defensor levava o dano
	# antes do sprite do projétil sequer sair do lugar. projectile_frames
	# conta como "tem arte" também, não só projectile_texture (ver
	# AttackData.projectile_frames — Water Gun usa esse formato).
	if attack.is_projectile and (attack.projectile_texture != null or not attack.projectile_frames.is_empty()):
		await fire_projectile(attack.projectile_texture, attacker.position, defender.position, 0, attack.projectile_frames, attack.projectile_faces_right)

	# Roll de acerto (attack.accuracy, ver AttackData) — DEPOIS do windup/cast/
	# projétil (isso sempre joga visualmente, acerte ou erre o golpe) e ANTES
	# de qualquer reação de quem defende (descongelar, hurt animation, efeito
	# de impacto, dano, efeitos secundários). Unit.get_accuracy_multiplier()
	# já embute Focus Band (ItemData.accuracy_multiplier) e o x0.5 de Blind —
	# accuracy = 1.0 (padrão de AttackData) sempre acerta, pulando o randf()
	# de propósito (evita, ainda que raríssimo, randf() == 1.0 falhar um golpe
	# que deveria ser garantido).
	# Harsh Sunlight faz Water falhar SEMPRE, Heavy Rain faz Fire falhar
	# SEMPRE (pedido do usuário) — checado ANTES do roll de accuracy normal
	# (mesmo lugar, mesmo formato de saída de "errou" que o miss comum logo
	# abaixo: consome o uso do slot igual, só não causa dano nem efeito
	# nenhum) porque nos jogos de verdade isso não é "imunidade" nenhuma,
	# é o golpe sendo tentado e falhando por conta do clima.
	if _weather_blocks_attack(attack):
		log_message("%s's attack failed because of the weather!" % attacker.data.unit_name)
		# Golpe falhou por causa do clima, não conectou de verdade — quebra a
		# sequência de uso consecutivo (ver Unit.consecutive_attack_uses).
		attacker.consecutive_attack_uses = 0
		refresh_unit_summary_hud()
		check_auto_end_turn()
		return

	# never_misses (ver AttackData) pula o roll de acerto POR COMPLETO — Swift
	# é o primeiro caso ("never misses" de verdade, não só accuracy=1.0
	# padrão): diferente de accuracy=1.0 sozinho, isso ignora até
	# attacker.get_accuracy_multiplier() (ex: o próprio atacante estar Blind,
	# ver AttackData.inflicts_status/Smokescreen), que de outra forma ainda
	# poderia derrubar final_accuracy abaixo de 1.0 e causar um erro.
	var final_accuracy = attack.accuracy * attacker.get_accuracy_multiplier()
	if not attack.never_misses and final_accuracy < 1.0 and randf() >= final_accuracy:
		log_message("%s's attack missed!" % attacker.data.unit_name)
		# Errou de verdade — quebra a sequência de uso consecutivo (ver
		# Unit.consecutive_attack_uses/AttackData.scales_with_consecutive_use
		# — pedido do usuário: "Rollout has to reset after missing"). Sem
		# isso, _track_attack_use já tinha incrementado o contador lá em
		# cima achando que "usou de novo", mesmo o golpe nunca conectando.
		attacker.consecutive_attack_uses = 0
		refresh_unit_summary_hud()
		check_auto_end_turn()
		return

	# Flash Fire (ver Unit.status_conditions/AbilityData.flash_fire): aplica
	# a Status Condition "Charged" assim que o golpe Fire CONECTA de verdade
	# (depois do roll de acerto acima, então um golpe que erra não arma
	# nada) — MESMO que o dano real vá sair 0 por causa da imunidade total
	# (ver has_type_immunity_ability/calculate_damage), porque na série
	# principal Flash Fire ativa por ser alvo de um golpe Fire, não por
	# levar dano dele. apply_status_condition() já recusa sozinha se
	# "Charged" já estiver ativa (defensor já tinha levado outro Fire antes
	# de gastar o próprio) — por isso só loga a mensagem se REALMENTE
	# aplicou agora.
	# Protected (ver AttackData.inflicts_status_on_self/Protect): golpe
	# ACERTOU (já passou o roll de acerto acima), mas o alvo está com o
	# escudo de Protect ativo — bloqueia TUDO (dano, Flash Fire, descongelar,
	# efeito secundário), sem contar como erro pra fins de
	# consecutive_attack_uses (é diferente de um miss de verdade: o golpe
	# conectou, só não teve efeito nenhum, mesmo tratamento que imunidade de
	# tipo já recebe).
	if defender.has_status("Protected"):
		# Feint (ver AttackData.pierces_protect, pedido do usuário: "If target
		# was Protected hit anyways and remove Protect status") — em vez do
		# bloqueio normal, remove o escudo e deixa o resto da função continuar
		# como se Protected nunca tivesse existido (dano normal acontece).
		if attack.pierces_protect:
			defender.cure_status_condition("Protected")
			log_message("%s's Protect was broken through!" % defender.data.unit_name)
		else:
			log_message("%s protected itself!" % defender.data.unit_name)
			refresh_unit_summary_hud()
			check_auto_end_turn()
			return

	# Brick Break (ver AttackData.removes_screens) — remove as 3 Status
	# Conditions de "tela" do alvo ANTES do dano, se ele tiver alguma
	# (groundwork: nenhum golpe deste projeto ainda CRIA essas 3 condições,
	# ver comentário grande do campo em attack_data.gd — este bloco já
	# funciona certo sozinho assim que uma existir).
	if attack.removes_screens:
		for screen_name in ["Light Screen", "Reflect", "Aurora Veil"]:
			if defender.has_status(screen_name):
				defender.cure_status_condition(screen_name)
				log_message("%s's %s shattered!" % [defender.data.unit_name, screen_name])

	if attack.element_type == "Fire" and has_flash_fire(defender) and defender.apply_status_condition("Charged"):
		log_message("%s's Flash Fire was triggered!" % defender.data.unit_name)

	# Frozen descongela na hora ao ser atingida por qualquer ataque tipo Fire
	# — automático, não precisa rolar chance nenhuma. ANTES de
	# play_hurt_animation() de propósito (diferente do Asleep logo abaixo,
	# que cura DEPOIS): _play_anim() ignora qualquer chamada de animação
	# enquanto Frozen estiver ativa (é assim que Frozen "não anima nada" —
	# ver comentário em Unit._play_anim), então curar depois faria a reação
	# de dor nem aparecer na tela.
	if defender.has_status("Frozen") and attack.element_type == "Fire":
		defender.cure_status_condition("Frozen")
		log_message("%s thawed out!" % defender.data.unit_name)

	defender.face_towards(attacker.grid_pos)
	defender.play_hurt_animation()

	# Efeito de impacto: toca PARADO em cima do alvo, ao mesmo tempo que a
	# animação de hurt — diferente do projétil (que precisa ser esperado
	# antes de aplicar dano), aqui não damos await: é só reação visual, não
	# deve atrasar o resto do turno. impact_texture_2 (ver AttackData) é uma
	# segunda camada opcional tocada JUNTO da primeira, sobreposta no mesmo
	# ponto (ex: Ice Fang = mordida + cacos de gelo, ver ImpactEffect.play()).
	# impact_frames (ver AttackData) conta como "tem arte" também, não só
	# impact_texture — mesma ideia de projectile_frames (Confusion: 13
	# arquivos separados, ataque à distância sem projétil, só o impacto).
	if attack.impact_texture != null or attack.impact_texture_2 != null or not attack.impact_frames.is_empty():
		play_impact_effect(attack.impact_texture, defender.position, attack.impact_texture_2, attack.impact_frames)

	# Asleep só cura ao ser ATACADA de verdade (não pelo tick de veneno, que
	# usa Unit.take_damage() por outro caminho — ver apply_end_of_turn_status,
	# que não passa por aqui). Antes de aplicar o dano, senão a unidade já
	# "acordada" mudaria a leitura de status no meio da mesma reação.
	if defender.has_status("Asleep"):
		defender.cure_status_condition("Asleep")

	# hp_lost (não `damage` cru) é o que self_recoil_fraction_of_damage_dealt
	# usa mais abaixo — bug reportado pelo usuário: um golpe que causa MUITO
	# mais dano do que o HP restante do alvo (overkill, ex: Typhlosion nível
	# 100 batendo 1000+ num alvo de 10 HP) NÃO deveria gerar recoil como se
	# tivesse causado 1000 de dano de verdade — só os 10 HP que o alvo
	# realmente tinha pra perder. Capturado ANTES de take_damage, já que
	# depois disso hp_current já reflete o alvo morto (0), perdendo a
	# diferença.
	var hp_lost = 0
	# Pin Missile (ver AttackData.is_multi_hit, pedido do usuário, Beedrill:
	# "randomly decide if they will fire 2/3/4/5 times... Only consumes 1 PP
	# regardless of roll. Treat each one as a different attack") — cada
	# acerto rola crítico e dano DE NOVO (_resolve_multi_hit_damage), em vez
	# do único roll de is_critical/damage abaixo. O roll de ACERTO (accuracy)
	# continua sendo UMA vez só pro golpe inteiro (feito bem antes, fora
	# desta função) — só o NÚMERO de vezes que conecta é sorteado aqui.
	if attack.is_multi_hit:
		hp_lost = _resolve_multi_hit_damage(attacker, defender, attack)
	else:
		# Rolado UMA vez só, antes de calcular o dano (ver comentário grande em
		# calculate_damage sobre por que is_critical vem pronto de fora em vez de
		# a função sortear ela mesma). get_effective_crit_chance() troca pela
		# chance própria do golpe se ele tiver uma (ver AttackData.
		# crit_chance_override — Razor Leaf é o primeiro caso) e dobra se
		# `attacker` estiver com Focus Energy (ver status novo, Beedrill).
		var is_critical = randf() < get_effective_crit_chance(attack, attacker)
		var damage = calculate_damage(attacker, defender, attack, is_critical)
		hp_lost = min(damage, defender.hp_current)
		defender.take_damage(damage)
		if is_critical:
			log_message("A critical hit!")

	# Run Away (ver AbilityData.run_away/has_run_away/_try_run_away) — só se
	# `defender` sobreviveu, sem depender de Sheer Force nem de mais nada
	# (mecanismo independente dos efeitos secundários abaixo). Pra multi-hit,
	# roda só UMA vez, depois de todos os acertos (não a cada acerto) — mais
	# simples e evita o alvo "escapando" no meio de uma rajada que já mirou
	# nele.
	_try_run_away(defender, attacker)

	# Effect Spore (ver AbilityData.effect_spore/_try_effect_spore) — reação
	# de QUEM DEFENDE contra QUEM ATACA, independente de Sheer Force (não é um
	# "efeito secundário do golpe" contado por attack_has_secondary_effect,
	# é uma Habilidade do defensor) e independente do defensor ter sobrevivido
	# (o contato já aconteceu, ver comentário grande da função).
	_try_effect_spore(attacker, defender, attack)

	# Roubo de vida (ver AttackData.drain_fraction, pedido do usuário,
	# Venonat/Shroomish: "Heals user for 50% of damage dealt (HP reduced)") —
	# usa hp_lost (não `damage` bruto), mesmo cuidado de overkill do comentário
	# grande acima. Só cura se o golpe realmente tirou HP de alguém (hp_lost >
	# 0) e só quem atacou ainda estiver vivo (Counter logo abaixo pode matar o
	# atacante ANTES daqui? não — Counter só roda depois do bloco de recoil,
	# mais abaixo, então `attacker` sempre está vivo neste ponto).
	if attack.drain_fraction > 0.0 and hp_lost > 0:
		var drain_amount = max(1, int(round(hp_lost * attack.drain_fraction)))
		attacker.hp_current = min(attacker.hp_current + drain_amount, attacker.hp_max)
		attacker.update_health_bar()
		attacker.sync_to_data()
		log_message("%s had its energy drained!" % defender.data.unit_name)

	# Consome a Status Condition "Charged" (ver Unit.status_conditions) SÓ
	# AQUI — depois que o dano REAL desse golpe já saiu de calculate_damage()
	# (que já aplicou o x1.5, ver calculate_damage_modifiers) — nunca dentro
	# de calculate_damage_modifiers, porque essa função também roda em
	# previews/decisão de IA sem o golpe estar realmente acontecendo (ver
	# comentário lá). Assim o cartucho só é gasto quando o golpe Fire de
	# verdade sai.
	if attack.element_type == "Fire" and attacker.has_status("Charged") and has_flash_fire(attacker):
		attacker.cure_status_condition("Charged")

	# Mensagem de efetividade — mesma lógica de calculate_damage (efetividade
	# de tipo x Habilidade de imunidade), recalculada aqui só pra decidir o
	# texto (sem efeito colateral nenhum, é a mesma fórmula, ver comentário
	# de calculate_damage acima). "Sem efeito" cobre tanto imunidade x0 da
	# TypeChart quanto imunidade por Habilidade (ex: Levitate).
	var effectiveness = get_weather_adjusted_effectiveness(attack.element_type, defender)
	if effectiveness == 0.0 or has_type_immunity_ability(defender, attack.element_type):
		log_message("It had no effect on %s!" % defender.data.unit_name)
	elif effectiveness > 1.0:
		log_message("It's super effective!")
	elif effectiveness < 1.0:
		log_message("It's not very effective...")

	# Efeito(s) secundário(s) (ex: Ember -> 10% de queimar o alvo, ver
	# AttackData.secondary_status/secondary_status_chance) — até DOIS por
	# ataque, rolados de forma independente (ver AttackData.
	# secondary_status_2, pensado pra golpes como Ice Fang: 10% de congelar
	# E, numa rolagem separada, 10% de Flinch). Só tenta se o alvo sobreviveu
	# ao golpe — não faz sentido aplicar Status Condition em quem já morreu.
	#
	# Sheer Force (ver AbilityData.sheer_force/has_sheer_force) CANCELA o
	# efeito secundário por completo — o bônus de 30% de dano (ver
	# calculate_damage_modifiers/SHEER_FORCE_MULTIPLIER) já foi aplicado no
	# `damage` calculado logo acima; aqui só falta garantir que o efeito em
	# si nunca dispara pra quem carrega essa Habilidade.
	if not has_sheer_force(attacker):
		# Boost de stat no próprio atacante (ex: Ancient Power) roda MESMO que o
		# defensor tenha desmaiado com esse golpe — diferente de secondary_status
		# abaixo (que não faz sentido aplicar em quem já morreu), aqui o alvo do
		# efeito é quem ataca, então a sobrevivência do defensor é irrelevante.
		_try_apply_self_stat_boost(attacker, attack)
		# stat_change_stat/_target == "Self" (ver AttackData — mesmo campo que
		# Defense Curl usa em execute_status_attack, agora também lido AQUI pra
		# ataque QUE CAUSA DANO) — Flame Charge é o primeiro caso: golpe físico
		# normal que, de quebra, sobe a própria Speed em +1, SEMPRE (sem chance
		# nenhuma, mesmo espírito de stat_change_amount noutros lugares).
		# Diferente de _try_apply_self_stat_boost logo acima (Ancient Power:
		# sobe os 5 stats de uma vez, com uma % de chance), este é UM stat só,
		# garantido — por isso são dois campos/caminhos separados em vez de
		# reaproveitar self_stat_boost_amount pra tudo.
		if attack.stat_change_target == "Self" and attack.stat_change_stat != "":
			apply_stat_change(attacker, attack.stat_change_stat, attack.stat_change_amount)
		if defender.hp_current > 0:
			_try_apply_secondary_status(defender, attack.secondary_status, attack.secondary_status_chance, attack.secondary_status_texture)
			_try_apply_secondary_status(defender, attack.secondary_status_2, attack.secondary_status_chance_2, attack.secondary_status_texture_2)
			_try_apply_secondary_stat_change(defender, attack)
	# Bug Bite (ver AttackData.steals_target_berry/_try_bug_bite_steal_berry)
	# — fora do bloco "if not has_sheer_force" de propósito: roubo de Berry não
	# é um "efeito secundário" no sentido de attack_has_secondary_effect() (só
	# olha secondary_status/_2), então Sheer Force não interfere nele.
	if defender.hp_current > 0:
		_try_bug_bite_steal_berry(attacker, defender, attack)

	if defender.hp_current <= 0:
		log_message("%s was defeated!" % defender.data.unit_name)
		award_experience(attacker, defender)
		remove_defeated_unit(defender)
		_apply_challenge_permadeath(defender)
		if enemy_units.is_empty() or player_units.is_empty():
			await end_battle(defender, enemy_units.is_empty())
			return

	# Recoil (ver AttackData.self_max_hp_recoil_fraction — Struggle é o
	# primeiro caso, 0.25) — SEMPRE que o golpe causou dano de verdade
	# (chegamos até aqui, então acertou), depois de resolver o destino do
	# defensor acima, nunca antes. max(1, ...) pela mesma razão de
	# calculate_damage: um recoil "de mentirinha" (0 de dano) seria
	# confuso, melhor sempre custar pelo menos 1 de HP. Mesmo padrão de
	# "morte fora do execute_attack normal" que apply_end_of_turn_status já
	# usa pro tick de Poison: sem exp (não tem "quem matou", ver
	# award_experience), remove_defeated_unit + _apply_challenge_permadeath
	# + checagem de fim de batalha na mão, porque quem morreu aqui é quem
	# ATACOU, não o `defender` de sempre.
	# self_recoil_fraction_of_damage_dealt (ver AttackData — Double-Edge é o
	# primeiro caso, "1/3 of DAMAGE DEALT") é uma fração de `hp_lost` (o HP
	# que o alvo REALMENTE perdeu, não o `damage` bruto calculado — ver
	# comentário grande em hp_lost acima sobre o bug de overkill), não do
	# próprio hp_max — os dois campos são mutuamente exclusivos na prática
	# (nenhum golpe hoje tem os dois > 0 ao mesmo tempo, mas se tivesse, os
	# dois recoils somariam).
	var recoil_fraction = attack.self_max_hp_recoil_fraction
	var recoil_base = float(attacker.hp_max)
	if attack.self_recoil_fraction_of_damage_dealt > 0.0:
		recoil_fraction = attack.self_recoil_fraction_of_damage_dealt
		recoil_base = float(hp_lost)
	if recoil_fraction > 0.0:
		var recoil_damage = max(1, int(round(recoil_base * recoil_fraction)))
		attacker.take_damage(recoil_damage)
		log_message("%s is damaged by recoil!" % attacker.data.unit_name)
		if attacker.hp_current <= 0:
			log_message("%s fainted from recoil!" % attacker.data.unit_name)
			remove_defeated_unit(attacker)
			_apply_challenge_permadeath(attacker)
			if enemy_units.is_empty() or player_units.is_empty():
				await end_battle(attacker, enemy_units.is_empty())
			else:
				# attacker (a unidade DA VEZ) morreu do próprio recoil, mas o
				# time dela ainda tem gente — remove_defeated_unit() já
				# reindexou current_turn_index pra apontar pra PRÓXIMA
				# unidade da fila (ver comentário lá dentro). Chamar
				# check_auto_end_turn() normalmente aqui seria errado:
				# get_current_unit() já não é mais quem atacou, e a PRÓXIMA
				# unidade ainda está com move_budget_left/attacks_remaining
				# do turno anterior (não resetados pra ela ainda) —
				# begin_current_turn() é quem faz esse reset direito. Mas
				# NÃO pode ser chamado direto aqui: quem chamou execute_attack
				# (_run_player_attack) ainda tem duas linhas pra rodar DEPOIS
				# do await (action_in_progress = false; flee_button.visible =
				# true incondicional), e essas linhas rodariam DEPOIS de
				# qualquer begin_current_turn() síncrono, sobrescrevendo por
				# cima o flee_button.visible=false que begin_current_turn()
				# acabou de decidir certo (ex: se a PRÓXIMA unidade for
				# inimiga). call_deferred adia a chamada pro final do frame
				# atual — depois que _run_player_attack já terminou de
				# limpar — garantindo que begin_current_turn() sempre fala a
				# última palavra sobre o HUD.
				call_deferred("begin_current_turn")
			return

	# Counter (ver Unit.status_conditions/STATUS_DURATIONS["Counter"], pedido
	# do usuário, Breloom: "Gives Counter status for 2 turns. Whenever hit by
	# a physical, range 1 move, deals back x2 the hp reduced") — só golpes
	# FÍSICOS, alcance EXATAMENTE 1, sem ser projétil (mesmo critério de
	# "contato direto" que Feint/Brick Break já tratam acima), e só se o
	# golpe realmente tirou HP de verdade (hp_lost > 0 — um golpe imune a 0
	# de dano não deveria disparar retaliação nenhuma). Chegar até aqui já
	# implica que `defender` sobreviveu ao próprio golpe (ver o "return" logo
	# acima quando defender.hp_current <= 0).
	if defender.has_status("Counter") and not attack.is_special and attack.range == 1 and not attack.is_projectile and hp_lost > 0:
		var battle_ended_by_counter = await _try_counter(defender, attacker, hp_lost)
		if battle_ended_by_counter:
			return

	refresh_unit_summary_hud()
	check_auto_end_turn()

# Reflete x2 o HP que `defender` (quem tem "Counter" ativo) REALMENTE perdeu
# pro golpe que acabou de acertar — chamado de dentro de execute_attack,
# nunca sozinho. Mesmo tratamento de morte "fora do fluxo normal" que o
# bloco de recoil logo acima já usa (sem exp — não é um golpe de verdade de
# `defender` contra `attacker`, ver award_experience — remove_defeated_unit +
# _apply_challenge_permadeath + checagem de fim de batalha na mão). Devolve
# true se a batalha acabou aqui (mesmo contrato de execute_whirlwind_push).
func _try_counter(defender: Node, attacker: Node, hp_lost: int) -> bool:
	var counter_damage = max(1, hp_lost * 2)
	attacker.take_damage(counter_damage)
	log_message("%s countered the attack!" % defender.data.unit_name)
	if attacker.hp_current <= 0:
		log_message("%s fainted from the counter!" % attacker.data.unit_name)
		remove_defeated_unit(attacker)
		_apply_challenge_permadeath(attacker)
		if enemy_units.is_empty() or player_units.is_empty():
			await end_battle(attacker, enemy_units.is_empty())
		else:
			# Mesmo raciocínio de call_deferred do bloco de recoil acima —
			# quem chamou execute_attack ainda tem linhas pra rodar depois do
			# await, então adiamos begin_current_turn pro final do frame.
			call_deferred("begin_current_turn")
		return true
	return false

# Fase de CARGA de um golpe com AttackData.is_charge_move (Solar Beam é o
# primeiro caso) — chamado de dentro de execute_attack_burst quando o golpe
# ainda não deve disparar neste turno. Bem mais simples que um ataque de
# verdade: sem roll de acerto, sem alvo nenhum resolvido, sem dano — só
# consome a ação/PP deste turno e guarda o golpe + direção em
# Unit.charging_attack/charging_dir/charging_slot_index pra
# begin_current_turn() disparar de verdade no próximo Action Point desta
# unidade (ver comentário grande lá).
func execute_charge_attack(attacker: Node, attack: AttackData, dir: Vector2i, slot_index: int) -> void:
	if dir != Vector2i.ZERO:
		attacker.face_towards(attacker.grid_pos + dir)
	attacker.play_attack_animation(attack.is_special)
	log_message("%s used %s." % [attacker.data.unit_name, attack.action_name])
	log_message("%s began charging power!" % attacker.data.unit_name)
	if attack.max_uses > 0:
		attacker.slot_uses[slot_index] -= 1
	attacker.attacks_remaining -= 1
	refresh_action_slots_hud()
	_track_attack_use(attacker, attack)
	attacker.charging_attack = attack
	attacker.charging_dir = dir
	attacker.charging_slot_index = slot_index
	refresh_unit_summary_hud()
	check_auto_end_turn()

# Gêmeo de execute_attack acima, mas pra AttackData.area_shape == "Burst" OU
# "Line" (ver comentário grande lá — Lava Plume e Flamethrower são os dois
# primeiros casos): em vez de UM `defender` já resolvido, recebe `dir`
# (igual execute_status_attack — pra "Burst" o clique só confirma o uso, pra
# "Line" ele decide a direção do feixe, ver comentário de area_shape) e
# descobre os alvos sozinha: TODO MUNDO (aliado ou inimigo, dos dois times),
# exceto quem atacou. Bastante duplicado de
# execute_attack de propósito, em vez de tentar generalizar as duas em cima
# de uma função só — um refactor assim mexeria numa função que já funciona
# (single-target) bem perto do prazo do usuário; mais seguro ter duas
# funções separadas, cada uma clara sobre pra quantos alvos ela resolve.
#
# Uma coisa MUDA de execute_attack: o roll de acerto (accuracy) é feito UMA
# VEZ SÓ pro golpe inteiro (não por alvo) — faz sentido pra uma explosão
# centrada em quem ataca (ou "a explosão sai" ou não sai pra ninguém), e
# Unit.get_accuracy_multiplier() só depende de quem ATACA mesmo (Blind/Focus
# Band do atacante), nunca do alvo — então rolar por alvo daria sempre o
# mesmo resultado, só gastando randf() à toa.
# `charge_release` (novo, 2026-07-23 — ver AttackData.is_charge_move/Solar
# Beam): false pra toda chamada normal de sempre. true SÓ quando quem chama é
# begin_current_turn() disparando um golpe que ficou guardado em
# Unit.charging_attack — nesse caso a "ação" de usar o golpe já rolou (e já
# gastou 1 uso/PP) no turno em que ele foi CARREGADO (ver
# execute_charge_attack), então aqui a gente pula o desconto de slot_uses de
# novo (senão Solar Beam custaria 2 PP em vez de 1, diferente da série
# principal) e troca a mensagem de log pra deixar claro que é o DISPARO, não
# um novo uso. attacks_remaining ainda desconta normalmente — disparar
# consome o Action Point novo que a unidade acabou de ganhar, mesmo se o uso
# em si já foi "pago" antes.
func execute_attack_burst(attacker: Node, attack: AttackData, dir: Vector2i, slot_index: int, charge_release: bool = false) -> void:
	if attack.is_charge_move and not charge_release and not (attack.instant_in_sun and is_sun_weather()):
		# Fase de CARGA (ver AttackData.is_charge_move) — pedido do usuário:
		# "Solar Beam charges and consumes 1 action point. Then, as soon as
		# the unit has another action point, it fires". Sem Sol ativo (ou com
		# Sol mas sem instant_in_sun, embora Solar Beam sempre tenha ambos
		# juntos hoje), NÃO dispara nada agora — só guarda o golpe/direção e
		# sai. `attack.instant_in_sun and is_sun_weather()` é a ÚNICA forma de
		# pular a carga: aí cai direto pro resto da função de baixo, idêntico
		# a um golpe normal de 1 turno.
		await execute_charge_attack(attacker, attack, dir, slot_index)
		return
	if dir != Vector2i.ZERO:
		attacker.face_towards(attacker.grid_pos + dir)
	attacker.play_attack_animation(attack.is_special)
	if attack.cast_frames_by_direction != null:
		play_cast_effect(attack.cast_frames_by_direction, attacker, dir, attack.range)
	if charge_release:
		log_message("%s unleashed %s!" % [attacker.data.unit_name, attack.action_name])
	else:
		log_message("%s used %s." % [attacker.data.unit_name, attack.action_name])
	if attack.max_uses > 0 and not charge_release:
		attacker.slot_uses[slot_index] -= 1
	attacker.attacks_remaining -= 1
	refresh_action_slots_hud()
	_track_attack_use(attacker, attack)

	var hit_delay = attacker.data.special_hit_delay if attack.is_special else attacker.data.attack_hit_delay
	await get_tree().create_timer(hit_delay).timeout

	if _weather_blocks_attack(attack):
		log_message("%s's attack failed because of the weather!" % attacker.data.unit_name)
		attacker.consecutive_attack_uses = 0
		refresh_unit_summary_hud()
		check_auto_end_turn()
		return

	var final_accuracy = attack.accuracy * attacker.get_accuracy_multiplier()
	if not attack.never_misses and final_accuracy < 1.0 and randf() >= final_accuracy:
		log_message("%s's attack missed!" % attacker.data.unit_name)
		# Errou de verdade — quebra a sequência de uso consecutivo, mesma
		# regra/motivo de execute_attack (ver comentário grande lá).
		attacker.consecutive_attack_uses = 0
		refresh_unit_summary_hud()
		check_auto_end_turn()
		return

	# Geometria de quem é achado: "Burst" (raio ao redor de quem atacou,
	# Chebyshev, mesmo critério de is_valid_target_cell/get_cone_cells) ou
	# "Line" (feixe reto na direção `dir`, para em parede/borda igual
	# find_projectile_target, mas SEM parar no primeiro inimigo — pega TODO
	# MUNDO em CADA célula do caminho, ver comentário grande em
	# AttackData.area_shape). Nos dois casos, player_units/enemy_units juntos
	# cobrem os DOIS times — só a geometria decide quem é achado, não quem é
	# aliado ou inimigo de quem atacou (fogo amigo possível nos dois).
	var targets: Array[Node] = []
	if attack.area_shape == "Line":
		var cell = attacker.grid_pos
		for step in attack.range:
			var next_cell = cell + dir
			if is_wall_or_border(next_cell):
				break
			cell = next_cell
			var u = get_unit_at(cell)
			if u != null and u != attacker:
				targets.append(u)
	elif attack.area_shape == "Cone":
		# Mesma geometria de get_cone_cells que execute_status_attack já usa
		# pra Growl, só que aqui TODO MUNDO no leque conta (aliado incluso,
		# ver comentário grande em AttackData.area_shape) em vez de só
		# inimigo. Overheat é o primeiro caso.
		for cell in get_cone_cells(attacker.grid_pos, dir, attack.range):
			if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
				continue
			var u = get_unit_at(cell)
			if u != null and u != attacker and not targets.has(u):
				targets.append(u)
	elif attack.area_shape == "Wide":
		# Mesma geometria de get_wide_cells (ver AttackData.area_shape) —
		# TODO MUNDO nas 3 células (aliado incluso), Rock Slide é o primeiro
		# caso.
		for cell in get_wide_cells(attacker.grid_pos, dir, attack.range):
			if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
				continue
			var u = get_unit_at(cell)
			if u != null and u != attacker and not targets.has(u):
				targets.append(u)
	else:
		# area_min_range (ver AttackData — Eruption é o primeiro caso: "hits
		# all units on a 3 to 5 range from the user, doesnt hit units up to 2
		# range") transforma o círculo cheio de sempre (0 = padrão, começa no
		# centro) num ANEL — exclui qualquer célula com distância MENOR que
		# isso, mesmo critério Chebyshev de sempre.
		for u in player_units + enemy_units:
			if u == attacker:
				continue
			var delta = u.grid_pos - attacker.grid_pos
			var dist = max(abs(delta.x), abs(delta.y))
			if dist <= attack.range and dist >= attack.area_min_range:
				targets.append(u)

	if targets.is_empty():
		log_message("But it failed!")

	# Soma de TODO dano causado nesta rajada — só usada se
	# AttackData.self_recoil_fraction_of_damage_dealt > 0 (ver comentário
	# grande em execute_attack): um golpe Burst/Line com esse tipo de recoil
	# soma o dano de TODOS os alvos atingidos antes de tirar a fração, em vez
	# de recalcular por alvo.
	var total_damage_dealt = 0

	for target in targets:
		# Protected (ver AttackData.inflicts_status_on_self/Protect — golpe
		# QUE CAUSA DANO em área, então checa por alvo: quem está Protected
		# fica de fora por COMPLETO (nem dano, nem Flash Fire, nem
		# descongela, nem efeito secundário nenhum), mas outros alvos na
		# mesma rajada continuam sendo atingidos normalmente — Protect só
		# protege quem usou, nunca aliados por perto.
		if target.has_status("Protected"):
			log_message("%s protected itself!" % target.data.unit_name)
			continue

		if attack.element_type == "Fire" and has_flash_fire(target) and target.apply_status_condition("Charged"):
			log_message("%s's Flash Fire was triggered!" % target.data.unit_name)

		if target.has_status("Frozen") and attack.element_type == "Fire":
			target.cure_status_condition("Frozen")
			log_message("%s thawed out!" % target.data.unit_name)

		target.face_towards(attacker.grid_pos)
		target.play_hurt_animation()
		if attack.impact_texture != null or attack.impact_texture_2 != null or not attack.impact_frames.is_empty():
			play_impact_effect(attack.impact_texture, target.position, attack.impact_texture_2, attack.impact_frames)

		if target.has_status("Asleep"):
			target.cure_status_condition("Asleep")

		# Mesma troca de get_effective_crit_chance() do ramo de alvo único
		# em execute_attack (ver comentário lá) — `attacker` passado também
		# aqui pra Focus Energy (Beedrill) valer em golpes Burst/Line.
		var is_critical = randf() < get_effective_crit_chance(attack, attacker)
		var damage = calculate_damage(attacker, target, attack, is_critical)
		# hp_lost em vez de `damage` cru — mesmo bug de overkill do
		# comentário grande em execute_attack (Typhlosion nível 100 batendo
		# 1000+ num alvo de 10 HP não devia gerar recoil de 1000).
		total_damage_dealt += min(damage, target.hp_current)
		target.take_damage(damage)
		# Run Away — mesmo mecanismo do ramo de alvo único em execute_attack
		# (ver comentário grande lá), aplicado por ALVO dentro da rajada.
		_try_run_away(target, attacker)
		if attack.element_type == "Fire" and attacker.has_status("Charged") and has_flash_fire(attacker):
			attacker.cure_status_condition("Charged")
		if is_critical:
			log_message("A critical hit!")

		var effectiveness = get_weather_adjusted_effectiveness(attack.element_type, target)
		if effectiveness == 0.0 or has_type_immunity_ability(target, attack.element_type):
			log_message("It had no effect on %s!" % target.data.unit_name)
		elif effectiveness > 1.0:
			log_message("It's super effective on %s!" % target.data.unit_name)
		elif effectiveness < 1.0:
			log_message("It's not very effective on %s..." % target.data.unit_name)

		if not has_sheer_force(attacker) and target.hp_current > 0:
			_try_apply_secondary_status(target, attack.secondary_status, attack.secondary_status_chance, attack.secondary_status_texture)
			_try_apply_secondary_status(target, attack.secondary_status_2, attack.secondary_status_chance_2, attack.secondary_status_texture_2)
			_try_apply_secondary_stat_change(target, attack)
		# Bug Bite — ver comentário grande no ramo de alvo único (execute_attack).
		if target.hp_current > 0:
			_try_bug_bite_steal_berry(attacker, target, attack)

		if target.hp_current <= 0:
			log_message("%s was defeated!" % target.data.unit_name)
			award_experience(attacker, target)
			remove_defeated_unit(target)
			_apply_challenge_permadeath(target)
			if enemy_units.is_empty() or player_units.is_empty():
				# Batalha acabou NO MEIO da rajada — para de processar o resto
				# dos alvos (units já saindo da árvore, ver end_battle) e nem
				# tenta boost/recoil/HUD depois disso.
				await end_battle(target, enemy_units.is_empty())
				return

	# Boost de stat no próprio atacante (mesmo par de campos/ordem de
	# execute_attack — ver comentário grande lá) roda UMA VEZ SÓ pro golpe
	# inteiro, depois de resolver todos os alvos, nunca por alvo (senão um
	# Burst com 3 alvos triplicaria o boost).
	if not has_sheer_force(attacker):
		_try_apply_self_stat_boost(attacker, attack)
		if attack.stat_change_target == "Self" and attack.stat_change_stat != "":
			apply_stat_change(attacker, attack.stat_change_stat, attack.stat_change_amount)

	# Recoil (ver comentário grande em execute_attack) — mesma regra, UMA VEZ
	# só pro golpe inteiro, não por alvo atingido. self_recoil_fraction_of_
	# damage_dealt usa total_damage_dealt (soma de TODOS os alvos da rajada),
	# não o dano de um alvo só.
	var recoil_fraction = attack.self_max_hp_recoil_fraction
	var recoil_base = float(attacker.hp_max)
	if attack.self_recoil_fraction_of_damage_dealt > 0.0:
		recoil_fraction = attack.self_recoil_fraction_of_damage_dealt
		recoil_base = float(total_damage_dealt)
	if recoil_fraction > 0.0:
		var recoil_damage = max(1, int(round(recoil_base * recoil_fraction)))
		attacker.take_damage(recoil_damage)
		log_message("%s is damaged by recoil!" % attacker.data.unit_name)
		if attacker.hp_current <= 0:
			log_message("%s fainted from recoil!" % attacker.data.unit_name)
			remove_defeated_unit(attacker)
			_apply_challenge_permadeath(attacker)
			if enemy_units.is_empty() or player_units.is_empty():
				await end_battle(attacker, enemy_units.is_empty())
			else:
				call_deferred("begin_current_turn")
			return

	refresh_unit_summary_hud()
	check_auto_end_turn()

# Uma rolagem de efeito secundário (ver os dois usos em execute_attack, um
# pra secondary_status/chance/texture e outro pro par "_2") — extraído pra
# não duplicar a mesma checagem duas vezes. status == "" (ataque sem esse
# efeito, ou sem o segundo) sai de cara sem rolar nada.
# apply_status_condition() devolve false sozinha se o alvo já tiver ESSA
# MESMA condição ativa (ver comentário lá — condições diferentes agora
# empilham normalmente), então a mensagem/animação só toca quando a
# condição realmente "pegou".
func _try_apply_secondary_status(defender: Node, status: String, chance: float, texture: Texture2D) -> void:
	if status == "" or randf() >= chance:
		return
	# Shield Dust (ver AbilityData.shield_dust, pedido do usuário, 2026-07-23,
	# Caterpie: "Immune to secondary effects of opponent's attacks") — cancela
	# o efeito secundário por completo pra quem DEFENDE, sem cancelar o dano
	# principal (já aplicado antes de chegar aqui, ver execute_attack/
	# execute_attack_burst). Silencioso, sem mensagem própria — mesmo
	# tratamento de "não pegou" que Powder->Grass/Sunny->Frozen já usam acima.
	if has_shield_dust(defender):
		return
	# Sunny/Harsh Sunlight: ninguém pega Frozen (regra oficial desde a Gen 6
	# — pedido do usuário: "Units can't be frozen"). Silencioso, sem
	# mensagem própria — mesmo tratamento de qualquer outra tentativa de
	# status que "não pega" por algum motivo (ver Unit.is_immune_to_status,
	# mesma ideia, só que a condição aqui depende do CLIMA, não do tipo da
	# unidade, por isso mora em battle.gd em vez de unit.gd).
	if status == "Frozen" and (current_weather == WEATHER_SUNNY or current_weather == WEATHER_HARSH_SUNLIGHT):
		return
	if defender.apply_status_condition(status):
		log_message("%s was %s!" % [defender.data.unit_name, status])
		if texture != null:
			play_impact_effect(texture, defender.position)

# Efeito secundário de AttackData.secondary_stat_change_stat/_amount/_chance
# (ver comentário grande lá — Rock Smash é o primeiro caso: "50% chance to
# lower Defense"). stat == "" sai de cara sem rolar nada (nenhum golpe sem
# esse efeito paga custo de randf() à toa). Reaproveita apply_stat_change()
# de novo (mesma função/efeito visual de Growl/Ancient Power/Flame Charge) —
# ela já cuida sozinha da mensagem "won't go any lower/higher" se o estágio
# já estiver no limite, então não precisa de tratamento especial aqui.
func _try_apply_secondary_stat_change(defender: Node, attack: AttackData) -> void:
	if attack.secondary_stat_change_stat == "" or randf() >= attack.secondary_stat_change_chance:
		return
	# Shield Dust — ver comentário grande em _try_apply_secondary_status acima,
	# mesma regra, mesmo mecanismo de defesa.
	if has_shield_dust(defender):
		return
	apply_stat_change(defender, attack.secondary_stat_change_stat, attack.secondary_stat_change_amount)

# Efeito secundário de AttackData.self_stat_boost_chance/_amount (ex: Ancient
# Power) — diferente de _try_apply_secondary_status acima (1 status, no
# defensor), aqui é SEMPRE os 5 stats de UnitScript.STAGE_STATS juntos, no
# próprio atacante. Reaproveita apply_stat_change() (mesma função/efeito
# visual que Growl já usa pra baixar Attack do inimigo) 5 vezes seguidas —
# cada stat loga/anima separado, mesmo estilo de "Attack rose! Defense
# rose!..." dos jogos originais.
func _try_apply_self_stat_boost(attacker: Node, attack: AttackData) -> void:
	if attack.self_stat_boost_amount == 0 or randf() >= attack.self_stat_boost_chance:
		return
	for stat in UnitScript.STAGE_STATS:
		apply_stat_change(attacker, stat, attack.self_stat_boost_amount)

# Bug Bite (ver AttackData.steals_target_berry, pedido do usuário, 2026-07-23,
# Caterpie: "If the target has a Berry, consume the berry and gain its
# effects. If there are more than one berry, consume a random one") — só
# chamado se `defender` sobreviveu ao golpe (mesmo critério de secondary
# effects). Procura TODOS os slots category=="Berry" no loadout do defensor,
# sorteia um se houver mais de um, e aplica o efeito em quem ATACA (não no
# defensor, que é quem perde a Berry) — hoje só existe efeito de cura (ver
# ItemData.heal_amount, Oran Berry), mas o mecanismo já lê genericamente
# "o que essa Berry faz", então uma Berry futura com outro efeito funcionaria
# sem precisar mexer aqui de novo. Remove a Berry do slot do defensor (mesmo
# padrão de Unit._check_berry_auto_use — slots[i]=null, slot_uses[i]=0).
func _try_bug_bite_steal_berry(attacker: Node, defender: Node, attack: AttackData) -> void:
	if not attack.steals_target_berry or defender.data == null:
		return
	var berry_indices: Array[int] = []
	for i in defender.data.slots.size():
		var item = defender.data.slots[i]
		if item is ItemData and item.category == "Berry":
			berry_indices.append(i)
	if berry_indices.is_empty():
		return
	var chosen_index: int = berry_indices[randi() % berry_indices.size()]
	var berry: ItemData = defender.data.slots[chosen_index]
	defender.data.slots[chosen_index] = null
	if chosen_index < defender.slot_uses.size():
		defender.slot_uses[chosen_index] = 0
	if berry.heal_amount > 0:
		attacker.hp_current = min(attacker.hp_current + berry.heal_amount, attacker.hp_max)
		attacker.update_health_bar()
		attacker.sync_to_data()
	log_message("%s stole and ate %s's %s!" % [attacker.data.unit_name, defender.data.unit_name, berry.action_name])

# Ataque de STATUS (ver AttackData.is_status): NÃO causa dano nenhum — só
# aplica stat_change_stat/_amount em cada INIMIGO encontrado dentro da área
# (Single = só a célula mirada; Cone = o leque inteiro, ver get_cone_cells).
# Estrutura parecida com execute_attack (delay, animação, consumo de uso),
# mas separada de propósito: aqui a lista de alvos só existe DEPOIS de
# calcular a geometria da área, então não dá pra reaproveitar a assinatura
# "1 defender só" de execute_attack — e mesmo se desse, calculate_damage()
# nunca devolve 0 (piso de 1, ver comentário lá), então um Ataque de Status
# passando por ali causaria dano por engano.
#
# `dir` já vem pronto de quem chama (handle_targeting_input calcula do clique
# do jogador; run_enemy_turn, da posição do aliado escolhido pela IA) — mesma
# convenção 8-way de sign(delta) usada no resto do jogo.
# Frase de efeito por status auto-aplicado (ver AttackData.inflicts_status_on_
# self) — pedido do usuário (2026-07-23) especificamente pra Aqua Ring, que
# antes reusava a frase do Protect ("protected itself") sem fazer sentido
# nenhum pra um golpe de cura, não de imunidade. Chave ausente (qualquer
# self-status futuro sem entrada própria aqui) cai no fallback genérico do
# Protect em vez de quebrar.
const SELF_STATUS_EFFECT_MESSAGES := {
	"Protected": "%s protected itself!",
	"Aqua Ring": "%s is enveloped by a veil of water!",
	"Focus Energy": "%s is getting pumped!",
}

# Mesma ideia de SELF_STATUS_EFFECT_MESSAGES acima, só que pro caso de um
# status aplicado em MÚLTIPLOS alvos de uma vez via inflicts_status (ver o
# ramo final de execute_status_attack) — "%s was %s!" (o padrão de sempre, ex:
# "Caterpie was Poisoned!") lê mal pra status com nome que não é adjetivo.
# Entradas com só 1 "%s" usam só o nome da unidade; com 2, nome + status (ver
# ponto de uso). Safeguarded/Tailwind/Taunted são os primeiros casos.
const GROUP_STATUS_EFFECT_MESSAGES := {
	"Safeguarded": "%s is protected by the Safeguard!",
	"Tailwind": "%s got a burst of speed from the Tailwind!",
	"Taunted": "%s fell for the taunt!",
}

# Wonder Skin (ver AbilityData.wonder_skin/has_wonder_skin) — precisa saber
# ANTES do roll de acerto (rodado logo no início de execute_status_attack,
# antes de `targets` ser resolvido de verdade mais abaixo na função) se
# QUALQUER inimigo na área deste golpe de Status carrega a Habilidade, pra
# cortar a accuracy pela metade só nesse caso. Reconstrói uma versão
# RESUMIDA da MESMA geometria que o bloco "var targets" mais abaixo calcula
# (Cone/Burst/projétil/Single) — duplicado de propósito em vez de mover
# aquele bloco (já testado, cheio de comentário) pra cima do roll: mais
# seguro reimplementar só a checagem de Habilidade aqui do que reordenar
# tudo perto do prazo. "Team"/self-target/sets_weather nunca miram inimigo
# nenhum, então nem entram na checagem (Wonder Skin só importa pra golpe que
# afeta INIMIGOS de quem usa).
func _status_move_hits_wonder_skin(attacker: Node, attack: AttackData, dir: Vector2i) -> bool:
	if attack.area_shape == "Cone":
		for cell in get_cone_cells(attacker.grid_pos, dir, attack.range):
			if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
				continue
			var u = get_unit_at(cell)
			if u != null and u.is_enemy != attacker.is_enemy and has_wonder_skin(u):
				return true
		return false
	if attack.area_shape == "Burst" and not attack.targets_allies:
		for u in player_units + enemy_units:
			if u == attacker or u.is_enemy == attacker.is_enemy:
				continue
			var delta = u.grid_pos - attacker.grid_pos
			var dist = max(abs(delta.x), abs(delta.y))
			if dist <= attack.range and dist >= attack.area_min_range and has_wonder_skin(u):
				return true
		return false
	if attack.is_projectile:
		var cell = attacker.grid_pos
		for step in attack.range:
			var next_cell = cell + dir
			if is_wall_or_border(next_cell):
				break
			cell = next_cell
			var u = get_unit_at(cell)
			if u != null and u.is_enemy != attacker.is_enemy:
				return has_wonder_skin(u)
		return false
	if attack.area_shape == "Single":
		var cell = attacker.grid_pos + dir * attack.range
		if cell.x >= 0 and cell.x < MAP_WIDTH and cell.y >= 0 and cell.y < MAP_HEIGHT:
			var u = get_unit_at(cell)
			if u != null and u.is_enemy != attacker.is_enemy:
				return has_wonder_skin(u)
	return false

func execute_status_attack(attacker: Node, attack: AttackData, dir: Vector2i, slot_index: int) -> void:
	attacker.face_towards(attacker.grid_pos + dir)
	# SEMPRE a animação "especial" (shoot_<dir>, ou charge_<dir> se a espécie
	# não tiver shoot — ver Unit.play_attack_animation) pra ataque de Status,
	# nunca attack_<dir> — pedido do usuário: "Use the special animation for
	# status moves (either shoot or charge)". attack.is_special É irrelevante
	# pra Status (ver comentário grande em AttackData.is_status), então usar
	# ele aqui era só coincidência: Growl (is_special=true) já saía certo,
	# mas Sunny Day/Rain Dance (is_special=false, o padrão) tocariam
	# attack_<dir> por engano sem essa troca pra `true` fixo.
	attacker.play_attack_animation(true)
	# Cast effect (ver AttackData.cast_frames_by_direction) — Growl é o
	# primeiro caso: a onda sonora saindo do próprio usuário do ataque, 1
	# tile à frente, viajando até `attack.range`. Aqui já temos `dir` pronto
	# (é literalmente pra que serve esse parâmetro), não precisa reconstruir
	# de attacker.facing como execute_attack faz.
	if attack.cast_frames_by_direction != null:
		play_cast_effect(attack.cast_frames_by_direction, attacker, dir, attack.range)
	log_message("%s used %s." % [attacker.data.unit_name, attack.action_name])
	if attack.max_uses > 0:
		attacker.slot_uses[slot_index] -= 1
	attacker.attacks_remaining -= 1
	refresh_action_slots_hud()
	_track_attack_use(attacker, attack)

	var hit_delay = attacker.data.special_hit_delay if attack.is_special else attacker.data.attack_hit_delay
	await get_tree().create_timer(hit_delay).timeout

	# Roll de acerto — pedido do usuário (2026-07-22): "We need to implement
	# accuracy checks for status moves, it makes no sense no having them".
	# Até aqui, execute_status_attack não tinha roll NENHUM: todo ataque de
	# Status sempre acertava, não importa o que AttackData.accuracy dissesse
	# (o campo existia mas nunca era lido aqui). Mesmo formato do roll de
	# execute_attack (ver comentário grande lá): usa attacker.
	# get_accuracy_multiplier() (Focus Band, Blind), respeita never_misses,
	# e accuracy == 1.0 (padrão de AttackData) pula o randf() de propósito —
	# ou seja, golpes que NUNCA setaram accuracy (Growl, Smokescreen, Defense
	# Curl, Sunny Day, Growth...) continuam 100% garantidos, exatamente como
	# se comportavam antes desta mudança; só quem realmente tem um accuracy
	# < 1.0 (Poison Powder/Sleep Powder a 0.75, Leech Seed a 0.9 — os .tres
	# foram atualizados junto com esta mudança) passa a poder falhar de
	# verdade agora. Mesma quebra de sequência de uso consecutivo do miss de
	# execute_attack (ver Unit.consecutive_attack_uses) — nenhum golpe de
	# Status usa scales_with_consecutive_use hoje, mas mantém os dois
	# caminhos consistentes caso um dia algum use.
	var final_accuracy = attack.accuracy * attacker.get_accuracy_multiplier()
	# Wonder Skin (ver AbilityData.wonder_skin, pedido do usuário, Venomoth
	# Hidden: "All enemy Status moves targeted at this unit have Accuracy
	# x0.5") — checado ANTES de resolver `targets` de verdade (ver comentário
	# grande de _status_move_hits_wonder_skin sobre por que essa checagem é
	# duplicada em vez de mover o bloco de `targets` pra cima do roll).
	if _status_move_hits_wonder_skin(attacker, attack, dir):
		final_accuracy *= 0.5
	# Toxic (ver AttackData.never_misses_if_user_type, pedido do usuário:
	# "Never misses if user is Poison type") — condicional ao TIPO de quem
	# ataca, diferente de never_misses (incondicional, ver Swift). Os dois se
	# somam no "pula o roll" (um golpe poderia ter os dois, embora nenhum hoje
	# tenha).
	var skips_accuracy_roll = attack.never_misses or (attack.never_misses_if_user_type != "" and attacker.data.types.has(attack.never_misses_if_user_type))
	if not skips_accuracy_roll and final_accuracy < 1.0 and randf() >= final_accuracy:
		# Pedido do usuário (2026-07-23): "On self cast status move fail,
		# message should be 'But it failed!'" — golpe auto-mirado (Protect,
		# Aqua Ring, ver is_self_target_status) não "erra" um alvo, ele só não
		# consegue se aplicar, então a frase de falha certa é a mesma usada em
		# qualquer outro "não fez nada" (HP cheio, já Protected, etc.), não
		# "attack missed" (que soa como um golpe indo pro alvo errado — só faz
		# sentido pra golpe de Status mirado em INIMIGO, ex: Growl, Poison
		# Powder).
		if is_self_target_status(attack):
			log_message("But it failed!")
		else:
			log_message("%s's attack missed!" % attacker.data.unit_name)
		attacker.consecutive_attack_uses = 0
		refresh_unit_summary_hud()
		check_auto_end_turn()
		return

	# Whirlwind (ver AttackData.push_mechanic/execute_whirlwind_push) — geometria
	# e efeito TOTALMENTE diferentes do resto desta função (empurra em vez de
	# aplicar stat/status/clima), então sai cedo daqui, ANTES de montar
	# `targets` (que nem faz sentido pra este golpe — a área de quem é
	# empurrado é resolvida dentro da própria execute_whirlwind_push, incluindo
	# aliados, que os ramos abaixo excluem de propósito).
	if attack.push_mechanic:
		# execute_whirlwind_push devolve true se a batalha JÁ acabou dentro
		# dela (ver comentário grande lá) — bug reportado pelo usuário: o jogo
		# travava quando o último inimigo morria de dano de colisão/parede do
		# empurrão, porque check_auto_end_turn() ainda rodava DEPOIS de
		# end_battle() já ter encerrado tudo (mesma classe de bug que
		# execute_attack/execute_attack_burst já evitam com um `return` logo
		# depois do `await end_battle(...)`, ver comentário lá — só que aqui
		# quem decide "a batalha acabou" é a função de baixo, não este ponto,
		# então precisa devolver isso pra quem chamou saber).
		var battle_ended = await execute_whirlwind_push(attacker, dir)
		if battle_ended:
			return
		refresh_unit_summary_hud()
		check_auto_end_turn()
		return

	# Bug corrigido aqui: um ternário com Array[Vector2i] de um lado (retorno
	# de get_cone_cells) e um literal `[...]` cru do outro CRASHAVA em
	# runtime ("Trying to assign an array of type 'Array' to a variable of
	# type 'Array[Vector2i]'") — literal de array dentro de expressão sai
	# SEM tipo (Array genérico), e GDScript recusa atribuir isso a uma
	# variável tipada, mesmo dentro do braço "else" nunca escolhido pro caso
	# Cone. Nunca disparava antes porque Growl (o único ataque de Status até
	# então) é sempre "Cone" — Sunny Day foi o primeiro "Single", que cai
	# bem nesse branch. if/else normal em vez de ternário evita o problema
	# (mesmo truque já usado em game_state.gd::extra_loadout, ver comentário
	# lá sobre o mesmo erro com Array[ActionData]).
	var targets: Array[Node] = []
	if attack.area_shape == "Cone":
		for cell in get_cone_cells(attacker.grid_pos, dir, attack.range):
			if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
				continue
			var u = get_unit_at(cell)
			if u != null and u.is_enemy != attacker.is_enemy and not targets.has(u):
				targets.append(u)
	elif attack.area_shape == "Burst":
		# Poison Powder/Sleep Powder são o primeiro caso de Burst num
		# ataque de STATUS — pedido do usuário: "all enemies in 1 range
		# area... Doesnt affect... allies". Mesma varredura por DISTÂNCIA
		# (Chebyshev) que execute_attack_burst já usa pro Burst de DANO
		# (Lava Plume etc.), só que aqui `u.is_enemy == attacker.is_enemy`
		# já pula fora de cara — diferente do Burst de dano, que acerta
		# todo mundo (aliado incluso) de propósito, este só mira inimigo,
		# igual Cone/is_projectile/Single logo abaixo. area_min_range (ver
		# AttackData) continua funcionando igual, viraria anel se algum
		# golpe de Status precisar no futuro, embora nenhum hoje use isso.
		#
		# targets_allies (ver AttackData — Safeguard é o primeiro caso: "All
		# allies in burst range 3 gain Safeguard status") INVERTE o filtro:
		# em vez de pular quem é do MESMO lado, pula quem é do lado OPOSTO —
		# e, diferente do ramo de inimigo, quem USA o golpe também entra (é
		# um efeito de proteção do próprio time, faz sentido incluir quem
		# lançou também).
		for u in player_units + enemy_units:
			if attack.targets_allies:
				if u.is_enemy != attacker.is_enemy:
					continue
			else:
				if u == attacker or u.is_enemy == attacker.is_enemy:
					continue
			var delta = u.grid_pos - attacker.grid_pos
			var dist = max(abs(delta.x), abs(delta.y))
			if dist <= attack.range and dist >= attack.area_min_range:
				targets.append(u)
	elif attack.area_shape == "Team":
		# Tailwind é o primeiro caso: "All allies gain Tailwind Status" — SEM
		# número de alcance nenhum dado (diferente de Safeguard, que ganhou
		# "burst range 3" explícito), lido como "o time inteiro, não importa a
		# posição" (ver comentário grande de area_shape=="Team" em
		# attack_data.gd). Inclui quem usa, mesmo espírito de targets_allies
		# acima.
		for u in player_units + enemy_units:
			if u.is_enemy == attacker.is_enemy:
				targets.append(u)
	elif attack.is_projectile:
		# Status "de projétil" (ex: Smokescreen: "single target, 2 range,
		# stops at first enemy hit") — mesmo espírito de find_projectile_target
		# (usado por execute_attack pra ataque QUE CAUSA DANO), mas não dá pra
		# reaproveitar aquela função direto: ela recebe um `target` (célula) e
		# DERIVA a direção com sign(delta), enquanto aqui `dir` já vem pronto
		# (mesmo motivo de play_cast_effect não precisar reconstruir direção,
		# ver comentário acima). Passo a passo, célula por célula, até
		# attack.range OU até esbarrar em parede/borda — para no PRIMEIRO
		# inimigo encontrado no caminho, sem precisar estar exatamente na
		# última célula (diferente do "Single" parado logo abaixo).
		var cell = attacker.grid_pos
		for step in attack.range:
			var next_cell = cell + dir
			if is_wall_or_border(next_cell):
				break
			cell = next_cell
			var u = get_unit_at(cell)
			if u != null and u.is_enemy != attacker.is_enemy:
				targets.append(u)
				break
	else:
		var cell = attacker.grid_pos + dir * attack.range
		if cell.x >= 0 and cell.x < MAP_WIDTH and cell.y >= 0 and cell.y < MAP_HEIGHT:
			var u = get_unit_at(cell)
			if u != null and u.is_enemy != attacker.is_enemy:
				targets.append(u)

	# self_heal_fraction (ver AttackData — Synthesis é o primeiro caso): cura
	# QUEM ATACA em vez de mirar em qualquer coisa, mesmo espírito de
	# stat_change_target=="Self" logo abaixo (por isso vem ANTES, como o
	# primeiro elo da mesma cadeia `if/elif` — os quatro casos são mutuamente
	# exclusivos na prática, nenhum golpe hoje combina cura com mudança de
	# stat/clima). "But it failed!" se quem usa já estiver com HP cheio,
	# mesmo critério de "não fez nada de verdade" usado noutros lugares.
	if attack.self_heal_fraction > 0.0:
		if attacker.hp_current >= attacker.hp_max:
			log_message("But it failed!")
		else:
			var heal_fraction = get_effective_self_heal_fraction(attack)
			var heal_amount = int(round(attacker.hp_max * heal_fraction))
			attacker.hp_current = min(attacker.hp_current + heal_amount, attacker.hp_max)
			attacker.update_health_bar()
			attacker.sync_to_data()
			log_message("%s's HP was restored!" % attacker.data.unit_name)
	# stat_change_target == "Self" (ver AttackData — Defense Curl é o primeiro
	# caso) NUNCA "falha" por falta de alvo, mesmo espírito de sets_weather
	# logo abaixo: aplica em QUEM ATACA direto, sem passar pela busca de
	# inimigo em area_cells/targets nenhuma (por isso vem ANTES, com `elif`
	# encadeado — as três condições são mutuamente exclusivas na prática, já
	# que nenhum golpe hoje combina Self com sets_weather).
	elif attack.stat_change_target == "Self" and attack.stat_change_stat != "":
		# stat_change_doubles_in_sun (ver AttackData — Growth é o primeiro
		# caso): dobra os DOIS valores juntos, não só o primeiro — o roll de
		# clima é lido UMA vez aqui, antes de aplicar qualquer um dos dois,
		# pra não arriscar o clima mudar (ex: sandstorm/rain_dance disparado
		# por outro efeito no meio do caminho, embora nada hoje faça isso no
		# meio de execute_status_attack) entre o primeiro e o segundo stat.
		var amount_1 = attack.stat_change_amount
		var amount_2 = attack.stat_change_amount_2
		if attack.stat_change_doubles_in_sun and is_sun_weather():
			amount_1 *= 2
			amount_2 *= 2
		apply_stat_change(attacker, attack.stat_change_stat, amount_1)
		# stat_change_stat_2 (ver AttackData — Growth de novo): segundo stat
		# opcional, SEMPRE no mesmo alvo (Self) que o primeiro — não existe
		# golpe hoje que precise de alvos diferentes pros dois.
		if attack.stat_change_stat_2 != "":
			apply_stat_change(attacker, attack.stat_change_stat_2, amount_2)
		# stat_change_stat_3 (ver AttackData — Quiver Dance é o primeiro caso:
		# Special Attack/Special Defense/Speed, os três de uma vez) — sem
		# stat_change_doubles_in_sun aplicado a ele (nenhum golpe hoje precisa),
		# mas nada impede um futuro golpe de setar os três campos se precisar.
		if attack.stat_change_stat_3 != "":
			apply_stat_change(attacker, attack.stat_change_stat_3, attack.stat_change_amount_3)
	# inflicts_status_on_self (ver AttackData — Protect é o primeiro caso):
	# aplica AttackData.inflicts_status (reaproveitado — mesmo campo/textura
	# que os golpes de status "pra inimigo" já usam, só que aqui o alvo é
	# QUEM ATACA) direto no attacker, sem passar pela busca de inimigo em
	# targets — mesmo espírito de self_heal_fraction/stat_change_target==
	# "Self" logo acima. "But it failed!" se apply_status_condition()
	# devolver false (ex: já estar Protected de um uso anterior que ainda
	# não expirou — não deveria rolar hoje já que Protected sempre cura no
	# início do próximo turno, mas o guard existe do mesmo jeito que Synthesis
	# guarda "já com HP cheio").
	elif attack.inflicts_status_on_self and attack.inflicts_status != "":
		if attacker.apply_status_condition(attack.inflicts_status):
			# Mensagem de EFEITO varia por condição (pedido do usuário, 2026-07-23:
			# "Aqua ring message is wrong. It should say 'UNITNAME used Aqua Ring.
			# UNITNAME is enveloped by a veil of water'") — o "X used Y." já sai
			# sozinho lá em cima (início da função), então só falta a frase de
			# efeito por baixo, uma por status (SELF_STATUS_EFFECT_MESSAGES),
			# com "%s protegeu a si mesmo" como fallback genérico pra qualquer
			# futuro self-status que não tenha entrada própria aqui.
			var effect_msg: String = SELF_STATUS_EFFECT_MESSAGES.get(attack.inflicts_status, "%s protected itself!")
			log_message(effect_msg % attacker.data.unit_name)
		else:
			log_message("But it failed!")
	elif attack.sets_weather != "":
		await try_set_weather(attack.sets_weather, attacker)
	elif targets.is_empty():
		log_message("But it failed!")
	for target in targets:
		# "Powder" (ver AttackData.tags — Poison Powder/Sleep Powder são o
		# primeiro caso): pedido do usuário, "Doesnt affect grass types".
		# Regra oficial da série principal é por CATEGORIA DO GOLPE (golpes
		# de pó — Stun Spore, Spore, etc. também seriam), não por Status
		# Condition em si (Toxic/Hypnosis não são pó e AINDA afetam Grass
		# normalmente) — por isso mora aqui como uma checagem de tag, não em
		# Unit.STATUS_TYPE_IMMUNITIES (que travaria TODO Poisoned/Asleep,
		# pó ou não, pra sempre). `continue` pula o alvo por COMPLETO (nem
		# stat_change nem inflicts_status pegam nele), igual a série
		# principal faz — mas o alvo ainda CONTA como atingido pra fins de
		# geometria (ver targets acima: um projétil de pó ainda para no
		# primeiro inimigo do caminho, mesmo sendo Grass e imune), só o
		# efeito que não acontece, sem mensagem própria (mesmo tratamento
		# silencioso de "não pegou" que Frozen+Sol já usa, ver
		# _try_apply_secondary_status).
		if attack.tags.has("Powder") and target.data.types.has("Grass"):
			continue
		# Protected (ver AttackData.inflicts_status_on_self/Protect): bloqueia
		# golpe de Status igual bloqueia dano — mesma mensagem/`continue` do
		# ramo Powder logo acima, só que aqui vale pra QUALQUER golpe de
		# Status mirado num inimigo (Growl, Poison Powder, Leech Seed, etc.).
		if target.has_status("Protected"):
			log_message("%s protected itself!" % target.data.unit_name)
			continue
		# Disable (ver AttackData.disables_target_last_move, pedido do
		# usuário, Venonat: "Opponent gets Disabled status. It saves the
		# targets last used move and disables it for 3 turns") — `continue`
		# no final porque este golpe NÃO aplica stat_change/inflicts_status
		# genérico nenhum, é um efeito totalmente à parte.
		if attack.disables_target_last_move:
			if target.last_attack_used == null or not target.apply_status_condition("Disabled", attacker):
				log_message("But it failed!")
			else:
				target.disabled_attack = target.last_attack_used
				log_message("%s's %s was disabled!" % [target.data.unit_name, target.disabled_attack.action_name])
			continue
		# Worry Seed (ver AttackData.replaces_target_ability, pedido do
		# usuário: "IF opponent has an ability in its loadout, choose a random
		# one to replace with Insomnia") — mesmo `continue` isolado de Disable
		# acima, efeito totalmente à parte do stat_change/inflicts_status
		# genérico.
		if attack.replaces_target_ability:
			var ability_indices: Array[int] = []
			for i in target.data.slots.size():
				if target.data.slots[i] is AbilityData:
					ability_indices.append(i)
			if ability_indices.is_empty():
				log_message("But it failed!")
			else:
				var chosen_index: int = ability_indices[randi() % ability_indices.size()]
				target.data.slots[chosen_index] = INSOMNIA_ABILITY
				log_message("%s's Ability was replaced with Insomnia!" % target.data.unit_name)
			continue
		if attack.stat_change_target != "Self":
			apply_stat_change(target, attack.stat_change_stat, attack.stat_change_amount)
			# stat_change_stat_2 (ver AttackData — até aqui só lido no ramo
			# "Self", ver Growth/Quiver Dance acima) — Toxic é o primeiro golpe
			# a precisar de DOIS stats mudados no ALVO (não em quem ataca):
			# "Poisons target and reduces Defense and Sp.Def by 1".
			if attack.stat_change_stat_2 != "":
				apply_stat_change(target, attack.stat_change_stat_2, attack.stat_change_amount_2)
		# Igual stat_change_stat acima: SEM chance nenhuma, sempre aplica se
		# achou o alvo (ver comentário grande em AttackData.inflicts_status
		# sobre por que isso é diferente de secondary_status). apply_status_
		# condition() já recusa sozinha se o alvo já tiver ESSA MESMA
		# condição ativa (ver comentário dela), então isso pode "tentar" sem
		# problema mesmo num alvo já Blind/Poisoned/etc — condições
		# DIFERENTES empilham (ex: Smokescreen ainda cega um alvo já
		# Poisoned), só a repetida é que não pega de novo.
		# `attacker` como source (ver Unit.apply_status_condition/status_source)
		# — a maioria das condições ignora isso, mas Seeded (Leech Seed)
		# precisa saber quem curar no tick de fim de turno (ver
		# get_seeded_tick_damage/_apply_leech_seed_heal mais abaixo).
		if attack.inflicts_status != "" and target.apply_status_condition(attack.inflicts_status, attacker):
			# GROUP_STATUS_EFFECT_MESSAGES (ver constante logo abaixo desta
			# função): "%s was %s!" lê estranho pra status que não são
			# adjetivos (ex: "Caterpie was Safeguard!"/"Caterpie was
			# Tailwind!") — mesmo espírito de SELF_STATUS_EFFECT_MESSAGES lá em
			# cima (Aqua Ring), só que pro caso de MÚLTIPLOS alvos (Safeguard/
			# Tailwind/Taunt), não auto-aplicado.
			var effect_msg: String = GROUP_STATUS_EFFECT_MESSAGES.get(attack.inflicts_status, "%s was %s!")
			if effect_msg.count("%s") == 2:
				log_message(effect_msg % [target.data.unit_name, attack.inflicts_status])
			else:
				log_message(effect_msg % target.data.unit_name)
			if attack.inflicts_status_texture != null:
				play_impact_effect(attack.inflicts_status_texture, target.position)

	refresh_unit_summary_hud()
	check_auto_end_turn()

# Whirlwind (ver AttackData.push_mechanic, pedido do usuário, 2026-07-23,
# Butterfree: "Pushes all units in rock slide range (3 tiles range 1) a
# number of tiles equal to 5-target's weight. If they would go through a
# wall, they stop and take 5*their weight as damage. If unit A would go
# through unit B, unit A stops before unit B and takes B's weight * 5, while B
# takes A's weight * 5"). Reaproveita get_wide_cells (mesma geometria de Rock
# Slide) pra achar quem é empurrado, SEM o filtro "só inimigo" — atinge TODO
# MUNDO (aliado e inimigo) na área, mesma regra de "sem isenção de fogo amigo"
# de qualquer área de dano (Cone/Burst/Line/Wide).
#
# Cada unidade atingida empurra na MESMA direção `dir` (continuação da mira,
# afastando de quem usou) por `5 - peso` tiles, andando célula por célula:
# - Esbarrou em parede/borda: para ali, toma 5*PRÓPRIO peso de dano.
# - Esbarrou em outra unidade: para ANTES dela (não entra na mesma célula),
#   as DUAS tomam dano (quem foi empurrada toma 5*peso de quem já estava lá,
#   quem já estava lá toma 5*peso de quem foi empurrada) — nenhuma das duas
#   se move além disso, mesmo que sobrasse "distância" de empurrão.
# - Terminou o empurrão inteiro sem esbarrar em nada: só reposiciona, sem
#   dano nenhum.
# As 3 células de get_wide_cells ficam lado a lado (perpendiculares à direção
# mirada), nunca na mesma "linha" de empurrão umas das outras — por isso não
# precisa se preocupar com a ordem de processamento entre elas (uma não
# atravessa o caminho da outra).
#
# Devolve true se a batalha já acabou dentro desta função (ver comentário no
# ponto de chamada, execute_status_attack::push_mechanic) — igual todo outro
# lugar que mata unidade em battle.gd, chama end_battle() e SAI imediatamente
# (return true) em vez de continuar processando o resto de hit_units; bug
# reportado pelo usuário: o jogo travava se o último inimigo morresse de dano
# de colisão/parede, porque antes desta correção o "return" só existia no
# CALLER (depois de já ter tentado check_auto_end_turn numa batalha que já
# tinha terminado).
func execute_whirlwind_push(attacker: Node, dir: Vector2i) -> bool:
	var hit_units: Array[Node] = []
	for cell in get_wide_cells(attacker.grid_pos, dir, 1):
		if cell.x < 0 or cell.x >= MAP_WIDTH or cell.y < 0 or cell.y >= MAP_HEIGHT:
			continue
		var u = get_unit_at(cell)
		if u != null and not hit_units.has(u):
			hit_units.append(u)

	for u in hit_units:
		var push_distance = 5 - u.weight
		var path: Array[Vector2i] = []
		var current_cell = u.grid_pos
		var stopped_by_wall = false
		var collided_unit: Node = null
		for step in push_distance:
			var next_cell = current_cell + dir
			if is_wall_or_border(next_cell):
				stopped_by_wall = true
				break
			var occupant = get_unit_at(next_cell)
			if occupant != null and occupant != u:
				collided_unit = occupant
				break
			current_cell = next_cell
			path.append(current_cell)

		# Pedido do usuário (2026-07-24): "Units pushed into fluids they can't
		# stand on are moved to the closest free standable tile" — diferente
		# de esbarrar em parede/unidade (que causa dano E para o empurrão),
		# aterrissar num fluido que esta unidade não atravessa NÃO é uma
		# colisão de verdade (get_wide_cells/is_wall_or_border não sabem nada
		# de fluido) — só redireciona o pouso final pro tile andável mais
		# próximo, sem dano nenhum por isso. Só importa se current_cell mudou
		# de verdade (path não vazio) — se o empurrão nem saiu do lugar
		# (parede logo no 1º passo), não há pouso nenhum pra corrigir.
		if not path.is_empty() and fluid_cells.has(current_cell) and not can_unit_cross_fluid(u):
			current_cell = _find_nearest_standable_cell(current_cell, u)
			path.append(current_cell)

		if not path.is_empty():
			u.move_along_path(path)

		if stopped_by_wall:
			var wall_damage = max(1, u.weight * 5)
			u.take_damage(wall_damage)
			log_message("%s slammed into a wall!" % u.data.unit_name)
			if u.hp_current <= 0:
				remove_defeated_unit(u)
				_apply_challenge_permadeath(u)
				if enemy_units.is_empty() or player_units.is_empty():
					await end_battle(u, enemy_units.is_empty())
					return true
		elif collided_unit != null:
			var damage_to_u = max(1, collided_unit.weight * 5)
			var damage_to_collided = max(1, u.weight * 5)
			u.take_damage(damage_to_u)
			collided_unit.take_damage(damage_to_collided)
			log_message("%s collided with %s!" % [u.data.unit_name, collided_unit.data.unit_name])
			var u_died = u.hp_current <= 0
			var collided_died = collided_unit.hp_current <= 0
			if u_died:
				remove_defeated_unit(u)
				_apply_challenge_permadeath(u)
			if collided_died:
				remove_defeated_unit(collided_unit)
				_apply_challenge_permadeath(collided_unit)
			if (u_died or collided_died) and (enemy_units.is_empty() or player_units.is_empty()):
				await end_battle(u if u_died else collided_unit, enemy_units.is_empty())
				return true

	return false

# BFS 8-direções a partir de `origin` (que a esta altura já se sabe que NÃO
# serve — fluido que `u` não atravessa) procurando a célula ANDÁVEL mais
# próxima: sem parede/borda, sem outra unidade em cima, e sem ser fluido que
# `u` não atravessa (mesma checagem de can_unit_cross_fluid). BFS garante
# "mais próxima" de verdade (primeira encontrada na busca em largura, não só
# a primeira testada). Pedido do usuário, ver execute_whirlwind_push acima.
# Fallback (`origin` de volta) só existiria num mapa impossível de preencher
# só de parede/fluido — nunca deveria acontecer na prática.
func _find_nearest_standable_cell(origin: Vector2i, u: Node) -> Vector2i:
	var visited := {origin: true}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	var neighbor_offsets = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell != origin and not is_wall_or_border(cell) and get_unit_at(cell) == null and not (fluid_cells.has(cell) and not can_unit_cross_fluid(u)):
			return cell
		for offset in neighbor_offsets:
			var n = cell + offset
			if n.x < 0 or n.x >= MAP_WIDTH or n.y < 0 or n.y >= MAP_HEIGHT:
				continue
			if visited.has(n):
				continue
			visited[n] = true
			queue.append(n)
	return origin

# Aplica UMA mudança de stat_stage em `target` (ver Unit.modify_stat_stage) e
# toca o efeito visual correspondente (ver play_stat_change_effect), exceto
# quando o estágio JÁ está no limite ANTES da chamada — nesse caso só loga
# "não sobe/desce mais" e nem chama modify_stat_stage (evita uma mensagem
# enganosa de "caiu!" quando na prática o clamp não deixou nada mudar).
func apply_stat_change(target: Node, stat: String, amount: int) -> void:
	if stat == "" or amount == 0:
		return
	var stat_label: String = STAT_DISPLAY_NAMES.get(stat, stat)
	var before: int = target.stat_stages.get(stat, 0)
	if amount > 0 and before >= UnitScript.STAT_STAGE_MAX:
		log_message("%s's %s won't go any higher!" % [target.data.unit_name, stat_label])
		return
	if amount < 0 and before <= UnitScript.STAT_STAGE_MIN:
		log_message("%s's %s won't go any lower!" % [target.data.unit_name, stat_label])
		return
	target.modify_stat_stage(stat, amount)
	log_message("%s's %s %s!" % [target.data.unit_name, stat_label, "rose" if amount > 0 else "fell"])
	play_stat_change_effect(target.position, stat, amount > 0)

# Toca o StatChangeEffect parado em cima de `at_position` (ver AttackData.
# stat_change_stat, scripts/stat_change_effect.gd) — não é esperado por quem
# chama, mesma ideia de play_impact_effect: é só reação visual, não deve
# atrasar o resto do turno.
func play_stat_change_effect(at_position: Vector2, stat: String, increased: bool) -> void:
	var e = STAT_CHANGE_EFFECT_SCENE.instantiate()
	add_child(e)
	var frames: Array[Texture2D] = STAT_CHANGE_UP_FRAMES if increased else STAT_CHANGE_DOWN_FRAMES
	var tint: Color = STAT_CHANGE_TINTS.get(stat, Color.WHITE)
	e.play(frames, at_position, tint)

# Toca o CastEffect VIAJANDO (ver scripts/cast_effect.gd) a partir de QUEM
# ATACA — não fica parado em cima do atacante, sai de 1 tile à FRENTE dele
# (attacker.grid_pos + dir) e viaja até `cast_range` tiles de distância na
# mesma direção (bug reportado pelo usuário: antes tocava direto em cima do
# atacante, sem sair do lugar). Não é esperado por quem chama — mesma ideia
# de play_impact_effect, é só reação visual.
func play_cast_effect(texture: Texture2D, attacker: Node, dir: Vector2i, cast_range: int) -> void:
	if dir == Vector2i.ZERO:
		return
	var from: Vector2 = attacker.cell_to_position(attacker.grid_pos + dir)
	var to: Vector2 = attacker.cell_to_position(attacker.grid_pos + dir * cast_range)
	var e = CAST_EFFECT_SCENE.instantiate()
	add_child(e)
	e.play(texture, from, to, attacker.facing)

# Uso de um item TM (ver handle_targeting_input) — reaproveita execute_attack
# inteiro (dano, efetividade, status secundário, tudo) rodando em cima do
# ataque referenciado (ItemData.tm_attack, ex: Ice Fang), só que
# consume_slot_use=false: quem desconta 1 carga aqui é a PILHA do próprio
# item TM (UnitData.slot_quantities), não o PP do ataque (attack.max_uses/
# Unit.slot_uses) — um TM não "recarrega" com o tempo feito um ataque normal,
# ele é consumido igual uma Ball, só que sem precisar acertar o alvo pra
# sumir uma unidade da pilha (usar o ataque já é o suficiente).
#
# phase pode já ter virado ENDED dentro do await de execute_attack (se esse
# ataque matou o último inimigo/aliado e end_battle já trocou de cena) — por
# isso o guard antes de mexer em slot/HUD, mesmo padrão já usado em
# execute_ball_throw logo abaixo.
func execute_tm_attack(attacker: Node, defender: Node, tm_item: ItemData, slot_index: int) -> void:
	await execute_attack(attacker, defender, tm_item.tm_attack, slot_index, false)
	if phase != Phase.BATTLE:
		return
	attacker.data.set_slot_quantity(slot_index, attacker.data.get_slot_quantity(slot_index) - 1)
	if attacker.data.get_slot_quantity(slot_index) <= 0:
		attacker.data.slots[slot_index] = null
	refresh_action_slots_hud()

# Gêmeo de execute_tm_attack() acima pra um TM cujo tm_attack é de Status
# (ver AttackData.is_status/ItemData.tm_attack) — mesma ideia de
# execute_status_attack existir separada de execute_attack (ver comentário
# grande em AttackData.is_status), só que pro TM: chama
# execute_status_attack em vez de execute_attack, e SÓ DEPOIS desconta a
# carga do item (mesmo "consumo sempre no fim, nunca antes" de
# execute_tm_attack — dir vem pronto de quem chama, igual
# execute_status_attack já espera). TM 11/Sunny Day é o primeiro caso.
func execute_tm_status_attack(attacker: Node, tm_item: ItemData, dir: Vector2i, slot_index: int) -> void:
	await execute_status_attack(attacker, tm_item.tm_attack, dir, slot_index)
	if phase != Phase.BATTLE:
		return
	attacker.data.set_slot_quantity(slot_index, attacker.data.get_slot_quantity(slot_index) - 1)
	if attacker.data.get_slot_quantity(slot_index) <= 0:
		attacker.data.slots[slot_index] = null
	refresh_action_slots_hud()

# Chamado assim que um dos dois times fica sem ninguém (ver o "if" acima,
# logo depois de remove_defeated_unit). `last_defeated` é o nó que acabou de
# morrer — ainda existe na árvore por um instante, tocando a sequência de
# morte (ver Unit.die()); esperamos ele sumir de vez (tree_exited) antes de
# fazer qualquer coisa, senão a cena trocaria/travaria no meio da animação,
# cortando ela na cara do jogador.
#
# phase = ENDED ANTES do await é o que impede qualquer clique de continuar
# a batalha nesse meio-tempo (ver _unhandled_input/handle_battle_input).
func end_battle(last_defeated: Node, victory: bool) -> void:
	phase = Phase.ENDED
	if is_instance_valid(last_defeated) and last_defeated.is_inside_tree():
		await last_defeated.tree_exited

	# Prêmio + registro de derrota SÓ na vitória (regra 6 do usuário: perder
	# pro Trainer não "derrota" ele nem paga nada, o jogador só volta pro
	# último Heal, ver o "else" de sempre logo abaixo). is_trainer_battle e
	# os outros três current_trainer_* SEMPRE voltam pro estado neutro depois
	# daqui, vitória ou derrota — sem isso uma batalha selvagem seguinte
	# herdaria "true" por engano (Ball falhando sempre, current_trainer_team
	# velho sendo spawnado de novo em vez da EncounterArea).
	if victory and GameState.is_trainer_battle:
		GameState.add_money(GameState.current_trainer_prize)
		log_message("You got $%d for winning!" % GameState.current_trainer_prize)
		# O prêmio já fica escrito no log da batalha (linha acima) — o
		# usuário achou uma segunda caixa de texto redundante ("It's already
		# written in the battle log"), então não abrimos mais nenhum popup
		# aqui. A PAUSA em si continua (pedido explícito: "The pause until
		# player presses X is fine though, keep it") — só trocamos "esperar
		# a caixa fechar" por "esperar X/Z ser apertado", sem UI nova
		# nenhuma, dando tempo do jogador ler o log antes da troca de cena.
		await _await_confirm_press()
		# Carimba o número de badges de AGORA, não só "true" — é isso que
		# deixa trainer.gd::interact() saber depois se já rolou uma badge
		# nova desde essa derrota (ver comentário grande em GameState.
		# defeated_trainer_badges).
		GameState.defeated_trainer_badges[GameState.current_trainer_id] = GameState.badges.size()
	# Treinador Rocket some PRA SEMPRE depois desta batalha, vitória OU
	# derrota do jogador (pedido do usuário: "Rocket trainers also vanish
	# after defeating or being defeated. They cannot be rematched") — bem
	# diferente da regra 6 (defeated_trainer_badges acima, só marcado na
	# vitória, e ainda permite revanche com badge nova). Por isso este
	# `if` roda incondicional a `victory`, e ANTES de current_trainer_id/
	# current_trainer_iq serem limpos de volta pro estado neutro logo
	# abaixo — depois disso não teria mais como saber QUEM era o Trainer
	# nem se o time dele era Rocket. Lido por trainer.gd::_ready(), que se
	# destrói na hora (queue_free) se encontrar este trainer_id aqui.
	if GameState.is_trainer_battle and GameState.current_trainer_iq == "Rocket" and GameState.current_trainer_id != "":
		GameState.vanished_trainers[GameState.current_trainer_id] = true
	GameState.is_trainer_battle = false
	GameState.current_trainer_id = ""
	GameState.current_trainer_team = []
	GameState.current_trainer_prize = 0
	GameState.current_trainer_iq = ""
	GameState.current_trainer_starting_weather = ""
	GameState.current_trainer_starting_weather_overridable = true
	# Mesmo espírito dos quatro campos acima — volta pro default ("Grass")
	# assim que a batalha termina, pra uma batalha de TREINADOR seguinte
	# (que nem olha pra este campo) não herdar por engano um "Water" de uma
	# batalha selvagem de água anterior caso algo volte a ler isso sem
	# querer.
	GameState.current_encounter_source = "Grass"

	if victory:
		# Mesmo caminho de volta do botão Flee (ver _on_flee_pressed) — a
		# posição do jogador no overworld já foi salva em GameState antes de
		# entrar na batalha (ver world.gd), então só trocar de cena já basta.
		get_tree().change_scene_to_file(GameState.overworld_scene_path)
	else:
		# Derrota: sem "voltar pro overworld de onde veio" (GameState.
		# player_grid_pos ali seria só o último passo antes de cair nesta
		# batalha específica, que pode ter sido longe de qualquer lugar
		# seguro) — em vez disso, devolve o jogador pro ÚLTIMO lugar onde
		# usou Computador -> Heal (ou Nurse, ou Bed — ver GameState.
		# last_heal_grid_pos/last_heal_facing/last_heal_scene_path,
		# atualizados em GameState.heal_active_roster()). Reaproveita o
		# MESMO mecanismo de restauração que a volta de vitória já usa
		# (has_saved_position + player_grid_pos/facing, lido por
		# world.gd/house_interior.gd::_restore_player_state ao
		# carregar a cena) — só com outra origem pros valores. Também
		# reaplica last_heal_scene_path (não só a posição) — sem isso, um
		# checkpoint de cura dentro de OUTRA cena (uma Bed numa casa,
		# enquanto a batalha perdida rolou lá fora numa rota) reaparecia com
		# as coordenadas certas mas na cena ERRADA (a da rota, não a da
		# casa).
		#
		# Conveniência pedida pelo usuário ("For convenience, also heal the
		# team"): cura o time de verdade na derrota, não só teleporta com o
		# time ainda desmaiado. NÃO chamamos GameState.heal_active_roster()
		# aqui — aquela função também RE-GRAVA o checkpoint pra posição
		# ATUAL (live_grid_pos/live_facing/overworld_scene_path), que nesse
		# momento é onde a batalha começou, não onde o jogador vai
		# reaparecer; faríamos o checkpoint "andar" pra qualquer lugar onde
		# o jogador leva um walkover. Em vez disso, só a parte de cura é
		# repetida aqui, deixando o checkpoint em si intocado.
		for data in GameState.roster:
			if data != null:
				data.current_hp = UnitScript.calc_hp_static(data.hp_base, data.level, data.weight)
		# Multa de dinheiro pedida pelo usuário: "the player loses money
		# equal to their highest unit level * number of badges * 25" —
		# highest LEVEL (não HP/base stat), do time ATIVO (GameState.roster,
		# a "reserva" de storage/giovanni_storage não conta pra isso).
		# clampi/max(0, ...) — dinheiro nunca fica negativo, mesmo espírito
		# de spend_money() recusar gastar mais do que o jogador tem.
		var money_lost = GameState.get_highest_roster_level() * GameState.badges.size() * 25
		GameState.money = max(0, GameState.money - money_lost)
		if money_lost > 0:
			log_message("You lost $%d..." % money_lost)
			await _await_confirm_press()
		GameState.has_saved_position = true
		GameState.player_grid_pos = GameState.last_heal_grid_pos
		GameState.player_facing = GameState.last_heal_facing
		GameState.overworld_scene_path = GameState.last_heal_scene_path
		get_tree().change_scene_to_file(GameState.overworld_scene_path)

# Espera o jogador apertar X/Z (confirm/cancel) uma vez, sem abrir UI
# nenhuma — usado só por end_battle() pra segurar a troca de cena até o
# jogador ter tempo de ler a mensagem de prêmio que já está no log da
# batalha (ver comentário em end_battle). is_action_just_pressed (não
# is_action_pressed) evita que o MESMO toque que já derrotou o último
# inimigo "vaze" pra cá e feche isso sozinho no mesmo frame; espera um
# frame novo de propósito antes do loop, pelo mesmo motivo.
func _await_confirm_press() -> void:
	await get_tree().process_frame
	while true:
		if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("cancel"):
			return
		await get_tree().process_frame

# Instancia o Projectile, manda ele viajar de `from` até `to` (posições em
# pixel, mesmo espaço de coordenadas dos Unit — ver Unit.cell_to_position),
# e só retorna quando ele chega (await no sinal `arrived`). Ver projectile.gd.
# known_frame_count opcional: repassado direto pro mesmo parâmetro de
# Projectile.launch() — 0 (padrão) mantém a adivinhação de sempre (quadros
# quadrados, usada por todo ataque-projétil existente); > 0 é só pra sprite
# sheets com quadros NÃO quadrados, como a de uma Ball (ver ItemData.
# ball_frame_count/execute_ball_throw).
# frames/rotate_to_direction: repassados direto pros mesmos parâmetros de
# Projectile.launch() — ver AttackData.projectile_frames/projectile_faces_right
# (Water Gun é o primeiro caso: dois arquivos separados, arte olhando pra
# direita, precisa girar pra cada direção de verdade).
func fire_projectile(texture: Texture2D, from: Vector2, to: Vector2, known_frame_count: int = 0, frames: Array[Texture2D] = [], rotate_to_direction: bool = false) -> void:
	var p = PROJECTILE_SCENE.instantiate()
	add_child(p)
	p.launch(texture, from, to, known_frame_count, frames, rotate_to_direction)
	await p.arrived

# Toca o ImpactEffect parado em cima de `at_position` (ver AttackData.
# impact_texture/impact_texture_2 e ImpactEffect.play() — não é esperado por
# quem chama, ver comentário no ponto de chamada em execute_attack).
# texture_2 opcional: segunda camada tocada junto (ver AttackData.
# impact_texture_2) — os outros dois usos (secondary_status_texture/_2 em
# _try_apply_secondary_status) continuam passando só uma textura, sem camada
# extra, exatamente como antes. frames opcional: formato "vários arquivos
# separados" da camada 1 (ver AttackData.impact_frames) — Confusion é o
# primeiro caso.
func play_impact_effect(texture: Texture2D, at_position: Vector2, texture_2: Texture2D = null, frames: Array[Texture2D] = []) -> void:
	var e = IMPACT_EFFECT_SCENE.instantiate()
	add_child(e)
	e.play(texture, at_position, texture_2, frames)

# Arremesso de uma Ball (ver handle_targeting_input) — bem mais simples que
# execute_attack: não tem dano, efetividade de tipo, nem status secundário,
# só "acerta uma unidade selvagem inimiga ou se perde numa parede", e SE
# acertar, tenta capturar (ver resolve_capture). A Ball é SEMPRE consumida
# do loadout ao ser arremessada, acerte ou erre — ela é um item físico que
# sai da mão da unidade, não tem "recarregar" (mesmo espírito de Berry se
# auto-consumir inteira, ver Unit._check_berry_auto_use, só que aqui é
# sempre, não condicional a nada).
#
# Ball é Stackable (ver ItemData.stackable) desde que passamos a poder dar
# várias de uma vez (UnitData.slot_quantities): cada arremesso desconta só 1
# da pilha, e o slot só fica null de fato quando a pilha chega a 0 — antes
# disso a mesma linha do loadout continua com as bolas restantes.
func execute_ball_throw(attacker: Node, target_cell: Vector2i, item: ItemData, slot_index: int) -> void:
	attacker.face_towards(target_cell)
	attacker.play_attack_animation(false)
	log_message("%s threw %s!" % [attacker.data.unit_name, item.action_name])

	attacker.data.set_slot_quantity(slot_index, attacker.data.get_slot_quantity(slot_index) - 1)
	if attacker.data.get_slot_quantity(slot_index) <= 0:
		attacker.data.slots[slot_index] = null
	attacker.slot_uses[slot_index] = 0
	attacker.attacks_remaining -= 1
	refresh_action_slots_hud()

	await get_tree().create_timer(attacker.data.attack_hit_delay).timeout

	var result = find_ball_target(attacker, attacker.grid_pos, target_cell, item.range)
	var defender: Node = result["unit"]
	var stop_cell: Vector2i = result["stop_cell"]

	if item.ball_closed_texture != null:
		await fire_projectile(item.ball_closed_texture, attacker.position, attacker.cell_to_position(stop_cell), item.ball_frame_count)

	if defender == null:
		log_message("The %s missed!" % item.action_name)
		refresh_unit_summary_hud()
		check_auto_end_turn()
		return

	await resolve_capture(defender, item)
	# Se a captura deu certo E acabou a batalha (ver resolve_capture ->
	# end_battle), phase já virou Phase.ENDED e a cena já está trocando —
	# nesse caso NÃO dá pra continuar como se o turno ainda existisse (mesmo
	# cuidado que execute_attack toma com o "return" logo após seu próprio
	# await end_battle).
	if phase != Phase.BATTLE:
		return
	refresh_unit_summary_hud()
	check_auto_end_turn()

# Wrappers chamados por handle_targeting_input em vez de execute_attack/
# execute_status_attack/execute_tm_attack/execute_ball_throw direto — essas
# 4 funções são disparadas SEM await ali (fire and forget: handle_targeting_
# input não é async, e travar o input até a animação acabar seria ruim), o
# que deixava flee_button clicável durante a animação de ataque do PRÓPRIO
# jogador (ver action_in_progress, comentário grande onde é declarada). Cada
# wrapper liga a flag antes de chamar a função de verdade (aqui sim COM
# await, já que quem chama o wrapper também não espera por ele) e desliga
# depois, então o "fire and forget" de fora continua igual — só ganhou um
# meio de campo que sabe quando a animação de verdade terminou.
#
# `if phase == Phase.BATTLE` antes de mexer em flee_button.visible: mesmo
# guard que execute_tm_attack/execute_ball_throw já usam — se esse ataque
# terminou a batalha (end_battle já trocou de cena dentro do await acima),
# flee_button não existe mais nesta árvore, não mexe nele.
func _run_player_attack(attacker: Node, defender: Node, attack: AttackData, index: int) -> void:
	action_in_progress = true
	flee_button.visible = false
	await execute_attack(attacker, defender, attack, index)
	action_in_progress = false
	if phase == Phase.BATTLE:
		flee_button.visible = true

func _run_player_status_attack(attacker: Node, attack: AttackData, dir: Vector2i, index: int) -> void:
	action_in_progress = true
	flee_button.visible = false
	await execute_status_attack(attacker, attack, dir, index)
	action_in_progress = false
	if phase == Phase.BATTLE:
		flee_button.visible = true

# Gêmeo de _run_player_status_attack acima pra execute_attack_burst (ver
# comentário grande lá — AttackData.area_shape == "Burst", Lava Plume).
func _run_player_burst_attack(attacker: Node, attack: AttackData, dir: Vector2i, index: int) -> void:
	action_in_progress = true
	flee_button.visible = false
	await execute_attack_burst(attacker, attack, dir, index)
	action_in_progress = false
	if phase == Phase.BATTLE:
		flee_button.visible = true

func _run_player_tm_attack(attacker: Node, defender: Node, item: ItemData, index: int) -> void:
	action_in_progress = true
	flee_button.visible = false
	await execute_tm_attack(attacker, defender, item, index)
	action_in_progress = false
	if phase == Phase.BATTLE:
		flee_button.visible = true

# Gêmeo de _run_player_tm_attack acima pra execute_tm_status_attack — ver
# comentário grande lá (TM 11/Sunny Day).
func _run_player_tm_status_attack(attacker: Node, item: ItemData, dir: Vector2i, index: int) -> void:
	action_in_progress = true
	flee_button.visible = false
	await execute_tm_status_attack(attacker, item, dir, index)
	action_in_progress = false
	if phase == Phase.BATTLE:
		flee_button.visible = true

func _run_player_ball_throw(attacker: Node, target_cell: Vector2i, item: ItemData, index: int) -> void:
	action_in_progress = true
	flee_button.visible = false
	await execute_ball_throw(attacker, target_cell, item, index)
	action_in_progress = false
	if phase == Phase.BATTLE:
		flee_button.visible = true

# Resolve UMA tentativa de captura contra `defender` (já confirmado inimigo
# selvagem válido, ver execute_ball_throw) usando `item` (a Ball
# arremessada). Fórmula pedida pelo usuário:
#
#   (3*HPmax - 2*HPcurrent) * catchRate * ballBonus * statusBonus / (3*HPmax)
#
# guaranteed_capture (ex: Master Ball) pula a fórmula inteira e sempre
# sucede. shake_count é só FLAVOR da animação (ver capture_ball.gd) — 3
# balanços no sucesso, 0 a 2 no fracasso (mesmo padrão visual dos jogos
# Pokémon: 3 balanços "fecha" a captura, menos que isso e o alvo escapa).
#
# Sucesso: a unidade sai da batalha (remove_defeated_unit, igual derrota,
# só que SEM ganhar exp — capturar não derrota ninguém) e o UnitData dela
# (com nível/HP preservados, ver UnitData.apply_capture_progress) vai pra
# primeira vaga livre da reserva certa (ver `storage_pool` logo abaixo).
# Fracasso: a unidade volta a aparecer exatamente como estava
# (visible = true) — nada nela foi alterado em momento nenhum, então
# "devolver" é só isso mesmo.
func resolve_capture(defender: Node, item: ItemData) -> void:
	var success: bool
	if not defender.is_enemy:
		# `defender` é uma unidade do JOGADOR — só acontece quando um
		# treinador Rocket joga a Rocket Ball nela (ver _plan_rocket_action),
		# nunca o contrário. Regra do usuário: "that always succeeds
		# capturing the player's unit" — sucesso incondicional, sem fórmula
		# nenhuma e SEM passar pelo `is_trainer_battle -> false` logo abaixo
		# (essa regra existe pra proteger o time do TREINADOR de ser roubado
		# pelo jogador, o oposto do que está acontecendo aqui).
		success = true
	elif GameState.is_trainer_battle:
		# Regra do usuário: "Balls will ALWAYS fail if used against Units on
		# a trainer battle" — checado ANTES até de guaranteed_capture (Master
		# Ball inclusa: nenhuma Ball é exceção). Time do próprio Trainer não
		# é "livre" pra capturar, diferente de um selvagem.
		success = false
	elif GameState.game_mode == "challenge" and GameState.current_area != null and GameState.challenge_caught_areas.get(GameState.current_area.area_name, false):
		# Regra 1 do Challenge (pedido do usuário: "Only one unit may be
		# caught in each area. Trying to catch a second unit always results
		# in failure") — mesma prioridade absoluta que a trava de trainer
		# battle logo acima: nenhuma Ball (nem Master Ball, guaranteed_capture
		# incluso) escapa disso enquanto a área já tiver um registro em
		# GameState.challenge_caught_areas (gravado abaixo, no ramo de
		# sucesso). Só entra em jogo no modo Challenge — nos outros dois
		# game_mode não existe restrição de área nenhuma.
		success = false
	elif item.guaranteed_capture:
		success = true
	else:
		var hp_max = float(defender.hp_max)
		var hp_now = float(defender.hp_current)
		var status_bonus = defender.get_capture_status_bonus()
		var chance = (3.0 * hp_max - 2.0 * hp_now) * defender.data.catch_rate * item.ball_bonus * status_bonus / (3.0 * hp_max)
		success = randf() < chance

	var shake_count = 3 if success else randi_range(0, 2)

	defender.visible = false
	var ball = CAPTURE_BALL_SCENE.instantiate()
	add_child(ball)
	# move_child() pro índice ONDE o defensor está (empurra ele — e todo
	# mundo depois dele — uma posição pra frente) em vez de deixar a bola no
	# fim da lista (padrão de add_child): mesmo z_index 0 de tudo, então quem
	# decide "na frente ou atrás" aqui é a ORDEM na árvore — ficar ANTES do
	# defensor é o que garante a bola desenhar atrás dele. Um z_index
	# negativo faria o mesmo só que atrás do MAPA também (TileMapLayer é
	# irmã, no mesmo z_index 0) — ficaria invisível debaixo do chão, que foi
	# exatamente o bug visto no teste.
	move_child(ball, defender.get_index())
	await ball.play(item.ball_open_texture, item.ball_closed_texture, item.ball_frame_count, defender.position, success, shake_count)

	if success:
		log_message("Gotcha! %s was caught!" % defender.data.unit_name)
		if defender.is_enemy:
			# Selvagem/de treinador capturado pelo JOGADOR — de sempre:
			# carimba nível/HP (UnitData.apply_capture_progress) e ONDE foi
			# capturada (UnitData.caught_location, lida de GameState.
			# current_area — null só aconteceria se uma batalha rodasse sem
			# NUNCA ter passado por um overworld antes, daí o "" de
			# fallback), depois vai pra reserva normal do jogador.
			defender.data.apply_capture_progress(defender.level, defender.hp_current)
			defender.data.caught_location = GameState.current_area.area_name if GameState.current_area != null else ""
			GameState.add_to_first_empty_storage_slot(defender.data)
			# Regra 1 do Challenge (ver comentário grande logo acima, no
			# `elif` que checa este mesmo Dictionary) — carimba a área AGORA,
			# depois que a captura já deu certo, pra travar qualquer
			# tentativa seguinte nesta mesma área pro resto da partida.
			if GameState.game_mode == "challenge" and GameState.current_area != null:
				GameState.challenge_caught_areas[GameState.current_area.area_name] = true
		else:
			# Unidade do JOGADOR roubada por um treinador Rocket
			# (defender.is_enemy == false). defender.data JÁ É a mesma
			# instância que mora em GameState.roster (Unit do jogador nunca
			# duplica UnitData, ver Unit.apply_persisted_data — diferente do
			# inimigo, que sempre duplica, ver Unit.apply_fresh_data) — nível/
			# xp/HP já estão corretos nela, então NENHUM dos dois passos
			# acima se aplica aqui: apply_capture_progress() reescreveria xp
			# pro chão do nível atual (perderia progresso parcial de
			# verdade), e "onde foi capturada" não faz sentido nenhum pra uma
			# unidade que já era do jogador.
			#
			# Precisa sair do time ATIVO (GameState.roster) ANTES de entrar
			# na caixa do Giovanni — sem isso, a MESMA UnitData ficava
			# referenciada nos dois lugares ao mesmo tempo (roster ainda
			# "cheio" nesse slot) e continuava aparecendo normalmente no
			# time do jogador (bug reportado pelo usuário: "the captured
			# unit didn't leave my party"). Ver GameState.remove_from_roster.
			GameState.remove_from_roster(defender.data)
			GameState.add_to_first_empty_giovanni_slot(defender.data)
		remove_defeated_unit(defender)
		defender.queue_free()
		if enemy_units.is_empty() or player_units.is_empty():
			await end_battle(defender, enemy_units.is_empty())
	else:
		log_message("%s broke free!" % defender.data.unit_name)
		defender.visible = true

# Distribui exp pro time de quem derrotou (ver ExpGroups.calc_exp_gain e a
# fórmula b*L*a/7): 1.5x pra quem deu o golpe final, 1x pros demais aliados
# que ainda estão vivos. defender já está com hp_current <= 0 aqui (mas o nó
# ainda existe — só é removido depois da sequência de morte, ver Unit.die()
# — então dá pra ler defender.level/defender.data à vontade).
#
# Só o time do JOGADOR ganha exp de verdade. Antes da IA existir, um inimigo
# nunca derrotava ninguém, então esse "if killer.is_enemy: return" nunca
# importava — agora que inimigo selvagem ataca de verdade (ver
# run_enemy_turn), sem essa trava um selvagem que derrota uma unidade do
# jogador faria TODOS os selvagens vivos da batalha subirem de nível na hora
# (Unit.gain_exp() recalcula stats na hora, sem checar is_enemy) — ficariam
# mais fortes NO MEIO do próprio combate, o que não faz sentido de jogo
# nenhum. sync_to_data() já impede isso de PERSISTIR pro catálogo, mas não
# impede a unidade de ficar mais forte ali mesmo, na mesma batalha.
func award_experience(killer: Node, defeated: Node) -> void:
	if killer.is_enemy:
		return
	var team = player_units
	var total_gained = 0
	for u in team:
		if u.hp_current <= 0:
			continue
		var multiplier = 1.5 if u == killer else 1.0
		var gained = ExpGroups.calc_exp_gain(defeated.data.base_exp_yield, defeated.level, multiplier)
		u.gain_exp(gained)
		total_gained += gained
	log_message("Your team gained %d EXP." % total_gained)

# Tira a unidade derrotada de TODA a contabilidade da batalha (menos da
# árvore de cena — o nó em si só some sozinho no fim da sequência de morte,
# ver Unit.die()). Sem isso, essas listas/dicionários ficavam com uma
# referência "presa" pra um nó que ia ser destruído em ~1s, e a primeira
# tentativa de usar essa referência depois (ex: get_unit_at percorrendo
# `units`) crashava com "Invalid access... on a base object of type
# 'previously freed'". Chamado assim que hp_current chega a 0, não quando o
# nó é de fato removido — a unidade fica "fora do jogo" um pouco antes de
# sumir da tela de vez, o que é o comportamento certo mesmo (não dá pra
# mirar nem contar turno de quem já morreu).
func remove_defeated_unit(u: Node) -> void:
	var turn_idx = turn_queue.find(u)
	if turn_idx != -1:
		turn_queue.remove_at(turn_idx)
		if turn_idx < current_turn_index:
			current_turn_index -= 1
		elif current_turn_index >= turn_queue.size():
			current_turn_index = 0

	player_units.erase(u)
	enemy_units.erase(u)
	units.erase(u)

	if unit_slots.has(u):
		var slot: PanelContainer = unit_slots[u]
		if is_instance_valid(slot):
			slot.queue_free()
		unit_slots.erase(u)
	unit_hp_labels.erase(u)

# Regra 2 do Challenge (pedido do usuário: "Once a unit faints it is
# deleted forever. The items that were in its loadout are added back to
# the bag") — chamada logo depois de remove_defeated_unit() nos dois
# lugares onde uma unidade de verdade desmaia em batalha (dano direto e
# Status Condition no fim do turno; NÃO no ramo de captura de
# resolve_capture(), que não é um desmaio). `u.data` ainda é válido aqui
# (o nó só é destruído de fato depois da animação de morte, ver Unit.die())
# — dá pra ler o loadout dele antes de sumir.
#
# not u.is_enemy: só o TIME DO JOGADOR sofre permadeath — um selvagem/
# treinador inimigo desmaiando é derrota normal de sempre, sem efeito
# nenhum daqui (regra do usuário fala só da unidade DO JOGADOR).
#
# GameState.remove_from_roster (já existia, usado por resolve_capture pro
# caso de Rocket roubando unidade do jogador) tira a UnitData de `roster`
# pra sempre — diferente de remove_defeated_unit() acima, que só limpa a
# contabilidade LOCAL desta batalha; sem isso a unidade voltaria a
# aparecer no time/Party assim que a batalha terminasse e o roster fosse
# lido de novo, exatamente como acontece nos outros 2 modos.
func _apply_challenge_permadeath(u: Node) -> void:
	if GameState.game_mode != "challenge" or u.is_enemy or u.data == null:
		return
	for i in u.data.slots.size():
		var action = u.data.slots[i]
		if action is ItemData:
			# get_slot_quantity só é > 1 pra item Stackable (Ball/TM, ver
			# UnitData.slot_quantities) — held item comum nunca teve
			# quantidade escrita nesse índice, então max(...,1) garante
			# devolver pelo menos a 1 unidade física que estava equipada.
			var amount = max(u.data.get_slot_quantity(i), 1)
			GameState.add_item(action, amount)
	GameState.remove_from_roster(u.data)

func cancel_targeting() -> void:
	targeting_action = null
	targeting_slot_index = -1
	attack_highlight_layer.clear()

# Passa o turno sozinho quando a unidade da vez não tem mais NEM movimento
# NEM ataque disponível (Habilidade/Item não entram nessa conta — só travam
# o ataque, ver Unit.attacks_remaining). Chamado depois de mover e depois de
# atacar, os dois únicos jeitos desses orçamentos baixarem.
func check_auto_end_turn() -> void:
	var u = get_current_unit()
	if u == null:
		return
	if move_budget_left <= 0 and u.attacks_remaining <= 0:
		_on_end_turn_pressed()

func _on_end_turn_pressed() -> void:
	if phase != Phase.BATTLE or turn_queue.is_empty():
		return
	# "Um turno é contabilizado depois daquela unidade afetada Passar o
	# turno" — ou seja, o tick de Status Condition é da unidade que está
	# TERMINANDO o turno agora (manual via Pass, ou automático via
	# check_auto_end_turn), nunca da próxima. Por isso pegamos o current ANTES
	# de avançar current_turn_index.
	var finishing_unit = get_current_unit()
	if finishing_unit != null:
		# Speed Boost (ver AbilityData.speed_boost/has_speed_boost) — sobe ANTES
		# do tick de Status Condition abaixo, incondicional (não depende de
		# sobreviver ao próprio turno): "ao final do turno", não "se nada mais
		# acontecer". Reusa apply_stat_change() — mesma função e mesmo efeito
		# visual que Growl já usa, só que aqui o alvo é a própria unidade.
		if has_speed_boost(finishing_unit):
			apply_stat_change(finishing_unit, "speed", 1)
		var died = await apply_end_of_turn_status(finishing_unit)
		# Veneno pode ter matado a unidade e encerrado a batalha dentro do
		# await acima (ver apply_end_of_turn_status) — nesse caso não faz
		# sentido continuar pra próxima unidade.
		if phase != Phase.BATTLE:
			return
		if died:
			# remove_defeated_unit() (chamado dentro de apply_end_of_turn_status)
			# já tira a unidade morta de turn_queue E reajusta
			# current_turn_index sozinho — nesse índice já sobrou apontando
			# pra quem SERIA o próximo. Se a gente ainda somasse +1 aqui
			# embaixo (igual o caminho normal, sem morte), pularia uma
			# unidade inteira da fila.
			begin_current_turn()
			return
	# Fim da rodada (todo mundo já jogou, current_turn_index ia estourar o
	# tamanho da fila) — re-sorta a fila INTEIRA pela Speed ATUAL de cada
	# unidade antes de recomeçar do topo. Sem isso, uma unidade que mudou a
	# PRÓPRIA Speed no fim do próprio turno (Speed Boost, chance da Ancient
	# Power) nunca refletia isso na fila: reorder_turn_queue_by_speed() (ver
	# abaixo) só reordena quem ainda não jogou NESTA rodada (pending) — quem
	# já jogou (incluindo a própria unidade que acabou de mudar a Speed dela)
	# fica de fora de propósito, porque não faz sentido "desjogar" alguém no
	# meio da rodada. Isso deixava a ordem "presa" pra sempre depois da
	# primeira rodada, mesmo com Speed mudando bastante — só um recomeço de
	# rodada de verdade corrige isso.
	var next_index = current_turn_index + 1
	if next_index >= turn_queue.size():
		# Rodada nova de verdade (todo mundo já jogou) — é AQUI, não no fim do
		# turno de cada unidade individual, que o clima desconta 1 (pedido do
		# usuário: "Weather effects last for 4 turns"). Contar por unidade em
		# vez de por rodada faria um time de 6 gastar o clima inteiro numa
		# rodada só — ver comentário grande em weather_turns_left.
		_advance_weather_turn()
		turn_queue.sort_custom(func(a, b): return a.get_effective_stat("speed") > b.get_effective_stat("speed"))
		current_turn_index = 0
		build_unit_summary_hud()
	else:
		current_turn_index = next_index
	begin_current_turn()

# Desconta 1 rodada de weather_turns_left e encerra o clima sozinho quando
# chega a 0 — nada acontece se não houver clima ativo (WEATHER_NONE) ou se
# ele for permanente (weather_turns_left < 0, ver try_set_weather). Voltar
# weather_overridable pra true junto da limpeza evita que o flag "travado"
# de um clima permanente anterior (ver EncounterArea/Trainer.
# starting_weather_overridable) vaze pro PRÓXIMO clima que vier a ser
# ativado nesta mesma batalha, que por padrão deveria poder ser sobrescrito
# normalmente.
const WEATHER_END_MESSAGES := {
	WEATHER_SUNNY: "The sunlight faded.",
	WEATHER_RAIN: "The rain stopped.",
	WEATHER_SANDSTORM: "The sandstorm subsided.",
	WEATHER_SNOW: "The snow stopped falling.",
}

func _advance_weather_turn() -> void:
	if current_weather == WEATHER_NONE or weather_turns_left < 0:
		return
	weather_turns_left -= 1
	if weather_turns_left <= 0:
		log_message(WEATHER_END_MESSAGES.get(current_weather, "The weather cleared up."))
		current_weather = WEATHER_NONE
		weather_turns_left = 0
		weather_overridable = true
	# Sem animação aqui de propósito — essa é só pra ATIVAÇÃO (ver
	# try_set_weather/play_weather_anim), nunca pra desconto de rodada ou
	# fim natural do clima. O mask precisa sumir/mudar NA HORA, junto com o
	# nome.
	refresh_weather_label()
	refresh_weather_mask()

# Sandstorm: todo mundo perde 1/16 do PRÓPRIO hp_max ao passar o turno,
# exceto Ground/Steel/Rock (pedido do usuário) — mesmo "cano" de
# Unit.get_status_tick_damage() (só calcula o número, quem aplica e checa
# morte é apply_end_of_turn_status logo abaixo), só que baseado no CLIMA da
# batalha em vez de status_condition da própria unidade, por isso mora aqui
# e não em unit.gd. max(1, ...) evita "0 de dano" arredondado em unidades de
# HP baixo — diferente do tick de Poisoned (Unit.get_status_tick_damage),
# que não tem essa trava; aqui vale a pena porque 1/16 é uma fração bem
# menor que os 8% de Poisoned, mais fácil de zerar em hp_max pequeno.
const SANDSTORM_DAMAGE_FRACTION_DENOMINATOR = 16
const SANDSTORM_IMMUNE_TYPES = ["Ground", "Steel", "Rock"]

func get_weather_tick_damage(u: Node) -> int:
	if current_weather != WEATHER_SANDSTORM:
		return 0
	for t in SANDSTORM_IMMUNE_TYPES:
		if u.data.types.has(t):
			return 0
	@warning_ignore("integer_division")
	return max(1, u.hp_max / SANDSTORM_DAMAGE_FRACTION_DENOMINATOR)

# Seeded (Leech Seed): pedido do usuário (2026-07-22, correção depois do
# valor inicial de 10%): "Increase leech seed damage to 12,5%" — mesmo "cano"
# de get_weather_tick_damage/Unit.get_status_tick_damage acima (só calcula o
# número), mas mora em battle.gd (não em unit.gd) porque quem consome esse
# valor (apply_end_of_turn_status) também precisa saber QUEM curar com ele
# (ver _apply_leech_seed_heal logo abaixo), e Unit não tem acesso a outras
# unidades da batalha pra fazer isso sozinha. Grass já é imune a "Seeded" de
# saída (ver Unit.STATUS_TYPE_IMMUNITIES — apply_status_condition recusa
# antes mesmo do status pegar), então nem chega a existir a Status Condition
# numa unidade Grass pra este tick rodar.
#
# 12,5% == 1/8 EXATO — por isso vira uma divisão por 8 (mesmo padrão de
# SANDSTORM_DAMAGE_FRACTION_DENOMINATOR logo acima), não uma conta em cima de
# 100 (que exigiria um float pra representar "12,5" sem arredondar errado
# antes da divisão inteira). Coincide, de propósito, com o valor real de
# Leech Seed na série principal (1/8 do HP máximo). Renomeada de
# LEECH_SEED_DAMAGE_FRACTION_DENOMINATOR (2026-07-23) quando Sand Tomb/Rooted
# virou o segundo efeito a usar a MESMA fração — pedido do usuário: "keep
# over-time damage percentage the same" (fez questão de manter os 12,5% de
# Leech Seed pro tick de Rooted também) — ver get_rooted_tick_damage abaixo.
const BINDING_DAMAGE_FRACTION_DENOMINATOR = 8

func get_seeded_tick_damage(u: Node) -> int:
	if not u.has_status("Seeded"):
		return 0
	@warning_ignore("integer_division")
	return max(1, u.hp_max / BINDING_DAMAGE_FRACTION_DENOMINATOR)

# Rooted (ver AttackData.secondary_status/Sand Tomb — pedido do usuário:
# "gives 'Rooted' status. Rooted Pokémon can't move... Change the duration
# to 2 turns, keep over-time damage percentage the same"). Diferente de
# Seeded, não cura NINGUÉM — é só dano direto na própria unidade presa, sem
# fonte pra "devolver" HP (Sand Tomb não é um dreno). Duração real (2 turnos)
# mora em Unit.STATUS_DURATIONS["Rooted"], decrementada pelo mesmo laço
# genérico de fim-de-turno que já cuida de Frozen/Paralyzed/Confused/Blind —
# este tick de dano só soma no HP perdido, não mexe na duração.
func get_rooted_tick_damage(u: Node) -> int:
	if not u.has_status("Rooted"):
		return 0
	@warning_ignore("integer_division")
	return max(1, u.hp_max / BINDING_DAMAGE_FRACTION_DENOMINATOR)

# Aqua Ring (ver AttackData.inflicts_status_on_self — mesmo mecanismo de
# Protect, só que o status aplicado é benéfico em vez de bloquear ataques
# alheios): pedido do usuário: "Self cast, gives 1/16 HP regeneration at the
# end of each turn... Create a status for it, since it isn't stackable with
# itself". O "não empilha com ele mesmo" já sai de graça: apply_status_
# condition() (ver lá em cima) recusa sozinho se a MESMA chave já estiver em
# status_conditions, então usar Aqua Ring de novo enquanto já ativo simplesmente
# não faz nada (mesma regra de Sleep citada no comentário grande de
# status_conditions) — nenhum código extra precisou ser escrito pra isso.
# Sem entrada em STATUS_DURATIONS (fica -1, "sem prazo") — diferente de Rooted,
# não foi pedido um número de turnos, então fica ativo até a unidade desmaiar
# ou a batalha acabar, igual Poisoned/Burned. Sem entrada em MOVEMENT_BLOCKING_
# STATUS/ATTACK_BLOCKING_STATUS (é benéfico, nunca trava nada de quem tem).
const AQUA_RING_HEAL_FRACTION_DENOMINATOR = 16

func get_aqua_ring_heal(u: Node) -> int:
	if not u.has_status("Aqua Ring"):
		return 0
	@warning_ignore("integer_division")
	return max(1, u.hp_max / AQUA_RING_HEAL_FRACTION_DENOMINATOR)

# Leftovers (ver ItemData.heal_fraction_per_turn, pedido do usuário: "at the
# end of each turn, heals user by 1/16 of their HP") — mesmo "cano" de
# get_aqua_ring_heal acima (só calcula o número, quem soma/aplica é
# apply_end_of_turn_status), mas lendo do ITEM equipado em vez de um Status
# Condition, por isso itera u.data.slots (mesmo padrão de has_shed_skin/
# has_flash_fire pra Habilidade, só que checando ItemData aqui). Soma TODOS os
# itens equipados com essa fração (hoje só existe Leftovers, mas nada impede
# um segundo item igual algum dia — improvável de acontecer na prática, já
# que só há 1 slot de Held Item por unidade, mas a soma cobre o caso mesmo
# assim em vez de só pegar "o primeiro achado").
func get_leftovers_heal(u: Node) -> int:
	var total_fraction = 0.0
	for action in u.data.slots:
		if action is ItemData and action.heal_fraction_per_turn > 0.0:
			total_fraction += action.heal_fraction_per_turn
	if total_fraction <= 0.0:
		return 0
	return max(1, int(u.hp_max * total_fraction))

# "HP reduced by this effect is granted to Leech Seed user as healing" — cura
# QUEM aplicou "Seeded" em `seeded_unit` (ver Unit.get_status_source), não
# necessariamente quem está na vez agora. `amount` já vem PRONTO de quem
# chamou (ver apply_end_of_turn_status: min(seed_damage, hp_lost), mesmo
# cuidado contra overkill do bug de recoil do Typhlosion — não cura mais do
# que a unidade Seeded realmente perdeu de HP). is_instance_valid() cobre o
# caso de quem aplicou já ter desmaiado/saído da batalha antes deste tick
# rodar — nesse caso simplesmente não cura ninguém, sem erro.
func _apply_leech_seed_heal(seeded_unit: Node, amount: int) -> void:
	if amount <= 0:
		return
	var source = seeded_unit.get_status_source("Seeded")
	if source == null or not is_instance_valid(source) or source.hp_current <= 0:
		return
	source.hp_current = min(source.hp_current + amount, source.hp_max)
	source.update_health_bar()
	source.sync_to_data()
	log_message("%s's health was sapped by Leech Seed!" % seeded_unit.data.unit_name)

# Aplica o "fim de turno" de Status Condition da unidade `u`, que acabou de
# passar seu turno (ver comentário acima): dano de Poisoned + decremento do
# contador de CADA condição empilhada que tiver prazo (ver Unit.
# status_conditions/STATUS_DURATIONS), curando individualmente quem chegar a
# 0 — antes disso era um único status_turns_left; agora, como várias
# condições podem coexistir (ver pedido do usuário sobre empilhamento), cada
# uma conta seu próprio prazo, sem uma condição "resetar" o prazo de outra.
# Frozen/Paralyzed/Confused/Blind/Asleep têm prazo; Poisoned/Burned/Charged
# não (só saem por cura, ver STATUS_DURATIONS.get(..., -1)) e Flinched nem
# chega aqui (já foi curada em begin_current_turn, ver comentário lá). Dano
# de clima (Sandstorm, ver get_weather_tick_damage acima) soma no MESMO
# take_damage de baixo — uma unidade Envenenada numa tempestade de areia
# leva os dois de uma vez, com uma mensagem própria só pro clima.
#
# Diferente de Unit.get_status_tick_damage() (que só CALCULA o número), aqui
# é onde a consequência de verdade acontece — inclusive uma possível morte,
# por isso essa função vive em battle.gd (que é quem sabe remover unidade
# derrotada e checar fim de batalha) e não em unit.gd. Seeded (Leech Seed,
# ver get_seeded_tick_damage/_apply_leech_seed_heal acima) soma no MESMO
# tick_damage de Poisoned/Sandstorm, mas precisa de tratamento à parte
# ANTES do take_damage — a cura de quem aplicou o golpe usa o HP que a
# unidade Seeded REALMENTE perdeu (capturado como hp_lost, mesmo cuidado
# contra overkill do bug de recoil do Typhlosion), não o tick_damage bruto,
# que pode incluir Poison/Sandstorm somados na mesma rodada.
#
# Devolve true se `u` morreu aqui (ver o "if died" em _on_end_turn_pressed,
# que depende disso pra não avançar o índice duas vezes).
func apply_end_of_turn_status(u: Node) -> bool:
	# Shed Skin (ver AbilityData.shed_skin, pedido do usuário, 2026-07-23,
	# Metapod: "at the end of each turn, recovers from Poison, Paralysis,
	# Freeze and Sleep. Heals from poison before being damaged") — roda ANTES
	# de calcular tick_damage de propósito: se `u` estava Poisoned, ela já não
	# está mais quando get_status_tick_damage() (linha logo abaixo) rodar,
	# então o dano de veneno deste turno nem chega a existir. SEMPRE (sem
	# chance nenhuma, diferente da série principal que usa 33% — pedido do
	# usuário não citou chance). Confused/Blind/Flinched/Rooted/etc. ficam de
	# fora — só as 4 condições nomeadas.
	if has_shed_skin(u):
		# "Badly Poisoned" (Toxic, ver Unit.badly_poison_turns) entra na MESMA
		# lista que "Poisoned" — pro efeito de Shed Skin, as duas são só
		# "está envenenado", igual Poison Heal logo abaixo trata as duas iguais.
		for status_name in ["Poisoned", "Badly Poisoned", "Paralyzed", "Frozen", "Asleep"]:
			if u.has_status(status_name):
				u.cure_status_condition(status_name)
				log_message("%s's Shed Skin cured its %s!" % [u.data.unit_name, status_name])
	# Poison Heal (ver AbilityData.poison_heal, pedido do usuário, Shroomish:
	# "When poisoned, user will Heal 1/8 of its HP instead of taking Poison
	# damage each turn") — TROCA o tick de dano de Poisoned/Badly Poisoned por
	# uma cura, em vez de somar no tick_damage normal como Sandstorm/Seeded/
	# Rooted fazem logo abaixo. get_status_tick_damage() nem chega a ser
	# chamado neste caso — o que também tem o efeito colateral correto de
	# NÃO incrementar Unit.badly_poison_turns enquanto Poison Heal estiver
	# ativo (ver comentário lá).
	var tick_damage = 0
	if has_poison_heal(u) and (u.has_status("Poisoned") or u.has_status("Badly Poisoned")):
		var poison_heal_amount = max(1, int(u.hp_max * POISON_HEAL_FRACTION))
		u.hp_current = min(u.hp_current + poison_heal_amount, u.hp_max)
		u.update_health_bar()
		u.sync_to_data()
		log_message("%s restored HP with Poison Heal!" % u.data.unit_name)
	else:
		tick_damage = u.get_status_tick_damage()
	var weather_tick_damage = get_weather_tick_damage(u)
	var seed_damage = get_seeded_tick_damage(u)
	var rooted_damage = get_rooted_tick_damage(u)
	if weather_tick_damage > 0:
		tick_damage += weather_tick_damage
		log_message("%s is buffeted by the sandstorm!" % u.data.unit_name)
	if seed_damage > 0:
		tick_damage += seed_damage
	if rooted_damage > 0:
		# Rooted (ver Sand Tomb): diferente de seed_damage, não cura ninguém
		# — só soma no dano bruto deste tick, sem tratamento à parte antes do
		# take_damage.
		tick_damage += rooted_damage
		log_message("%s is hurt by Rooted!" % u.data.unit_name)
	if tick_damage > 0:
		var hp_lost = min(tick_damage, u.hp_current)
		u.take_damage(tick_damage)
		if seed_damage > 0:
			_apply_leech_seed_heal(u, min(seed_damage, hp_lost))
		if u.hp_current <= 0:
			# Sem exp aqui de propósito: veneno não tem "quem matou" (ver
			# award_experience, que precisa de um killer) — é uma
			# simplificação deliberada, não um esquecimento.
			remove_defeated_unit(u)
			_apply_challenge_permadeath(u)
			refresh_unit_summary_hud()
			if enemy_units.is_empty() or player_units.is_empty():
				await end_battle(u, enemy_units.is_empty())
			return true

	# Aqua Ring (ver get_aqua_ring_heal acima): roda DEPOIS do bloco de dano
	# (que já retornou true e saiu se a unidade morreu ali), então só cura
	# quem sobreviveu ao próprio tick. Cura diretamente (sem passar por
	# take_damage, que é só pra dano) e trava em hp_max via min(), mesmo
	# cuidado de _apply_leech_seed_heal logo abaixo.
	var aqua_ring_heal = get_aqua_ring_heal(u)
	if aqua_ring_heal > 0 and u.hp_current > 0:
		u.hp_current = min(u.hp_current + aqua_ring_heal, u.hp_max)
		u.update_health_bar()
		u.sync_to_data()
		log_message("%s's Aqua Ring restored its HP!" % u.data.unit_name)

	# Leftovers (ver get_leftovers_heal acima): tick independente do de Aqua
	# Ring — os dois podem empilhar (uma unidade Aqua Ring segurando Leftovers
	# cura os dois no mesmo turno), cada um com sua própria mensagem.
	var leftovers_heal = get_leftovers_heal(u)
	if leftovers_heal > 0 and u.hp_current > 0:
		u.hp_current = min(u.hp_current + leftovers_heal, u.hp_max)
		u.update_health_bar()
		u.sync_to_data()
		log_message("%s restored a little HP using its Leftovers!" % u.data.unit_name)

	# .duplicate() antes de iterar: cure_status_condition(status) apaga a
	# chave do dicionário DE VERDADE (ver Unit.cure_status_condition) — mexer
	# na coleção enquanto ela mesma está sendo percorrida é terreno instável
	# em GDScript, então percorremos uma cópia das chaves e só depois mexemos
	# no dicionário original.
	for status_name in u.status_conditions.keys().duplicate():
		if u.status_conditions[status_name] > 0:
			u.status_conditions[status_name] -= 1
			if u.status_conditions[status_name] <= 0:
				u.cure_status_condition(status_name)
	return false

# Desfaz o movimento inteiro da unidade da vez, voltando pra onde ela
# estava no início do turno, e devolve o orçamento de movimento cheio.
# Sai da batalha sem vencer nem perder, direto pro overworld — devolve o
# personagem pra onde ele estava graças ao GameState (ver world.gd
# _restore_player_state(), já escuta isso desde o encontro aleatório).
# Ainda não desconta nada por fugir (perder o Pokémon selvagem, etc.) —
# é só o "sair da tela de batalha" por enquanto.
func _on_flee_pressed() -> void:
	if phase != Phase.BATTLE:
		return
	# Trainer battle nunca deixa fugir (mesma regra dos jogos de verdade) —
	# sem isso, fugir mudava de cena direto (change_scene_to_file logo
	# abaixo) SEM passar por end_battle(), que é quem zera GameState.
	# is_trainer_battle/current_trainer_*; a próxima batalha (selvagem ou
	# não) herdaria esse estado "preso" em true por engano (Ball falhando
	# sempre, time de Trainer errado spawnando de novo).
	if GameState.is_trainer_battle:
		log_message("You can't flee from a Trainer battle!")
		return
	# Segunda trava (a primeira é esconder flee_button durante o turno do
	# inimigo, ver begin_current_turn) — mesma checagem que _unhandled_input
	# já fazia pro atalho de teclado (Esc), só que o clique direto no BOTÃO
	# nunca passava por ali. Sem isso dava pra clicar Flee no meio de
	# run_enemy_turn() (ele fica suspenso num await de movimento/ataque da
	# IA) e crashar quando esse await retomasse com a cena de batalha já
	# destruída por baixo (change_scene_to_file logo abaixo).
	if get_current_unit() == null or get_current_unit().is_enemy:
		return
	# Terceira trava: mesmo durante o PRÓPRIO turno do jogador, um ataque/item
	# ainda pode estar animando (execute_attack e companhia rodam sem await
	# desde handle_targeting_input — ver action_in_progress/_run_player_*()).
	# flee_button já fica escondido nesse intervalo (mesmos wrappers), isso
	# aqui é só a segunda camada de segurança, igual a linha acima é a
	# segunda camada do guard de is_enemy.
	if action_in_progress:
		return
	get_tree().change_scene_to_file(GameState.overworld_scene_path)

func _on_undo_pressed() -> void:
	if phase != Phase.BATTLE:
		return
	var u = get_current_unit()
	if u == null:
		return
	deselect()
	cancel_targeting()
	u.teleport_to(turn_start_pos)
	move_budget_left = u.move_range

func handle_battle_input(clicked_cell: Vector2i, clicked_unit: Node) -> void:
	# _unhandled_input já não deixa chegar aqui durante turno de inimigo (ver
	# guarda lá) — checagem repetida por segurança, mesmo padrão do resto do
	# arquivo, caso algum caminho futuro chame isso direto sem passar por lá.
	var current = get_current_unit()
	if current == null or current.is_enemy:
		return
	# Só a unidade da vez pode ser selecionada — as outras (aliadas ou
	# inimigas) ainda não fazem nada quando clicadas.
	if clicked_unit and clicked_unit == get_current_unit():
		select_unit(clicked_unit)
	elif selected_unit and clicked_cell in highlighted_tiles:
		move_selected_unit(clicked_cell)
	else:
		deselect()

func select_unit(u: Node) -> void:
	clear_highlights()
	selected_unit = u
	highlighted_tiles = get_reachable_tiles(u.grid_pos, move_budget_left, u)
	highlight_tiles()

func move_selected_unit(target: Vector2i) -> void:
	# Distância REAL do caminho (calculada por get_reachable_tiles via BFS),
	# não a distância Chebyshev em linha reta — senão dava pra "atravessar"
	# um lago só por ele estar dentro do alcance em linha reta, mesmo sem
	# caminho de verdade até lá (o desvio em volta da água custa mais passos).
	var distance = move_distances.get(target, 0)
	move_budget_left = max(0, move_budget_left - distance)
	selected_unit.move_along_path(get_move_path_to(selected_unit.grid_pos, target))
	deselect()
	check_auto_end_turn()

# Reconstrói o caminho passo a passo (sem a origem, terminando em target),
# de trás pra frente, usando move_distances (preenchido pela última chamada
# de get_reachable_tiles()). Usado pra unidade ANDAR de verdade pelo caminho
# válido em vez de deslizar em linha reta por cima de parede/água/outra
# unidade — só a distância já respeitava o desvio, faltava a parte visual.
# (Nome não pode ser get_path_to: Node já tem um método nativo com esse nome
# e assinatura diferente — sobrescrever dava erro "function signature
# doesn't match the parent".)
#
# Diferente de simplesmente seguir "de quem essa célula foi descoberta" na
# BFS (o que dá QUALQUER caminho de custo mínimo, já que as 8 direções custam
# o mesmo passo — inclusive uns "em escada" tipo direita-baixo-direita-baixo
# em vez de uma diagonal só), aqui a cada célula a gente escolhe, entre TODOS
# os vizinhos que também estão exatamente 1 passo mais perto da origem, o que
# resulta no trajeto mais parecido com uma linha reta — ver
# path_step_score(). O custo final (quantidade de passos) é sempre o mesmo
# de qualquer jeito; isso só desempata a favor do caminho mais intuitivo.
func get_move_path_to(origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	if target == origin or not move_distances.has(target):
		return []

	var general_dir = Vector2i(sign(target.x - origin.x), sign(target.y - origin.y))
	var path: Array[Vector2i] = []
	var cell = target

	while cell != origin:
		path.append(cell)
		var current_dist = move_distances.get(cell, 0)
		var best_prev = origin
		var best_score = -INF
		var found = false

		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var prev = cell + Vector2i(dx, dy)
				var prev_dist = 0 if prev == origin else move_distances.get(prev, -1)
				if prev_dist != current_dist - 1:
					continue
				var score = path_step_score(cell - prev, general_dir)
				if not found or score > best_score:
					best_score = score
					best_prev = prev
					found = true

		if not found:
			return []   # não deveria acontecer se target está em move_distances
		cell = best_prev

	path.reverse()
	return path

# Pontua um passo (de `prev` pra a célula atual, como delta) contra a direção
# geral origin -> target, eixo por eixo: anda no mesmo sentido do eixo geral
# pontua 1, fica parado nesse eixo pontua 0 (neutro — só relevante quando o
# eixo geral também é 0, ou seja, o alvo está exatamente na mesma linha/coluna
# da origem, e queremos DESENCORAJAR sair dessa linha à toa), anda no sentido
# contrário pontua -1. Um passo diagonal que bate com os dois eixos ao mesmo
# tempo (score 2) sempre vence um passo ortogonal (score no máximo 1) — é
# assim que uma diagonal "reta" vence dois passos em escada de mesmo custo.
func path_step_score(step: Vector2i, general_dir: Vector2i) -> int:
	return path_axis_score(step.x, general_dir.x) + path_axis_score(step.y, general_dir.y)

func path_axis_score(step_component: int, dir_component: int) -> int:
	if dir_component == 0:
		return 0 if step_component == 0 else -1
	if step_component == dir_component:
		return 1
	if step_component == 0:
		return 0
	return -1

# BFS por 8 direções (todas custam 1 passo, igual nas 8 — bate com o sistema
# de sprites direcionais) até max_range passos. Isso, ao contrário de um
# simples quadrado Chebyshev ao redor de origin, respeita desvios reais: uma
# célula só entra em "reachable" se existir um CAMINHO até ela dentro do
# orçamento de movimento — não só se ela estiver perto em linha reta. É o que
# impede "teleportar" pro outro lado de um lago que a unidade não atravessa.
# Cortar uma diagonal encostando num canto de água/parede continua permitido
# de propósito — só a célula de destino de cada passo precisa ser passável.
func get_reachable_tiles(origin: Vector2i, max_range: int, u: Node) -> Array[Vector2i]:
	move_distances.clear()
	var allow_fluid = can_unit_cross_fluid(u)

	var visited := {origin: 0}
	var frontier: Array[Vector2i] = [origin]

	while not frontier.is_empty():
		var next_frontier: Array[Vector2i] = []
		for cell in frontier:
			var dist = visited[cell]
			if dist >= max_range:
				continue
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var n = cell + Vector2i(dx, dy)
					if n.x < 0 or n.x >= MAP_WIDTH or n.y < 0 or n.y >= MAP_HEIGHT:
						continue
					if visited.has(n):
						continue
					if wall_cells.has(n):
						continue
					if fluid_cells.has(n) and not allow_fluid:
						continue
					if get_unit_at(n) != null:
						continue   # ocupada — não dá pra passar por cima nem parar ali
					visited[n] = dist + 1
					next_frontier.append(n)
		frontier = next_frontier

	visited.erase(origin)
	move_distances = visited
	var reachable: Array[Vector2i] = []
	for cell in visited.keys():
		reachable.append(cell)
	return reachable

# ---------- IA de inimigos selvagens (QI 1) ----------
# Comportamento mais simples possível, do jeito que foi pedido: no turno de
# um inimigo selvagem, ele anda até ficar ao alcance de alguma unidade
# aliada e usa, entre os próprios ataques, o que causar MAIS dano contra
# quem ele conseguiu alcançar. calculate_damage() já embute efetividade de
# tipo/imunidade — é assim que "se o alvo for Dark, usa Tackle em vez de
# Confusion" sai de graça, sem nenhuma lógica extra: Confusion (Psychic)
# contra Dark dá 0 de dano ali dentro, então Tackle sempre vence a
# comparação de "maior dano" nessa hora. Se não conseguir alcançar ninguém
# neste turno (mesmo gastando todo o movimento), anda o máximo possível na
# direção do aliado mais próximo, sem atacar.
#
# begin_current_turn() chama isso no lugar de esperar clique do jogador
# sempre que a unidade da vez tem is_enemy == true; handle_battle_input() e
# _unhandled_input() têm guardas equivalentes pra impedir o jogador de
# clicar/atalhar por cima de um turno de IA em andamento (ver lá).
func run_enemy_turn(u: Node) -> void:
	var plan = plan_enemy_action(u)

	if plan.has("move_to") and plan["move_to"] != u.grid_pos:
		await move_unit_along_path(u, plan["move_to"])

	# Checagem defensiva — nada em move_unit_along_path() deveria terminar a
	# batalha hoje, mas é o mesmo padrão de segurança usado depois de todo
	# await que mexe em HP/turno no resto do arquivo (ver _on_end_turn_pressed).
	if phase != Phase.BATTLE:
		return

	if plan.has("attack"):
		var chosen_attack: AttackData = plan["attack"]
		if chosen_attack.is_status:
			# Ataque de Status (ver execute_status_attack): a IA "mirou" um
			# aliado específico (plan["target"]) só pra decidir SE dava pra
			# usar o ataque dali (is_valid_target_cell), mas a execução de
			# verdade mira uma DIREÇÃO — reconstrói a mesma direção 8-way a
			# partir de onde `u` já está (depois do move_unit_along_path acima)
			# até esse aliado, igual o jogador faz em handle_targeting_input.
			var target: Node = plan["target"]
			var dir = Vector2i(sign(target.grid_pos.x - u.grid_pos.x), sign(target.grid_pos.y - u.grid_pos.y))
			await execute_status_attack(u, chosen_attack, dir, plan["slot_index"])
		else:
			await execute_attack(u, plan["target"], chosen_attack, plan["slot_index"])
		if phase != Phase.BATTLE:
			return
	elif plan.has("ball_throw"):
		# Só a tática "Rocket" produz isso (ver _plan_rocket_action) —
		# captura a última unidade do jogador em vez de dar o golpe final
		# nela. execute_ball_throw já cuida de tudo (animação, gasto do
		# slot, resolve_capture) — mesmo caminho que o arremesso do
		# JOGADOR usa (ver _run_player_ball_throw).
		await execute_ball_throw(u, plan["target"].grid_pos, plan["ball_throw"], plan["slot_index"])
		if phase != Phase.BATTLE:
			return

	# execute_attack()/execute_ball_throw() já chamam check_auto_end_turn() sozinhos no final (pode
	# ter encerrado o turno ali, se move_budget_left TAMBÉM tivesse chegado a
	# 0) — só terminamos o turno de novo aqui se AINDA formos a unidade da
	# vez, senão avançaríamos current_turn_index duas vezes (mesma classe de
	# bug já corrigida uma vez em apply_end_of_turn_status/_on_end_turn_pressed).
	if get_current_unit() == u:
		_on_end_turn_pressed()

# Decide o que um inimigo faz no turno dele — despachante pro NÍVEL de IA
# certo (ver Unit.iq/UnitData.iq/Trainer.iq). Devolve um Dictionary, mesmo
# formato pras 4 táticas (ver cada uma pra detalhe):
# - {} (vazio): não pode nem se mover nem atacar (travado por status) — o
#   turno passa sem fazer nada.
# - {"move_to": cell}: não alcança ninguém pra atacar este turno; anda o
#   máximo possível em direção ao aliado mais próximo (ver _plan_approach).
# - {"move_to": cell, "attack": AttackData, "slot_index": int, "target": Node}:
#   posição (pode ser a própria posição atual) de onde atacar, o ataque
#   escolhido, e quem é o alvo.
# - {"move_to": cell, "ball_throw": ItemData, "slot_index": int, "target": Node}:
#   só a tática "Rocket" produz isso (ver _plan_rocket_action) — captura o
#   alvo em vez de bater nele.
#
# "Champion" ainda não tem tática própria (pedido do usuário: "Skip for
# now") — cai pra Medium por enquanto, junto com qualquer valor inesperado.
func plan_enemy_action(u: Node) -> Dictionary:
	match u.iq:
		"Easy":
			return _plan_easy_action(u)
		"Hard":
			return _plan_hard_action(u)
		"Rocket":
			return _plan_rocket_action(u)
		_:
			return _plan_medium_action(u)

# Reaproveitado pelas 4 táticas — quem do time do jogador ainda está de pé,
# e quais células `u` alcança neste turno. Inclui a própria posição atual
# como candidata de ataque (custo de movimento 0) — get_reachable_tiles()
# não devolve a origem no resultado dela, só o que está a 1+ passo.
# move_budget_left já vem 0 se a unidade não pode se mover (ver
# begin_current_turn/Unit.can_move()), não precisa checar de novo aqui.
func _get_ai_context(u: Node) -> Dictionary:
	var allies: Array = []
	for p in player_units:
		if p.hp_current > 0:
			allies.append(p)
	var reachable: Array[Vector2i] = []
	if move_budget_left > 0:
		reachable = get_reachable_tiles(u.grid_pos, move_budget_left, u)
	var candidate_cells: Array[Vector2i] = [u.grid_pos]
	candidate_cells.append_array(reachable)
	return {"allies": allies, "reachable": reachable, "candidate_cells": candidate_cells}

# Não alcançou ninguém pra atacar este turno — anda o máximo possível em
# direção ao aliado mais próximo. Escolhe, entre todas as células
# alcançáveis (a própria posição incluída), a que fica mais perto desse
# aliado (distância Chebyshev, mesma métrica do resto do movimento) — uma
# aproximação gulosa simples, não um replanejamento do caminho até ele.
# Usada pelas 4 táticas como fallback comum quando não sobra alvo válido.
func _plan_approach(u: Node, allies: Array, reachable: Array[Vector2i]) -> Dictionary:
	if reachable.is_empty():
		return {}   # travado por status ou já sem orçamento — nada a fazer

	var nearest = allies[0]
	for ally in allies:
		if chebyshev_distance(u.grid_pos, ally.grid_pos) < chebyshev_distance(u.grid_pos, nearest.grid_pos):
			nearest = ally

	var best_cell = u.grid_pos
	var best_cell_dist = chebyshev_distance(u.grid_pos, nearest.grid_pos)
	for cell in reachable:
		var d = chebyshev_distance(cell, nearest.grid_pos)
		if d < best_cell_dist:
			best_cell_dist = d
			best_cell = cell
	return {"move_to": best_cell}

func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

# ---------- Tática "Easy" ----------
# Pedido do usuário: "Big nerf from what we had previously. Units will
# select a random move to use and walk to the first target they can hit
# with that move and only enough to hit that move." — SEM otimizar dano
# nem posição nenhuma, de propósito:
#   1. sorteia UM slot de ataque usável (dano OU Status, tanto faz — "a
#      random move" não distingue os dois);
#   2. entre os aliados vivos, na ordem de sempre (player_units), pega o
#      PRIMEIRO que esse ataque alcança de ALGUMA célula candidata;
#   3. anda só até a célula candidata MAIS PERTO da posição atual que sirva
#      pra esse alvo (não a melhor posição possível — "only enough to hit").
# Se o ataque sorteado não alcançar ninguém (nem andando o máximo permitido),
# cai pra _plan_approach em vez de travar o turno inteiro parado — sem isso,
# uma unidade Easy má sorteada (ex: só tem um golpe de curto alcance e o
# alvo mais próximo está longe) ficaria parada pra sempre, mesmo turnos
# depois, o que não é "burra", é quebrada.
func _plan_easy_action(u: Node) -> Dictionary:
	var ctx = _get_ai_context(u)
	var allies: Array = ctx["allies"]
	var reachable: Array[Vector2i] = ctx["reachable"]
	var candidate_cells: Array[Vector2i] = ctx["candidate_cells"]
	if allies.is_empty():
		return {}

	if u.attacks_remaining > 0:
		var usable_slots: Array[int] = []
		for slot_index in u.data.slots.size():
			var action = u.data.slots[slot_index]
			# Taunted (ver comentário grande em refresh_action_slots_hud) — a
			# IA "Easy" também não pode sortear um golpe de Status enquanto
			# travada.
			# Disabled (ver Unit.disabled_attack) — mesmo espírito de Taunted
			# logo acima, mas travando só o golpe específico marcado, não
			# todo golpe de Status.
			if action is AttackData and not (action.is_status and u.has_status("Taunted")) and u.disabled_attack != action and (action.max_uses <= 0 or slot_index >= u.slot_uses.size() or u.slot_uses[slot_index] > 0):
				usable_slots.append(slot_index)

		if not usable_slots.is_empty():
			var slot_index: int = usable_slots[randi() % usable_slots.size()]
			var action: AttackData = u.data.slots[slot_index]

			# candidate_cells vem com a posição ATUAL primeiro (ver
			# _get_ai_context) e o resto na ordem "de descoberta" de
			# get_reachable_tiles() — reordenamos por distância aqui mesmo só
			# pra achar a célula "mais perto que serve" (pedido: "only enough
			# to hit that move"), sem afetar candidate_cells de ninguém mais.
			var sorted_cells := candidate_cells.duplicate()
			sorted_cells.sort_custom(func(a, b): return chebyshev_distance(u.grid_pos, a) < chebyshev_distance(u.grid_pos, b))

			for ally in allies:
				for cell in sorted_cells:
					if not is_valid_target_cell(cell, ally.grid_pos, action):
						continue
					if action.is_projectile and find_projectile_target(u, cell, ally.grid_pos, action.range) != ally:
						continue
					return {
						"move_to": cell, "attack": action,
						"slot_index": slot_index, "target": ally,
					}

	return _plan_approach(u, allies, reachable)

# ---------- Tática "Medium" ----------
# O comportamento que a IA sempre teve (por isso reaproveita quase tudo do
# antigo plan_enemy_action): pra cada ataque de DANO no loadout, testa todo
# aliado alcançável e fica com a combinação posição+ataque+alvo de MAIOR
# dano. Pedido do usuário: 1/8 de chance de, em vez disso, usar um ataque
# de Status num alvo válido qualquer (ver _pick_medium_status_action) —
# rolado ANTES da busca por dano, pra não competir com ela (um Status quase
# sempre "perde" a comparação de dano, já que calculate_damage nunca
# devolve menos que 1 — sem esse desvio explícito, ele praticamente nunca
# seria escolhido pela busca de maior dano sozinha).
func _plan_medium_action(u: Node) -> Dictionary:
	var ctx = _get_ai_context(u)
	var allies: Array = ctx["allies"]
	var reachable: Array[Vector2i] = ctx["reachable"]
	var candidate_cells: Array[Vector2i] = ctx["candidate_cells"]
	if allies.is_empty():
		return {}

	if u.attacks_remaining > 0 and randf() < 0.125:
		var status_plan = _pick_medium_status_action(u, allies, candidate_cells)
		if not status_plan.is_empty():
			return status_plan

	var best: Dictionary = {}
	if u.attacks_remaining > 0:
		var best_damage = -1
		for slot_index in u.data.slots.size():
			var action = u.data.slots[slot_index]
			if not (action is AttackData):
				continue   # Habilidade é passiva, nunca é "usada" ativamente
			if u.disabled_attack == action:
				continue   # Disabled (ver Unit.disabled_attack) — esse golpe específico está travado
			if action.max_uses > 0 and slot_index < u.slot_uses.size() and u.slot_uses[slot_index] <= 0:
				continue   # sem usos sobrando nesse slot
			for ally in allies:
				for cell in candidate_cells:
					if not is_valid_target_cell(cell, ally.grid_pos, action):
						continue
					# Projétil: só serve se ESSE aliado for realmente quem o
					# projétil acertaria primeiro na linha — mesma regra do
					# jogador (ver find_projectile_target/handle_targeting_input).
					if action.is_projectile and find_projectile_target(u, cell, ally.grid_pos, action.range) != ally:
						continue
					var damage = calculate_damage(u, ally, action)
					if damage > best_damage:
						best_damage = damage
						best = {
							"move_to": cell, "attack": action,
							"slot_index": slot_index, "target": ally,
						}

	if not best.is_empty():
		return best

	return _plan_approach(u, allies, reachable)

# Sorteia UM ataque de Status (is_status == true) usável do loadout, com
# pelo menos UMA combinação célula+alvo válida — se houver mais de uma
# combinação possível no total (vários aliados alcançáveis, ou vários
# Status diferentes), sorteia entre TODAS elas, não só entre os ataques
# (senão um Status com 3 alvos válidos teria a mesma chance que um com 1
# só, o que não é "aleatório" de verdade). Devolve {} se não houver Status
# nenhum usável agora — quem chama (_plan_medium_action/_plan_hard_action)
# cai de volta pra busca de maior dano normal nesse caso.
func _pick_medium_status_action(u: Node, allies: Array, candidate_cells: Array[Vector2i]) -> Dictionary:
	# Taunted — nem tenta escolher um golpe de Status enquanto travada (mesma
	# regra do jogador, ver refresh_action_slots_hud).
	if u.has_status("Taunted"):
		return {}
	var options: Array[Dictionary] = []
	for slot_index in u.data.slots.size():
		var action = u.data.slots[slot_index]
		if not (action is AttackData) or not action.is_status:
			continue
		if u.disabled_attack == action:
			continue   # Disabled (ver Unit.disabled_attack)
		if action.max_uses > 0 and slot_index < u.slot_uses.size() and u.slot_uses[slot_index] <= 0:
			continue
		for ally in allies:
			for cell in candidate_cells:
				if not is_valid_target_cell(cell, ally.grid_pos, action):
					continue
				options.append({
					"move_to": cell, "attack": action,
					"slot_index": slot_index, "target": ally,
				})
	if options.is_empty():
		return {}
	return options[randi() % options.size()]

# ---------- Tática "Hard" ----------
# As 3 funções abaixo (_best_possible_damage/_max_threat_range/
# _is_lethally_threatened_at) estimam "o pior que uma unidade DO JOGADOR
# poderia fazer neste turno" sem rodar get_reachable_tiles() de verdade pra
# ela — get_reachable_tiles() zera/reescreve move_distances, que
# move_unit_along_path() precisa intacto pra mover `u` (a unidade da vez
# de VERDADE) no final de plan_enemy_action; chamá-la de novo aqui, pra
# outra unidade, corromperia esse estado global. Em vez disso, usamos uma
# heurística de distância (Chebyshev, mesma métrica do resto do movimento):
# "alcance total" = move_range + o maior range de ataque no loadout,
# otimista sobre a posição de onde o golpe sairia. Não é uma simulação
# perfeita (ignora parede/unidade no caminho, formato de cone etc — mesma
# simplificação que _plan_approach já assume pro próprio movimento), só
# precisa ser boa o bastante pra "desviar da faixa de perigo" existir de
# verdade.

# Maior dano que `p` causaria em `defender` com QUALQUER ataque de dano do
# loadout dela — calculate_damage() não depende de posição/distância
# nenhuma (só stats/tipo), então isso é só "qual dos golpes dela bate mais
# forte nesse alvo", sem nenhuma checagem de alcance (ver _max_threat_range
# pra isso). -1 se `p` já estiver derrotada ou não tiver ataque de dano
# usável.
func _best_possible_damage(p: Node, defender: Node) -> int:
	if p.hp_current <= 0:
		return -1
	var best = -1
	for slot_index in p.data.slots.size():
		var action = p.data.slots[slot_index]
		if not (action is AttackData) or action.is_status:
			continue
		if p.disabled_attack == action:
			continue   # Disabled (ver Unit.disabled_attack)
		if action.max_uses > 0 and slot_index < p.slot_uses.size() and p.slot_uses[slot_index] <= 0:
			continue
		var damage = calculate_damage(p, defender, action)
		if damage > best:
			best = damage
	return best

# Ver comentário grande acima do bloco "Tática Hard" — alcance TOTAL
# otimista de `p` este turno (move_range + maior range de ataque no
# loadout), pra comparar contra distância Chebyshev em vez de rodar um BFS
# de verdade.
func _max_threat_range(p: Node) -> int:
	var max_range = 0
	for action in p.data.slots:
		if action is AttackData and not action.is_status and action.range > max_range:
			max_range = action.range
	return p.move_range + max_range

# `defender` ficaria ao alcance de um golpe FATAL de algum `p` em
# `threateners`, SE `defender` estivesse na célula `at_cell`? ("Fatal" =
# dano estimado >= HP atual de `defender` — mata de um golpe só.) Usado
# tanto pra saber se `u` está em perigo onde está quanto pra testar cada
# célula candidata de fuga.
func _is_lethally_threatened_at(defender: Node, at_cell: Vector2i, threateners: Array) -> bool:
	for p in threateners:
		if chebyshev_distance(p.grid_pos, at_cell) > _max_threat_range(p):
			continue
		if _best_possible_damage(p, defender) >= defender.hp_current:
			return true
	return false

# Primeiro `p` em `threateners` que ameaça matar `mate` de um golpe só
# NESTE turno — usado por _plan_hard_action pra escolher quem `u` foca no
# lugar do alvo de maior dano de sempre ("proteger aliado", pedido do
# usuário).
func _find_lethal_threatener(mate: Node, threateners: Array) -> Node:
	for p in threateners:
		if chebyshev_distance(p.grid_pos, mate.grid_pos) > _max_threat_range(p):
			continue
		if _best_possible_damage(p, mate) >= mate.hp_current:
			return p
	return null

# Entre as células alcançáveis por `u` este turno (a atual incluída), a
# primeira que NÃO fica na faixa de ataque fatal de nenhum `threatener` —
# null se não existir nenhuma (aí não tem pra onde fugir; _plan_hard_action
# cai pro comportamento normal de _plan_approach mesmo assim, é melhor
# andar em direção a alguém do que travar o turno).
func _find_safe_cell(u: Node, reachable: Array[Vector2i], threateners: Array) -> Variant:
	if not _is_lethally_threatened_at(u, u.grid_pos, threateners):
		return u.grid_pos
	for cell in reachable:
		if not _is_lethally_threatened_at(u, cell, threateners):
			return cell
	return null

# Busca de ataque igual à do Medium (maior dano por combinação alvo+célula
# alcançável), com um adicional: se `avoid_danger` for true, uma célula que
# deixaria `u` na mira de um golpe fatal (ver _is_lethally_threatened_at)
# perde o DESEMPATE contra uma célula de mesmo dano que não deixa — nunca
# troca dano por segurança sozinho (dano pesa mais no score, ver `* 2`
# abaixo), só decide entre jogadas igualmente boas. Reaproveitada pelas
# duas tentativas de _plan_hard_action (alvo prioritário de defesa e,
# se esse não alcançar ninguém, todos os alvos).
func _search_best_attack(u: Node, targets: Array, candidate_cells: Array[Vector2i], threateners: Array, avoid_danger: bool) -> Dictionary:
	if u.attacks_remaining <= 0:
		return {}
	var best: Dictionary = {}
	var best_score = -1
	for slot_index in u.data.slots.size():
		var action = u.data.slots[slot_index]
		if not (action is AttackData) or action.is_status:
			continue
		if u.disabled_attack == action:
			continue   # Disabled (ver Unit.disabled_attack)
		if action.max_uses > 0 and slot_index < u.slot_uses.size() and u.slot_uses[slot_index] <= 0:
			continue
		for target in targets:
			for cell in candidate_cells:
				if not is_valid_target_cell(cell, target.grid_pos, action):
					continue
				if action.is_projectile and find_projectile_target(u, cell, target.grid_pos, action.range) != target:
					continue
				var damage = calculate_damage(u, target, action)
				var danger = avoid_danger and _is_lethally_threatened_at(u, cell, threateners)
				var score = damage * 2 + (0 if danger else 1)
				if score > best_score:
					best_score = score
					best = {
						"move_to": cell, "attack": action,
						"slot_index": slot_index, "target": target,
					}
	return best

# Pedido do usuário (resumo): além de maximizar dano (igual Medium), essa
# tática também se PROTEGE e protege o time:
#   1. Se `u` está na mira de um golpe fatal de algum inimigo que ainda vai
#      jogar nesta rodada, e não sobra ataque melhor que valha o risco,
#      foge pra uma célula fora dessa faixa em vez do "anda em direção ao
#      mais próximo" padrão.
#   2. Se um ALIADO (outra unidade do mesmo time de `u`) está sob risco de
#      morrer pra um golpe fatal pendente, `u` foca o inimigo que ameaça
#      esse aliado, no lugar do alvo de maior dano de sempre.
#   3. Ordem de turno: só quem ainda vai jogar NESTA rodada (ver
#      turn_queue/current_turn_index) conta como ameaça — quem já agiu só
#      volta a ameaçar de novo na rodada seguinte.
func _plan_hard_action(u: Node) -> Dictionary:
	var ctx = _get_ai_context(u)
	var targets: Array = ctx["allies"]          # unidades do jogador = alvos de `u`
	var reachable: Array[Vector2i] = ctx["reachable"]
	var candidate_cells: Array[Vector2i] = ctx["candidate_cells"]
	if targets.is_empty():
		return {}

	var teammates: Array = []
	for e in enemy_units:
		if e != u and e.hp_current > 0:
			teammates.append(e)

	var pending_targets: Array = []
	for t in targets:
		var idx = turn_queue.find(t)
		if idx != -1 and idx >= current_turn_index:
			pending_targets.append(t)

	var priority_target: Node = null
	for mate in teammates:
		var threatener = _find_lethal_threatener(mate, pending_targets)
		if threatener != null:
			priority_target = threatener
			break   # primeiro aliado ameaçado já basta — não hierarquiza vários em perigo ao mesmo tempo

	var best := _search_best_attack(u, [priority_target] if priority_target != null else targets, candidate_cells, pending_targets, true)
	# priority_target inalcançável de lugar nenhum -> tenta com todos os
	# alvos, igual Medium faria, em vez de deixar `u` parado à toa.
	if best.is_empty() and priority_target != null:
		best = _search_best_attack(u, targets, candidate_cells, pending_targets, true)

	if not best.is_empty():
		return best

	if _is_lethally_threatened_at(u, u.grid_pos, pending_targets):
		var safe_cell = _find_safe_cell(u, reachable, pending_targets)
		if safe_cell != null and safe_cell != u.grid_pos:
			return {"move_to": safe_cell}

	return _plan_approach(u, targets, reachable)

# ---------- Tática "Rocket" ----------
# Pedido do usuário: "Same as medium, but with a special feature." — a
# parte "igual Medium" é literal (reaproveita _plan_medium_action inteira,
# dano máximo + a mesma chance de 1/8 de Status). O especial: toda unidade
# de um time Rocket ganha 1 Rocket Ball no loadout (ver spawn_enemies/
# _spawn_enemy_unit, ROCKET_BALL_ITEM, mais abaixo).
#
# O time Rocket joga NORMAL (bate pra derrotar, igual Medium) enquanto o
# jogador ainda tiver MAIS de uma unidade — só quando resta a ÚLTIMA
# (player_units.size() == 1) é que a Rocket Ball entra em jogo: SE o golpe
# que _plan_medium_action escolheu for justamente o GOLPE FINAL que
# derrotaria essa última unidade (dano calculado >= HP dela), a unidade usa
# a Ball nesse alvo em vez de bater nele — captura em vez de derrotar (ver
# resolve_capture, que trata `defender.is_enemy == false` como esse caso
# exato — captura sempre sucede, sem fórmula nenhuma, e vai pra
# GameState.giovanni_storage em vez da reserva normal do jogador). Pedido
# do usuário, depois de testar uma versão anterior que capturava a
# PRIMEIRA unidade que desse (errado): "it should defeat every unit but
# one and THEN capture the last one if it COULD deal a lethal attack. It
# will only throw a ball if it has an attack that would finish the fight
# if it lands on the last unit" — dano normal em qualquer unidade que NÃO
# seja a última, Ball só na última E só se fosse mesmo terminar a luta ali.
#
# Uma versão intermediária chegou a bloquear a captura da última unidade
# por completo (medo de zerar GameState.roster e travar o jogo) — não é
# mais necessário: resolve_capture já tira a UnitData do roster de verdade
# antes de guardá-la em giovanni_storage (ver GameState.remove_from_roster),
# então terminar a batalha com o roster inteiro vazio agora é só uma
# derrota comum (mesmo end_battle(victory=false) de sempre), não um estado
# quebrado.
func _plan_rocket_action(u: Node) -> Dictionary:
	var best = _plan_medium_action(u)

	if not best.has("attack") or best["attack"].is_status:
		return best   # sem golpe de dano nenhum escolhido — nada pra trocar por captura
	if player_units.size() != 1:
		return best   # ainda sobra outra unidade DE PÉ além dessa — bate normal, Ball só vale pra última

	# Bug reportado pelo usuário: "the bug where rocket catches the ONLY
	# member of the active team is still happening" — player_units.size()
	# == 1 acima só diz "só uma unidade ainda está de pé NESTA batalha", o
	# que é verdade também quando o time INTEIRO do jogador sempre foi
	# aquela única unidade (nunca teve companheiro nenhum, vivo ou
	# desmaiado). Regra corrigida do usuário: "The rocket trainer will only
	# catch the last remaining unit alive IF and ONLY IF, there are other
	# active units on the team. (Even if they are fainted)" — o que importa
	# é o TIME ATIVO inteiro (GameState.roster, slots não-nulos — desmaiado
	# ainda conta, só reserva do PC/Giovanni é que não), não só quem
	# continua de pé na batalha agora. Sem essa segunda trava, um jogador
	# com um único membro no time (o caso mais perigoso de todos, ver
	# comentário grande acima sobre zerar o roster) tinha essa mesma
	# unidade capturada na primeira oportunidade.
	var active_team_size := 0
	for d in GameState.roster:
		if d != null:
			active_team_size += 1
	if active_team_size <= 1:
		return best   # essa É o time inteiro do jogador — nunca captura, bate normal mesmo

	var target: Node = best["target"]
	var attack: AttackData = best["attack"]
	if calculate_damage(u, target, attack) < target.hp_current:
		return best   # esse golpe não terminaria com a unidade — bate normal mesmo

	var ball_slot_index = -1
	var ball_item: ItemData = null
	for slot_index in u.data.slots.size():
		var action = u.data.slots[slot_index]
		if action is ItemData and action.category == "Ball":
			ball_slot_index = slot_index
			ball_item = action
			break
	if ball_item == null:
		return best   # sem Ball no loadout (não devia acontecer numa equipe Rocket de verdade, ver spawn_enemies) — bate normal

	# A célula que _plan_medium_action escolheu pode não servir pra Ball —
	# Ball exige linha reta (ver is_valid_target_cell), um Cone por exemplo
	# não. Tenta a mesma célula primeiro (caso comum: ataque reto também),
	# senão procura entre as candidatas de novo, agora só pra Ball.
	var ctx = _get_ai_context(u)
	var candidate_cells: Array[Vector2i] = ctx["candidate_cells"]
	var throw_cells: Array[Vector2i] = [best["move_to"]]
	for cell in candidate_cells:
		if cell != best["move_to"]:
			throw_cells.append(cell)

	for cell in throw_cells:
		if not is_valid_target_cell(cell, target.grid_pos, ball_item):
			continue
		if find_ball_target(u, cell, target.grid_pos, ball_item.range)["unit"] != target:
			continue
		return {
			"move_to": cell, "ball_throw": ball_item,
			"slot_index": ball_slot_index, "target": target,
		}

	return best   # não achou de onde arremessar em linha reta — bate normal mesmo

# Move `u` até `target` — uma célula alcançável dentro do orçamento de
# movimento ATUAL (ver plan_enemy_action, que preenche move_distances via
# get_reachable_tiles logo antes de devolver o plano) — e só retorna quando a
# caminhada termina DE VERDADE na tela, pra IA não disparar o ataque em cima
# da animação de andar ainda rolando. Mesmo desconto de move_budget_left que
# move_selected_unit() faz pro jogador, só que sem esperar clique nenhum.
func move_unit_along_path(u: Node, target: Vector2i) -> void:
	var distance = move_distances.get(target, 0)
	move_budget_left = max(0, move_budget_left - distance)
	u.move_along_path(get_move_path_to(u.grid_pos, target))
	while u.is_moving:
		await get_tree().process_frame

# ---------- Comum às duas fases ----------

func deselect() -> void:
	selected_unit = null
	highlighted_tiles = []
	move_distances.clear()
	clear_highlights()

func highlight_tiles() -> void:
	for cell in highlighted_tiles:
		highlight_layer.set_cell(cell, 0, Vector2i(13, 1))

func clear_highlights() -> void:
	highlight_layer.clear()
