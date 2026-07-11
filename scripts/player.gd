extends Node2D

# Movimento do personagem principal do overworld: passo a passo, travado no
# grid do TileMapLayer — no espírito do grid de batalha (ver Unit.gd), mas
# só com 4 direções (baixo/cima/esquerda/direita). As spritesheets desse
# personagem (assets/sprites/Human) não têm poses diagonais como as dos
# sprites de batalha (que são 8 direções), por isso a diferença.

# Antes isso era @export (setado via NodePath na mão em world.tscn), mas
# node exports tipados só resolvem de node de verdade quando atribuídos
# PELO editor do Godot (arrastando o node no Inspector) — escrever o
# NodePath direto no .tscn deixa a propriedade null em runtime, foi isso
# que causou o erro "Cannot call method 'map_to_local' on a null value".
# get_node() aqui resolve na hora — Player mora dentro de "Actors" (Node2D
# com y_sort_enabled = true, ver world.gd/world.tscn: é o que resolve o
# personagem desenhar na ordem errada perto de um NPC), que por sua vez é
# filho direto de World, o mesmo Node2D que tem o TileMapLayer chamado
# "TileMapLayer" — daí o "../.." (sobe de Player pra Actors, de Actors pra
# World). Se um dia o Player for reusado em outra cena com estrutura
# diferente, isso precisa generalizar.
@onready var tile_map: TileMapLayer = get_node("../../TileMapLayer")

# Mesmo motivo/padrão do tile_map acima — World (ver world.gd::has_npc_at,
# usado em can_move_to() lá embaixo pra bloquear o passo em cima de um NPC
# parado) fica DOIS níveis acima do Player agora (Player -> Actors -> World).
@onready var world: Node2D = get_node("../..")

# Antes (ver git blame se quiser comparar) essas três eram @export Texture2D,
# arrastadas à mão no Inspector de player.tscn — funcionava porque só
# existia UM personagem possível. Assim que precisamos escolher entre boy/
# girl (ver GameState.player_gender), isso parou de fazer sentido: um export
# fixo no .tscn não pode variar por escolha feita em RUNTIME (a escolha de
# gênero só existe depois que o jogo já está rodando, não em tempo de
# edição). A solução é a mesma usada em qualquer lugar que precisa "montar
# algo a partir de um dado que só se sabe depois": carregar a textura certa
# via load(caminho) dentro de _ready(), lendo o caminho de uma TABELA
# (SHEETS_BY_GENDER logo abaixo) em vez de deixar o Godot resolver o
# ext_resource sozinho. Por isso essas três viraram var comuns (sem @export)
# — não aparecem mais no Inspector, quem preenche é _load_sheets_for_gender().
var walk_sheet: Texture2D   # trainer_POKEMONTRAINER_Red/Leaf.png — dá idle E walk
var run_sheet: Texture2D    # boy_run.png / girl_run.png — só run, sem pose parada
var bike_sheet: Texture2D   # boy_bike.png / girl_bike.png — só bike, sem pose parada (mesmo espírito de run_sheet)

# Caminho de cada spritesheet por gênero — a MESMA convenção de arquivo do
# boy (boy_run/boy_bike) não existe pro walk (que usa o nome do trainer de
# origem, trainer_POKEMONTRAINER_Red/Leaf), por isso isso é uma tabela
# explícita em vez de um prefixo string trocado ("boy_" -> "girl_") aplicado
# em cima de um nome só: walk quebraria essa convenção. Leaf escolhida como
# contraparte de Red (mesmo jogo de origem, FireRed/LeafGreen) — May também
# existe na pasta como alternativa, caso o usuário troque de ideia depois.
const SHEETS_BY_GENDER = {
	"boy": {
		"walk": "res://assets/sprites/Human/Main Character/trainer_POKEMONTRAINER_Red.png",
		"run": "res://assets/sprites/Human/Main Character/boy_run.png",
		"bike": "res://assets/sprites/Human/Main Character/boy_bike.png",
	},
	"girl": {
		"walk": "res://assets/sprites/Human/Main Character/trainer_POKEMONTRAINER_Leaf.png",
		"run": "res://assets/sprites/Human/Main Character/girl_run.png",
		"bike": "res://assets/sprites/Human/Main Character/girl_bike.png",
	},
}

# As duas spritesheets seguem o layout clássico de charset (RPG Maker XP):
# 4 colunas (quadros do ciclo) x 4 linhas (direção), nessa ordem de linha —
# confirmado pelo usuário, não é o mesmo esquema de baixo/direita/cima/
# esquerda usado nos sprites de batalha.
const SHEET_DIRECTIONS = ["down", "left", "right", "up"]
const FRAMES_PER_CYCLE = 4

# Frame do ciclo de walk usado como pose "parada" (idle) — index 0 (1º
# quadro) ou 2 (3º quadro) servem, os dois são poses paradas no meio do
# ciclo de passos. Troque pra 2 se a pose com index 0 ficar estranha.
const IDLE_FRAME_INDEX = 0

# Duração (não velocidade em pixels/segundo) — assim o "tempo pra atravessar
# 1 tile" fica fixo não importa o tamanho real do tile (que ainda podia
# mudar enquanto o TileSet tava sendo ajustado). Correndo, o mesmo trajeto
# leva menos tempo; de bicicleta, metade do tempo de correr (2x a velocidade
# de Run, ver BIKE_DURATION).
const MOVE_DURATION = 0.22   # segundos pra atravessar 1 tile andando
const RUN_DURATION = 0.11    # segundos pra atravessar 1 tile correndo
const BIKE_DURATION = RUN_DURATION / 2.0   # segundos pra atravessar 1 tile de bike (2x Run)

# Emitido quando a unidade TERMINA de entrar numa célula nova (não quando só
# vira de direção sem poder andar). world.gd escuta isso pra decidir coisas
# que dependem do tile em que o personagem pisou (ex: grama alta -> chance
# de combate aleatório).
signal tile_entered(cell: Vector2i)

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var grid_pos: Vector2i = Vector2i.ZERO
var facing: String = "down"
var is_moving: bool = false
var is_running: bool = false
# Espelha GameState.is_biking (ver comentário lá) — NÃO é uma tecla segurada
# (diferente de is_running/"run"): liga/desliga usando o item Bicycle na Bag
# (ver GameState.use_tool), um toggle persistente que sobrevive à troca de
# cena. _sync_biking_state(), chamado todo _process, é quem mantém essa
# cópia local em dia — Player só LÊ GameState.is_biking, nunca escreve nele
# diretamente (quem escreve é sempre GameState.use_tool).
var is_biking: bool = false

# Estado do passo atual em andamento — origem/destino em pixels e quanto
# tempo já passou, pra interpolar center-a-center numa duração fixa (ver
# MOVE_DURATION/RUN_DURATION) em vez de uma velocidade em pixels/segundo.
var move_start: Vector2 = Vector2.ZERO
var move_target: Vector2 = Vector2.ZERO
var move_elapsed: float = 0.0
var move_duration: float = MOVE_DURATION

func _ready() -> void:
	is_biking = GameState.is_biking   # já nasce de bike se o jogador tinha ligado antes (ver comentário do var)
	_load_sheets_for_gender()
	anim.sprite_frames = build_sprite_frames()
	_align_sprite_to_tile()
	_setup_sink_shader()
	position = tile_map.map_to_local(grid_pos)
	anim.play(_idle_anim_name())

# O shader de afundar na grama (sink_in_grass.gdshader) precisa saber, em
# fração do atlas inteiro (walk_sheet/run_sheet), onde o quadro ATUAL fica
# — ele muda de quadro (e de linha do atlas, ao trocar de direção) o tempo
# todo, então isso tem que recalcular sempre que o quadro ou a animação
# mudar, não só uma vez.
func _setup_sink_shader() -> void:
	anim.frame_changed.connect(_update_sink_shader_region)
	anim.animation_changed.connect(_update_sink_shader_region)
	_update_sink_shader_region()

func _update_sink_shader_region() -> void:
	if not (anim.material is ShaderMaterial):
		return
	if anim.sprite_frames == null or anim.animation == "":
		return
	var current_texture = anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)
	if not (current_texture is AtlasTexture):
		return

	var atlas_texture := current_texture as AtlasTexture
	var atlas_size = atlas_texture.atlas.get_size()
	var region = atlas_texture.region
	var region_rect = Vector4(
		region.position.x / atlas_size.x,
		region.position.y / atlas_size.y,
		region.size.x / atlas_size.x,
		region.size.y / atlas_size.y
	)
	anim.material.set_shader_parameter("region_rect", region_rect)

# AnimatedSprite2D com centered=true (o padrão) desenha o quadro com o MEIO
# dele em cima de position. Em vez de chutar/ajustar esse offset no olho, a
# gente CALCULA: lê os pixels de verdade do quadro parado (idle, "down") e
# acha a última linha com algum pixel visível — essa linha É o pé do
# personagem no desenho, padding nenhum interessa. Só usamos o valor manual
# abaixo (foot_offset_ratio) como fallback, pro caso da textura estar
# importada como "VRAM Compressed" (aí get_image() não funciona em runtime).
@export_range(0.0, 0.5, 0.01) var foot_offset_ratio: float = 0.15

# Assume que walk_sheet, run_sheet e bike_sheet têm a mesma altura de quadro
# (mesmo personagem, três poses) — se um dia usarem tamanhos diferentes,
# isso precisa recalcular por animação em vez de um offset global só.
func _align_sprite_to_tile() -> void:
	@warning_ignore("integer_division")
	var frame_w = walk_sheet.get_width() / FRAMES_PER_CYCLE
	@warning_ignore("integer_division")
	var frame_h = walk_sheet.get_height() / SHEET_DIRECTIONS.size()
	var tile_h = tile_map.tile_set.tile_size.y

	var foot_row = _find_foot_row(walk_sheet, frame_w, frame_h)
	if foot_row < 0:
		anim.offset = Vector2(0, -frame_h / 2.0 + frame_h * foot_offset_ratio)
		return

	# centered=true desenha o quadro com o MEIO dele em cima de position, e
	# só depois soma offset. Uma linha de pixel "row" (contada do topo do
	# quadro, 0-based) acaba, sem nenhum offset, na posição local
	# (row - frame_h/2). Queremos que a linha do pé (foot_row) caia
	# exatamente na borda de baixo do tile — que fica em tile_h/2, já que a
	# origem do Player é o CENTRO da célula (ver map_to_local em _ready()).
	# Isolando offset.y da equação (row - frame_h/2) + offset.y == tile_h/2:
	var offset_y = (tile_h / 2.0) - foot_row + (frame_h / 2.0)
	anim.offset = Vector2(0, offset_y)

# Varre de baixo pra cima o quadro parado (linha "down", coluna
# IDLE_FRAME_INDEX de walk_sheet) procurando a primeira linha com algum
# pixel de alpha visível — essa é a linha mais baixa com desenho de
# verdade, ou seja, onde o pé encosta. Retorna -1 se a textura não puder
# ser lida como Image em runtime (texturas "VRAM Compressed" não suportam
# get_image() depois de importadas — troque o Import Mode pra "Lossless"
# ou "Lossy" no painel Import se isso acontecer).
func _find_foot_row(sheet: Texture2D, frame_w: int, frame_h: int) -> int:
	var image = sheet.get_image()
	if image == null:
		return -1
	image.decompress()

	var origin_x = IDLE_FRAME_INDEX * frame_w   # coluna do quadro parado
	var origin_y = 0                            # linha "down" é a 1ª do atlas
	const ALPHA_THRESHOLD = 0.05

	for y in range(frame_h - 1, -1, -1):
		for x in frame_w:
			if image.get_pixel(origin_x + x, origin_y + y).a > ALPHA_THRESHOLD:
				return y
	return frame_h - 1   # quadro inteiro transparente — não devia acontecer

# Preenche walk_sheet/run_sheet/bike_sheet lendo GameState.player_gender —
# chamado uma vez em _ready(), ANTES de build_sprite_frames() (que só sabe
# fatiar o que já está carregado aqui). .get(..., SHEETS_BY_GENDER["boy"])
# cai pro boy também se um dia player_gender vier com um valor inesperado
# (string digitada errado em algum save antigo, por exemplo) em vez de
# quebrar com um load(null).
func _load_sheets_for_gender() -> void:
	var sheets: Dictionary = SHEETS_BY_GENDER.get(GameState.player_gender, SHEETS_BY_GENDER["boy"])
	walk_sheet = load(sheets["walk"])
	run_sheet = load(sheets["run"])
	bike_sheet = load(sheets["bike"])

# Monta o SpriteFrames inteiro (idle/walk/run/bike x 4 direções) na hora, a
# partir das três texturas brutas — em vez de um .tres com AtlasTexture
# fatiado à mão (que exigiria saber o tamanho em pixel de cada quadro de
# antemão). frame_w/frame_h saem da divisão do tamanho REAL da textura por
# 4 colunas / 4 linhas, então funciona não importa a resolução real das
# spritesheets.
func build_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	_add_walk_and_idle(frames, walk_sheet)
	_add_run(frames, run_sheet)
	_add_bike(frames, bike_sheet)
	return frames

func _add_walk_and_idle(frames: SpriteFrames, sheet: Texture2D) -> void:
	@warning_ignore("integer_division")
	var frame_w = sheet.get_width() / FRAMES_PER_CYCLE
	@warning_ignore("integer_division")
	var frame_h = sheet.get_height() / SHEET_DIRECTIONS.size()

	for row in SHEET_DIRECTIONS.size():
		var dir = SHEET_DIRECTIONS[row]
		_start_animation(frames, "walk_" + dir, 8.0)
		_start_animation(frames, "idle_" + dir, 5.0)
		for col in FRAMES_PER_CYCLE:
			var atlas = AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame("walk_" + dir, atlas)
			if col == IDLE_FRAME_INDEX:
				frames.add_frame("idle_" + dir, atlas)

func _add_run(frames: SpriteFrames, sheet: Texture2D) -> void:
	@warning_ignore("integer_division")
	var frame_w = sheet.get_width() / FRAMES_PER_CYCLE
	@warning_ignore("integer_division")
	var frame_h = sheet.get_height() / SHEET_DIRECTIONS.size()

	for row in SHEET_DIRECTIONS.size():
		var dir = SHEET_DIRECTIONS[row]
		_start_animation(frames, "run_" + dir, 12.0)
		for col in FRAMES_PER_CYCLE:
			var atlas = AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame("run_" + dir, atlas)

# Mesma ideia de _add_run() acima, só que pra bike_sheet. TAMBÉM monta
# idle_bike_<dir> (1º quadro do ciclo, mesmo IDLE_FRAME_INDEX de
# _add_walk_and_idle) — diferente de run_sheet (que não precisa de pose
# parada, já que ninguém fica "parado correndo"), bike_sheet precisa:
# enquanto is_biking for true, a pose parada do personagem passa a ser esta,
# não a de walk_sheet (ver _idle_anim_name()).
#
# O valor 10.0 abaixo é o FPS (quadros por segundo) do ciclo de pedalada —
# quer mais rápido/devagar? É só mudar esse número (mesma ideia pro walk_
# em _add_walk_and_idle, 8.0, e run_ em _add_run, 12.0). Repare que isso é
# INDEPENDENTE de BIKE_DURATION (velocidade de MOVIMENTO, quanto tempo leva
# pra atravessar 1 tile) — mudar um não muda o outro.
func _add_bike(frames: SpriteFrames, sheet: Texture2D) -> void:
	@warning_ignore("integer_division")
	var frame_w = sheet.get_width() / FRAMES_PER_CYCLE
	@warning_ignore("integer_division")
	var frame_h = sheet.get_height() / SHEET_DIRECTIONS.size()

	for row in SHEET_DIRECTIONS.size():
		var dir = SHEET_DIRECTIONS[row]
		# 10.0, mais devagar que run (12.0) mesmo a bike andando 2x mais rápido
		# (ver BIKE_DURATION) — velocidade de ANIMAÇÃO (troca de quadro) e
		# velocidade de MOVIMENTO (duração do tile) são coisas independentes;
		# 16.0 deixava o pedal "picotado"/frenético demais aos olhos do usuário.
		_start_animation(frames, "bike_" + dir, 10.0)
		_start_animation(frames, "idle_bike_" + dir, 5.0)
		for col in FRAMES_PER_CYCLE:
			var atlas = AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			frames.add_frame("bike_" + dir, atlas)
			if col == IDLE_FRAME_INDEX:
				frames.add_frame("idle_bike_" + dir, atlas)

func _start_animation(frames: SpriteFrames, anim_name: String, speed: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, true)
	frames.set_animation_speed(anim_name, speed)

func _process(delta: float) -> void:
	_sync_biking_state()
	if is_moving:
		_continue_move(delta)
	else:
		_try_start_move()

# Espelha GameState.is_biking (ver comentário do var is_biking) — chamado
# todo frame porque o toggle pode acontecer a qualquer momento (usar a
# Bicycle na Bag, ver GameState.use_tool) sem o Player saber diretamente.
# Só troca a animação na hora se a unidade estiver PARADA — se estiver no
# meio de um passo (is_moving), o passo atual termina do jeito que começou
# (ver _try_start_move, que já lê o is_biking atualizado no PRÓXIMO passo);
# trocar o sprite no meio do slide ficaria estranho.
func _sync_biking_state() -> void:
	if GameState.is_biking == is_biking:
		return
	is_biking = GameState.is_biking
	if not is_moving:
		anim.play(_idle_anim_name())

# Nome da animação parada certa pra AGORA — idle_bike_<direção> enquanto
# is_biking for true (1º quadro de bike_sheet, ver _add_bike), idle_<direção>
# (1º quadro de walk_sheet) caso contrário. Centraliza essa escolha num só
# lugar em vez de repetir o ternário em cada anim.play("idle...") espalhado
# pelo arquivo.
func _idle_anim_name() -> String:
	return ("idle_bike_" if is_biking else "idle_") + facing

# Só considera um passo novo quando a unidade está parada — sem "buffer" de
# input ainda. Segurando a direção, o próximo passo começa sozinho assim que
# o atual termina, porque essa função roda de novo no frame seguinte.
#
# Apertar uma direção DIFERENTE da que o personagem já está encarando só
# gira ele no lugar (1 frame de atraso) — não anda de cara. Só quando a
# direção apertada já é a mesma do facing atual (ou seja: o giro do passo
# anterior já aconteceu) é que o passo de verdade começa. Isso é o que faz
# um toque rápido de direção (solta antes do próximo _process) virar só um
# giro, e segurar a tecla virar "gira, depois anda continuamente" — mesmo
# comportamento clássico de jogo Pokémon.
func _try_start_move() -> void:
	var dir = read_direction()
	if dir == Vector2i.ZERO:
		# Ninguém segurando direção nenhuma — mostra parado. Isso (e não mais
		# _continue_move) é quem decide "parar de andar" agora, ver comentário
		# grande em _continue_move sobre por que o play(idle) saiu de lá.
		anim.play(_idle_anim_name())
		return

	var new_facing = direction_to_facing(dir)
	if new_facing != facing:
		facing = new_facing
		anim.play(_idle_anim_name())
		return

	var target_cell = grid_pos + dir

	if not can_move_to(target_cell):
		anim.play(_idle_anim_name())   # já estava de frente, mas não pode andar pra lá (parede etc.)
		return

	grid_pos = target_cell
	is_running = Input.is_action_pressed("run")
	move_start = position
	move_target = tile_map.map_to_local(grid_pos)
	move_elapsed = 0.0
	move_duration = BIKE_DURATION if is_biking else (RUN_DURATION if is_running else MOVE_DURATION)
	is_moving = true
	var prefix = "bike_" if is_biking else ("run_" if is_running else "walk_")
	anim.play(prefix + facing)

func _continue_move(delta: float) -> void:
	move_elapsed += delta
	var t = clamp(move_elapsed / move_duration, 0.0, 1.0)
	position = move_start.lerp(move_target, t)
	if t >= 1.0:
		is_moving = false
		# NÃO troca pra idle aqui — antes trocava (anim.play(_idle_anim_name())),
		# mas isso interrompia o ciclo de walk/run/bike a CADA passo: se a
		# direção continuasse segurada, _try_start_move (no próximo _process)
		# tocava o mesmo prefix+facing de novo — só que como o AnimatedSprite2D
		# tinha acabado de trocar pra uma animação DIFERENTE (idle), o Godot
		# reinicia do quadro 0 ao voltar (play() só continua de onde parou se
		# for a MESMA animação já tocando; muda de animação sempre volta pro
		# quadro 0). Passo a passo, isso reiniciava o ciclo toda vez — imperceptível
		# em MOVE_DURATION/RUN_DURATION (dá tempo de trocar de quadro antes do
		# próximo passo reiniciar), mas em BIKE_DURATION (bem mais curto) o
		# ciclo nunca chegava a sair do quadro 0 => parecia "travado". Agora
		# quem decide mostrar idle é só _try_start_move(), no frame em que
		# realmente não há mais passo nenhum pra continuar (dir == ZERO,
		# virou de direção, ou bateu em algo) — segurando a tecla, o mesmo
		# nome de animação continua tocando sem interrupção entre um passo e
		# o próximo, preservando o quadro atual do ciclo.
		tile_entered.emit(grid_pos)

# Direção lida das ações padrão ui_up/down/left/right (setas do teclado, já
# vêm configuradas por padrão em qualquer projeto Godot). Se duas teclas
# perpendiculares estiverem pressionadas ao mesmo tempo, prioriza vertical
# sobre horizontal — critério simples, dá pra ajustar depois se incomodar.
func read_direction() -> Vector2i:
	if Input.is_action_pressed("ui_up"):
		return Vector2i.UP
	if Input.is_action_pressed("ui_down"):
		return Vector2i.DOWN
	if Input.is_action_pressed("ui_left"):
		return Vector2i.LEFT
	if Input.is_action_pressed("ui_right"):
		return Vector2i.RIGHT
	return Vector2i.ZERO

func direction_to_facing(dir: Vector2i) -> String:
	if dir == Vector2i.UP:
		return "up"
	if dir == Vector2i.DOWN:
		return "down"
	if dir == Vector2i.LEFT:
		return "left"
	return "right"

# Checagem de colisão de verdade agora: cada tile tem um campo de dado
# customizado "walkable" (bool), configurado no editor do TileSet (aba
# "Custom Data" -> pinta "walkable" = true nos tiles andáveis). Célula sem
# tile nenhum (tile_data null) ou tile marcado como não-andável (inclusive
# o padrão, que é false, se ninguém configurar nada) bloqueia o passo — é
# assim que troncos de árvore, água, etc. vão travar o personagem mais pra
# frente, no mesmo espírito de wall_cells/fluid_cells em battle.gd.
func can_move_to(cell: Vector2i) -> bool:
	var tile_data = tile_map.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	if not tile_data.get_custom_data("walkable"):
		return false
	# NPC parado (ver npc.gd/world.gd::has_npc_at) bloqueia o passo igual uma
	# parede, mesmo sem ter física nenhuma — checado por último porque é o
	# caso raro (a maioria das células não tem NPC nenhum), então não vale a
	# pena pagar esse custo antes de já ter certeza que o tile em si é andável.
	if world.has_npc_at(cell):
		return false
	return true

# Liga/desliga o efeito de "afundar" na grama alta — quem decide QUANDO
# chamar isso é world.gd (só ele sabe o que é um tile de grama), Player só
# sabe cortar a metade de baixo do próprio sprite via shader (ver
# assets/shaders/sink_in_grass.gdshader, material em AnimatedSprite2D).
func set_sunk_in_grass(sunk: bool) -> void:
	if anim.material is ShaderMaterial:
		anim.material.set_shader_parameter("sunk", sunk)

# Reposiciona instantaneamente, sem tocar animação de passo — usado quando
# o personagem "aparece" numa célula sem ter andado até ela de verdade (ex:
# voltando de uma troca de cena, ver GameState/world.gd). Mesmo espírito de
# Unit.teleport_to() em battle.gd, usado ali pro Undo de movimento.
func teleport_to(cell: Vector2i, new_facing: String = facing) -> void:
	grid_pos = cell
	facing = new_facing
	position = tile_map.map_to_local(grid_pos)
	is_moving = false
	anim.play(_idle_anim_name())
