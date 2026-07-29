extends "res://scripts/npc.gd"
class_name OpenPc

# Terminal de PC interagível — pedido do usuário: "create a 'open pc' actor
# that is interactable. it has no sprite by default but it MAY have
# inside.tres (6,164) or (7,166) appear when it's being interacted with...
# remove the PC option from the A menu. When this actor is interacted with,
# activate 'PC' menu."
#
# Herda de npc.gd pelo MESMO motivo de LootBall (ver comentário grande lá):
# de graça, ganha grid_pos alinhado ao tile + grupo "npc" (é assim que
# world.gd/house_interior.gd::_try_interact() acham "tem algo
# interagível na minha frente" e bloqueiam o jogador de atravessar por
# cima), sem precisar duplicar esse sistema de detecção.
#
# "Sem sprite por padrão" — diferente de LootBall (que É o próprio desenho
# do prêmio), aqui o "computador" físico já é pintado como decoração normal
# na TileMapLayerObjects/Ground do cômodo (mesa, monitor desligado etc.) —
# este node é só o GATILHO invisível de interação em cima daquela célula.
# anim.visible fica false o tempo todo, exceto durante a própria interação,
# quando mostra o quadro de "tela ligando" configurado em screen_on_coord
# abaixo, recortado de Interior general.png (a mesma imagem-fonte de
# inside.tres) — mesma técnica de recorte por região que loot_ball.gd já usa
# pra ler um tile do TileSet direto da textura crua, em vez de duplicar a
# arte em outro arquivo.

# Rodrigo (2026-07-26): refatoração dos tilesets de interior — daqui pra
# frente, mapas NOVOS usam um tileset único "interiorFULL" (com todos os
# sprites de interior juntos numa imagem só), pra reduzir a dor de cabeça de
# NPCs/interagíveis precisarem saber QUAL tileset de interior cada cômodo
# usa. Mapas JÁ EXISTENTES continuam no tileset dedicado de antes (ex:
# "Interior general.png") — nenhum dos dois é "o certo", coexistem.
#
# Por isso TILESET_TEXTURE virou @export (era `const`, fixo pro projeto
# inteiro) — cada OpenPc agora escolhe, no Inspector, DE QUAL imagem-fonte
# recortar screen_on_coord abaixo. Padrão continua "Interior general.png",
# então todo OpenPc já colocado em cômodos antigos continua funcionando
# sem precisar reconfigurar nada; só os NOVOS, em cômodos que usam
# interiorFULL, precisam trocar isto no Inspector (e escolher a coordenada
# certa dentro da imagem nova, ver comentário de screen_on_coord abaixo).
@export var tileset_texture: Texture2D = preload("res://assets/tiles/tilesets/OW/sourceIMG/Interior general.png")
const ATLAS_TILE_SIZE := Vector2i(32, 32)

const COMPUTER_SCREEN_SCENE: PackedScene = preload("res://scenes/ui/screens/computer_screen.tscn")

# Coordenada do tile "tela ligada" DENTRO do atlas de tileset_texture acima
# (mesma ideia de LootBall.ATLAS_COORD/world.gd::grass_atlas_coords) —
# escolhível por INSTÂNCIA no Inspector ao arrastar open_pc.tscn pra uma
# cena, em vez de fixo no código: cada terminal pode usar um visual
# diferente sem precisar de uma variante de script. Pra descobrir a
# coordenada certa: abra a cena, selecione a TileMapLayer que usa a MESMA
# imagem apontada em tileset_texture (inside.tres nos cômodos antigos, o
# tileset "interiorFULL" nos novos), abra o painel de tiles embaixo e
# clique no quadro de tela ligada que você quer — o Godot mostra "(coluna,
# linha)" no rodapé/tooltip. IMPORTANTE desde a refatoração de tilesets de
# interior: esta coordenada só faz sentido pra imagem-fonte configurada
# ACIMA em tileset_texture — trocar uma sem revisar a outra recorta o
# pedaço errado da imagem. Padrão (6, 164) só porque foi o primeiro exemplo
# dado pelo usuário (pra Interior general.png); troque os dois juntos no
# Inspector de cada OpenPc novo.
@export var screen_on_coord: Vector2i = Vector2i(6, 164)

# Trava contra reabrir a tela duas vezes (ex: X segurado) — mesmo espírito
# de LootBall._opened, só que aqui não há "consumir" nenhum: o terminal
# pode ser usado quantas vezes o jogador quiser, então isto só evita abrir
# uma segunda cópia da tela por cima da primeira no mesmo frame.
var _busy: bool = false

func _ready() -> void:
	super._ready()
	anim.visible = false   # sem sprite nenhum em repouso, ver comentário grande acima

# Sobrescreve npc.gd::_build_sprite_frames() — mesmo motivo de LootBall: a
# arte não vem de um charset de personagem (sheet, 4 colunas x 4 linhas),
# vem de tiles soltos do TileSet do overworld. idle_* precisa EXISTIR (npc.gd
# ::_ready()/face_towards() chamam anim.play("idle_"+facing) sem checar se a
# animação existe de verdade) mas nunca é mostrado de fato — anim.visible
# fica false o tempo todo fora de uma interação (ver _ready() acima), então
# tanto faz qual quadro está "parado" por baixo.
func _build_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	var screen_atlas = _make_atlas(screen_on_coord)
	for dir in SHEET_DIRECTIONS:
		var anim_name = "idle_" + dir
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, 5.0)
		frames.add_frame(anim_name, screen_atlas)

	# Um quadro só (não pisca mais) — pedido do usuário: "i want only one,
	# but I want it to be selectable when I add the OpenPC to the scene".
	frames.add_animation("screen_on")
	frames.set_animation_loop("screen_on", true)
	frames.add_frame("screen_on", screen_atlas)
	return frames

func _make_atlas(coord: Vector2i) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	atlas.atlas = tileset_texture
	atlas.region = Rect2(coord.x * ATLAS_TILE_SIZE.x, coord.y * ATLAS_TILE_SIZE.y, ATLAS_TILE_SIZE.x, ATLAS_TILE_SIZE.y)
	return atlas

# Mesma caixa genérica de 1 linha de sempre (ver player.gd::MESSAGE_BOX_SCENE
# pro mesmo comentário) — usada só pro "esse terminal ainda não foi
# configurado" abaixo, quando nenhuma conta foi desbloqueada ainda (ver
# baldo.gd — fala com ele primeiro).
const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")

# X de frente pro terminal (mesmo caminho de qualquer Npc — ver world.gd/
# world.gd/house_interior.gd::_try_interact). Pedido do usuário: "activate
# 'PC' menu" — abre a MESMA computer_screen.tscn que existia atrás da opção
# "PC" do menu A antes dela ser removida (ver game_menu.gd), só que agora
# direto do overworld, sem passar pelo menu A nenhum.
func interact() -> void:
	if _busy:
		return
	# computer_screen.gd esconde "PC"/"Giovanni"/"Baldo"/"Heaven"
	# individualmente conforme os flags (ver _ready() lá) — mas se NENHUM
	# dos quatro estiver desbloqueado ainda, abrir aquela tela mostraria um
	# menu completamente vazio (sem nada pra selecionar). Barra a interação
	# inteira nesse caso específico, com uma mensagem em vez de um menu em
	# branco — pedido do usuário original das contas só existirem depois de
	# falar com Baldo (ver baldo.gd).
	if not GameState.get_flag("PC_ACCOUNT_REGISTERED") and not GameState.get_flag("GIOVANNI_PC_UNLOCKED") and not GameState.get_flag("BALDO_PC_UNLOCKED") and not GameState.get_flag("HEAVEN_PC_UNLOCKED"):
		_show_locked_message()
		return
	_busy = true
	anim.visible = true
	anim.play("screen_on")
	get_tree().paused = true   # mesmo padrão de world.gd::_open_game_menu — pausa o overworld enquanto a tela está aberta
	var screen = COMPUTER_SCREEN_SCENE.instantiate()
	add_child(screen)
	screen.closed.connect(_on_screen_closed)

func _show_locked_message() -> void:
	get_tree().paused = true
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup("This terminal isn't set up yet.")
	box.closed.connect(_on_locked_message_closed)

func _on_locked_message_closed() -> void:
	get_tree().paused = false

func _on_screen_closed() -> void:
	get_tree().paused = false
	anim.visible = false
	_busy = false
