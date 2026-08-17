extends "res://scripts/npc.gd"

# Mom (assets/sprites/Human/NPC/NPC 28.png, ver red_house_interior.tscn) —
# pedido do usuário (2026-08-04): "Stops the player from leaving the house
# the first time they try to, and give them 3000$, then update the
# mom_leave_house flag, so it doesnt happen again. After that she works
# like a nurse."
#
# Duas partes bem separadas:
# 1) A "trava de saída" em si mora INTEIRAMENTE em Door (ver
#    required_flag/blocked_message/use_blocked em door.gd) — a porta de
#    saída da casa (ver red_house_interior.tscn::Door) é configurada com
#    required_flag = GIFT_FLAG abaixo e o próprio blocked_message dela (o
#    aviso mostrado ANTES do presente, ver house_interior.gd::
#    _handle_blocked_door). Mom só precisa saber QUAL Door é essa
#    (guarded_door abaixo, arrastado no Inspector) pra escutar o sinal
#    use_blocked dela.
# 2) Ao ouvir use_blocked (ver _on_guarded_door_blocked), dá o dinheiro e
#    marca a MESMA flag que o required_flag da porta pede — a porta nunca
#    mais bloqueia depois disso (Door.is_blocked() já lê a flag sozinha,
#    nenhum código extra aqui precisa "destravar" nada na porta).
#
# interact() continua EXATAMENTE como um Nurse normal (mesmo texto que já
# existia aqui antes deste pedido) — "After that she works like a nurse" já
# era o comportamento de sempre desta cena, não precisa de nada novo.

const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")
const MESSAGE_BOX_SCENE: PackedScene = preload("res://scenes/ui/popups/trainer_message_box.tscn")

const GIFT_AMOUNT = 3000
# Precisa bater exatamente com Door.required_flag da porta de saída (ver
# red_house_interior.tscn::Door) — é essa igualdade que faz a porta parar
# de bloquear sozinha assim que esta flag vira true aqui embaixo.
const GIFT_FLAG = "mom_leave_house"

# Caminho (relativo a este node) até a Door de saída da casa — NodePath em
# vez de `@export var guarded_door: Door` de propósito, mesma convenção já
# usada no resto do projeto pra referências cruzadas dentro da cena (ver
# npc.gd::world/tile_map, ambos resolvidos via get_node() em vez de export
# de Node tipado). NodePath() vazio (padrão) = Mom nunca reage a porta
# nenhuma, só funciona como Nurse (mesmo comportamento de antes deste campo
# existir).
@export var guarded_door_path: NodePath = NodePath()

func _ready() -> void:
	super._ready()
	if guarded_door_path != NodePath():
		var door := get_node(guarded_door_path) as Door
		if door != null:
			door.use_blocked.connect(_on_guarded_door_blocked)

func interact() -> void:
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("Rest a bit darling")
	prompt.answered.connect(_on_answered)
	get_tree().paused = true

func _on_answered(yes: bool) -> void:
	if yes:
		GameState.heal_active_roster()
	get_tree().paused = false

# guarded_door já mostrou o próprio blocked_message (ver door.gd/
# house_interior.gd::_handle_blocked_door) ANTES de emitir isto — aqui só
# entra a parte "de verdade" do presente: dinheiro + a flag que destrava a
# porta pra sempre (ver GIFT_FLAG acima). Segunda caixa de texto separada
# (em vez de só mexer em GameState.money em silêncio) pra deixar claro pro
# jogador de onde o dinheiro veio.
func _on_guarded_door_blocked() -> void:
	GameState.add_money(GIFT_AMOUNT)
	GameState.set_flag(GIFT_FLAG)
	get_tree().paused = true
	var box = MESSAGE_BOX_SCENE.instantiate()
	add_child(box)
	box.setup("Mom gave you $%d for the road!" % GIFT_AMOUNT)
	box.closed.connect(func(): get_tree().paused = false)
