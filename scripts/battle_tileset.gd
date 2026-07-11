class_name BattleTileset
extends Resource

# Configuração de UM tileset de batalha completo — a ARTE de verdade
# (tile_set) MAIS o COMPORTAMENTO do "fluido" daquele mapa (os tiles do
# terço central do atlas: água na tinyWoods, lava na mtBlaze, buraco num
# futuro terceiro tileset). O MAPEAMENTO de coordenadas (paredes, chão,
# fluido) é o MESMO em todo tileset de batalha — confirmado pelo usuário,
# "isso vai se manter para todos eles" — por isso battle.gd usa sempre as
# MESMAS constantes de atlas (WALL_SET_A, FLUID_SET_A, FLUID_DETAIL,
# GROUND_ATLAS_*) não importa qual BattleTileset foi sorteado; só a imagem
# por trás (tile_set) e os dois campos abaixo mudam de um pra outro.
#
# battle.gd sorteia um destes aleatoriamente a cada batalha (ver
# BATTLE_TILESETS/current_battle_tileset) — por enquanto só "pra teste"
# (pedido explícito do usuário), então ainda não existe nenhum vínculo com a
# EncounterArea nem com o bioma do overworld.

# Só cosmético (aparece no log da batalha pra facilitar teste/depuração —
# ver battle.gd::_ready) — não afeta nenhuma regra.
@export var display_name: String = ""

# O TileSet de verdade (textura + registro de atlas) — ver battle_tileset_
# tinywoods.tres/battle_tileset_mtblaze.tres. Atribuído em runtime ao
# tile_set de CADA TileMapLayer da cena de batalha (ver battle.gd::_ready).
@export var tile_set: TileSet

# Tipo elemental (mesmo vocabulário de UnitData.types) que atravessa o
# fluido livremente, além de quem já atravessa por outros motivos (grounded
# = false na própria UnitData, ou uma Habilidade com grants_levitation, ver
# battle.gd::can_cross_fluid) — "Water" pro tileset de água, "Fire" pro de
# lava. "" (padrão) = nenhum tipo específico atravessa livre — é o caso do
# futuro tileset de buraco, onde SÓ quem é non-grounded passa, nenhum tipo
# dá esse direito sozinho.
@export var fluid_pass_type: String = ""

# Status Condition (mesmo vocabulário de Unit.status_condition) aplicada a
# QUALQUER unidade que pise numa célula de fluido (ver battle.gd::
# _on_unit_tile_entered) — "" (padrão, água) = nenhum efeito. "Burned" pro
# tileset de lava: tentamos aplicar em todo mundo que entra, mas quem é do
# fluid_pass_type (Fire) já é naturalmente imune via Unit.
# STATUS_TYPE_IMMUNITIES, então na prática só quem atravessa por ser
# non-grounded (ou por Levitate) realmente se queima — sem precisar checar
# tipo nenhum aqui, apply_status_condition() já se recusa sozinha.
@export var fluid_status_on_enter: String = ""
