class_name MapEntryPoint
extends Resource

# Onde o jogador aparece quando ENTRA num lugar andável (vilarejo, ponto
# especial, rota) vindo de um vizinho pelo Town Map. Ex: entrar na Route 1
# vindo de Wushu deve colocar o jogador na borda de cima da rota; vindo de
# Kano, na borda de baixo — por isso é um ponto POR VIZINHO, não um só.
#
# Mesmo espírito de Door.target_grid_pos/target_facing (ver door.gd): uma
# posição em coordenada de GRID (não pixel) da cena de destino.

# id do MapLocation de onde o jogador está vindo (ex: "wushu"). "" = ponto
# padrão, usado quando nenhum outro bate (ver MapLocation.get_entry_from).
@export var from_location_id: String = ""
@export var grid_pos: Vector2i = Vector2i.ZERO
@export_enum("down", "left", "right", "up") var facing: String = "down"
