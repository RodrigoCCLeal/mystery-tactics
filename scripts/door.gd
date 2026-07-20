class_name Door
extends Node2D

# Marca UMA célula do grid como porta/entrada de caverna — o jogador
# atravessa essa célula e a cena troca na hora, sem precisar apertar nada
# (igual entrar numa casa nos jogos Pokémon originais). Ver
# world.gd/house_interior.gd::_on_player_tile_entered, que chama
# get_door_at(cell), checado em player.gd::_try_start_move() ANTES do
# jogador entrar na célula (não depois, ver comentário lá).
#
# Por que isso é um NODE (um por porta, posicionado à mão na cena) e não um
# dado pintado no TileSet — tipo marcar o tile da porta como "is_transition"
# no Custom Data, do mesmo jeito que "walkable" já funciona hoje?
#
# Porque Custom Data no TileSet é por TIPO DE TILE, compartilhado por TODA
# pintura daquele tile no jogo inteiro — se você pintar o mesmo tile de
# porta em três casas diferentes do mapa, as três teriam OBRIGATORIAMENTE o
# mesmo destino, porque a informação mora no tile, não na célula onde ele
# foi pintado. Cada porta de verdade precisa saber PRA ONDE ela leva (que
# cena, que posição de chegada) — isso é informação POR INSTÂNCIA, não por
# tipo de tile. Um node por porta resolve isso (mesmo espírito de
# nurse.tscn/baldo.tscn: um Npc por NPC, não um "tipo de tile de NPC" — ver
# comentário de npc.gd).
#
# O tile da porta em si pode continuar sendo só arte estática pintada na
# camada de Objetos/Chão (walkable=true) — door_sheet abaixo é OPCIONAL: se
# não for atribuído, este node continua 100% invisível, só carregando o
# destino, exatamente como antes. Se for atribuído, ele monta uma pequena
# animação de "abrir" (ver _build_open_animation) que toca por cima do tile
# no instante em que o jogador entra na célula, ANTES do fade-to-black.

# Caminho da cena de destino (ex: "res://scenes/overworld/red_house_interior.tscn")
# — Ctrl clique no campo no Inspector pra escolher o arquivo em vez de digitar.
@export_file("*.tscn") var target_scene_path: String = ""

# Onde o jogador aparece NA CENA DE DESTINO, em coordenada de grid (não
# pixel) — geralmente a célula bem em frente à porta de lá (pra ele "sair"
# andando pra fora, não nascer em cima da porta de novo).
@export var target_grid_pos: Vector2i = Vector2i.ZERO
@export_enum("down", "left", "right", "up") var target_facing: String = "down"

@export_group("Animação de abrir (opcional)")
# Spritesheet tipo RPG Maker (ex: doors5.png): cada COLUNA é uma cor/estilo
# de porta diferente, cada LINHA é um quadro da animação de abrir (fechada
# -> abrindo -> aberta). null (padrão) = sem animação, porta fica muda.
@export var door_sheet: Texture2D
# Qual coluna (estilo/cor) usar DENTRO do sheet acima — index 0 = primeira.
@export var sheet_column: int = 0
# Quantos quadros de animação (linhas) o sheet tem.
@export var frame_count: int = 4
# Tamanho de UM quadro em pixels — NÃO calculado dividindo o tamanho total
# do arquivo pelas colunas/linhas (isso quebra se o sheet tiver qualquer
# espaço/borda entre os quadros, que foi exatamente o problema visto: o
# recorte "vazava" pro quadro vizinho). 32x32 é o tamanho real confirmado
# pelo usuário pra doors5.png — mesmo tamanho de tile do resto do overworld.
@export var frame_size: Vector2i = Vector2i(32, 32)
# Espaço EXTRA entre um quadro e o próximo, em pixels (0 = quadros
# perfeitamente colados). Se depois de setar frame_size ainda aparecer um
# pedaço do quadro vizinho, aumente isso aos poucos (1, depois 2...) até a
# borda sumir — o print em _build_open_animation mostra os valores usados.
@export var frame_separation: Vector2i = Vector2i.ZERO
@export var open_anim_fps: float = 8.0
# Pausa extra DEPOIS que a animação termina (porta já totalmente aberta),
# antes do fade-to-black começar — sem isso, a tela escurecia imediatamente
# no último quadro, quase junto com a animação terminando, e dava a
# impressão de que a porta nem tinha aberto de verdade. Dá tempo do jogador
# REGISTRAR a porta aberta antes de tudo escurecer.
@export var hold_open_duration: float = 0.5

# Door mora DENTRO de "Actors" (Node2D com y_sort_enabled=true), igual
# Player/Npc, pra desenhar na ordem certa por posição Y (senão a arte da
# porta sempre aparece por CIMA do jogador, não importa se ele está na
# frente ou atrás dela).
#
# MAS não assumimos "../.." (profundidade fixa) pra achar o script de
# overworld (Test/World/HouseInterior) — já quebrou uma vez ("Nonexistent
# function 'get_ground_tile_map' in base 'Window'": Door não estava
# aninhado na profundidade esperada, "../.." subiu passando do topo da cena
# e foi parar no Window de verdade do sistema operacional). Em vez disso,
# _find_ground_tile_map() sobe a árvore nó por nó perguntando "você tem
# get_ground_tile_map()?" até achar quem tiver — funciona não importa se
# Door está direto embaixo da raiz, dentro de Actors, ou mais aninhado
# ainda no futuro.
@onready var tile_map: TileMapLayer = _find_ground_tile_map()

# Sobe a árvore a partir do PAI de Door até achar um node com o método
# get_ground_tile_map() (Test/World/HouseInterior implementam isso — ver
# comentário deles) e já devolve o TileMapLayer em si. null (com um erro
# claro no Output, não um crash) se não achar nenhum ancestral assim —
# melhor um aviso legível do que "Nonexistent function em Window" de novo.
func _find_ground_tile_map() -> TileMapLayer:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("get_ground_tile_map"):
			return node.get_ground_tile_map()
		node = node.get_parent()
	push_error("Door '%s': nenhum ancestral com get_ground_tile_map() encontrado — Door precisa estar dentro da árvore de Test/World/HouseInterior." % name)
	return null

var grid_pos: Vector2i = Vector2i.ZERO
var anim: AnimatedSprite2D = null

# Ajuste fino pedido pelo usuário: cada quadro do sheet tem uma coluna de
# pixel EXTRA sobrando (ver o "- 1" no recorte do AtlasTexture em
# _build_open_animation) — cortar essa coluna encolhe o quadro em 1px de
# largura, o que sozinho já puxa o desenho pra direita/baixo
# (AnimatedSprite2D centra na LARGURA/ALTURA atual do quadro, então um
# quadro mais estreito recentra sozinho). DOOR_ANIM_OFFSET some o resto do
# ajuste — x começou em -1 (esquerda), depois voltou +1 (direita: "Move 1
# pixel to the right"), os dois se cancelam e ficou 0; y continua -1 (1px
# pra cima) — no mesmo sistema de coordenadas 2D de sempre (direita = +x,
# baixo = +y). Aplicado como anim.offset em _build_open_animation() logo
# abaixo (AnimatedSprite2D é centered por padrão, então offset desloca o
# desenho sem mexer em position/grid_pos).
const DOOR_ANIM_OFFSET := Vector2(0, -1)

func _ready() -> void:
	add_to_group("door")
	# Mesmo bug (e mesma correção) do gêmeo em npc.gd::_ready() — usar
	# `position` direto (relativo ao pai, normalmente "Actors") só é seguro
	# se esse pai estiver exatamente em (0,0). global_position/to_local/
	# to_global evitam depender disso (ver comentário grande em npc.gd pro
	# caso real que expôs o bug: Actors com offset em oak_lab_interior.tscn).
	grid_pos = tile_map.local_to_map(tile_map.to_local(global_position))
	global_position = tile_map.to_global(tile_map.map_to_local(grid_pos))
	# TODO(debug): remove depois de confirmar a animação — só pra ver no
	# painel Output se door_sheet chegou aqui de verdade e com que tamanho.
	print("[Door %s] _ready: door_sheet=%s grid_pos=%s" % [name, door_sheet, grid_pos])
	if door_sheet != null:
		_build_open_animation()
		print("[Door %s] animação construída, anim=%s frames=%s" % [name, anim, anim.sprite_frames.get_frame_count("open") if anim else "n/a"])

# Monta o AnimatedSprite2D em código (em vez de exigir montar a árvore na
# mão pra CADA porta no editor) — mesma técnica de player.gd::build_sprite_
# frames/npc.gd::_build_sprite_frames: fatia o sheet cru em quadros via
# AtlasTexture, usando column_count/frame_count pra calcular o tamanho de
# cada quadro (não precisa saber a resolução exata do arquivo de antemão).
# Fica invisible=true até play_open_animation() ser chamado — sem isso,
# ficaria mostrando o quadro 0 (porta fechada) o tempo todo, duplicando a
# arte que já está pintada na TileMapLayer embaixo.
func _build_open_animation() -> void:
	anim = AnimatedSprite2D.new()
	add_child(anim)
	anim.visible = false
	anim.offset = DOOR_ANIM_OFFSET

	var frames = SpriteFrames.new()
	frames.add_animation("open")
	frames.set_animation_loop("open", false)
	frames.set_animation_speed("open", open_anim_fps)

	# "step" = distância de um quadro até o próximo (tamanho do quadro +
	# espaço extra entre eles) — se frame_separation for ZERO, step ==
	# frame_size, ou seja, quadros colados (comportamento antigo). origin_x
	# é sempre a MESMA coluna (sheet_column), só a linha (quadro da
	# animação) muda por iteração.
	var step_x = frame_size.x + frame_separation.x
	var step_y = frame_size.y + frame_separation.y
	var origin_x = sheet_column * step_x
	# TODO(debug): remove depois — confirma os números realmente usados no
	# recorte. Se origin_x ficar maior que door_sheet.get_width(), a coluna
	# pedida nem existe no arquivo.
	print("[Door %s] sheet=%dx%d frame_size=%s separation=%s origin_x=%d" % [name, door_sheet.get_width(), door_sheet.get_height(), frame_size, frame_separation, origin_x])

	for row in frame_count:
		var atlas = AtlasTexture.new()
		atlas.atlas = door_sheet
		atlas.region = Rect2(origin_x, row * step_y, frame_size.x, frame_size.y)
		frames.add_frame("open", atlas)

	anim.sprite_frames = frames

# Chamado por world.gd/house_interior.gd::use_door() ANTES de
# salvar a posição/trocar de cena — toca a animação inteira (fechada até
# aberta) e só devolve o controle quando ela termina, pra dar tempo da
# porta "abrir de verdade" antes do fade-to-black cobrir a tela. Sem
# door_sheet configurado, não faz nada (retorna na hora) — porta muda,
# igual sempre foi.
func play_open_animation() -> void:
	print("[Door %s] play_open_animation chamado, anim=%s" % [name, anim])
	if anim == null:
		return
	anim.visible = true
	anim.play("open")
	print("[Door %s] tocando, is_playing=%s" % [name, anim.is_playing()])
	await anim.animation_finished
	print("[Door %s] animação terminou, segurando %.2fs" % [name, hold_open_duration])
	if hold_open_duration > 0.0:
		await get_tree().create_timer(hold_open_duration).timeout
