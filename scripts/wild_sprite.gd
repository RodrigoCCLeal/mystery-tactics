class_name WildSprite
extends Node2D

# Sprite selvagem VISÍVEL no overworld — pedido do usuário (refactor de
# encontro selvagem, 2026-09-10, verbatim): "grass areas will spawn
# overworld sprites for units able to spawn in that region, and will
# initiate combat when touched by the player". Instanciado em bloco por
# world.gd::_refresh_grass_patch() (ver lá pra regra de ONDE/QUAL espécie, de
# novo a CADA refresh — troca de área ou GRASS_GROUP_REFRESH_INTERVAL
# segundos, não só uma vez), nunca colocado à mão no editor — por isso não usa o mesmo truque de
# "calcular grid_pos a partir da posição arrastada" que npc.gd usa; quem
# spawna já sabe a célula exata e chama setup() com ela.
#
# Diferente de Npc (ver npc.gd) — NÃO entra no grupo "npc": um NPC de
# verdade BLOQUEIA o passo (ver Player._try_start_move/world.has_npc_at) e
# só reage a "confirm" de frente pra ele; um WildSprite faz o oposto, o
# jogador anda LIVREMENTE por cima da mesma célula, e é o PRÓPRIO passo que
# dispara a batalha (ver world.gd::_on_player_tile_entered ->
# get_wild_sprite_at), igual grama alta/água hoje — "touched" = pisou em
# cima, sem precisar de confirm nenhum. Fica no grupo "wild_sprite" própria
# (ver world.gd::get_wild_sprite_at/_get_wild_sprites_in_patch), pra não
# contaminar nenhuma lógica existente que já varre o grupo "npc" (Trainer,
# _get_npc_at, etc.).

@export var species: UnitData
@export var level: int = 1

var grid_pos: Vector2i = Vector2i.ZERO

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

# Chamado por world.gd LOGO após instantiate(), ANTES de add_child() (ou
# depois, tanto faz — _apply_visual() roda dos dois jeitos: aqui embaixo se
# já estiver na árvore, ou de novo em _ready() se ainda não estiver, mesmo
# espírito defensivo de outros setup() do projeto, ex: pc_slot.gd).
func setup(new_species: UnitData, new_level: int, cell: Vector2i, tile_map: TileMapLayer) -> void:
	species = new_species
	level = new_level
	grid_pos = cell
	global_position = tile_map.to_global(tile_map.map_to_local(cell))
	if is_inside_tree():
		_apply_visual()

func _ready() -> void:
	add_to_group("wild_sprite")
	_apply_visual()

# Reaproveita UnitData.portrait_anim_name() (ver comentário grande lá) —
# MESMA regra de fallback idle/hover que o retrato do menu de time já usa,
# aqui aplicada ao sprite do overworld em vez do retrato parado. fainted
# sempre false aqui (nenhum wild sprite nasce desmaiado).
func _apply_visual() -> void:
	if species == null or anim == null:
		return
	anim.sprite_frames = species.sprite_frames
	var anim_name = species.portrait_anim_name()
	if anim_name != "" and anim.sprite_frames != null and anim.sprite_frames.has_animation(anim_name):
		anim.play(anim_name)
