class_name ItemData
extends ActionData

# Item (Medicine/Held Items/Berry/Tool/TM/Ball). Estende ActionData (não
# Resource puro) porque Held Items e Berries de verdade OCUPAM um dos 6
# slots de ação de uma unidade (UnitData.slots é Array[ActionData]) —
# exatamente como o comentário em ActionData já previa ("Ability/Item
# viram novas subclasses depois, do mesmo jeito"). action_name (herdado)
# é o nome mostrado na Bag e no loadout; max_uses/range (herdados) ficam
# no padrão sem uso, igual Habilidade (ver comentário de AbilityData sobre
# o mesmo caso) — um item não gasta usos por contador, ele é removido do
# slot inteiro quando consumido (ver Unit._check_berry_auto_use).
#
# Diferente de UnitData, a QUANTIDADE que o jogador possui de um item não
# mora aqui — duas unidades carregando o mesmo Focus Band, ou dois slots
# da Bag mostrando a mesma Potion, sempre apontam pra ESTA MESMA instância
# de Resource (sem duplicate() nenhum). Quem sabe "quantos eu tenho" é
# GameState.inventory (Dictionary ItemData -> int).

const CATEGORIES = ["Medicine", "Held Items", "Berry", "Tool", "TM", "Ball"]

# Mostrado na Bag e no loadout; null vira um retângulo cinza de espaço
# reservado na Bag (ver item_list_screen.gd) até existir ícone de verdade.
@export var icon: Texture2D

@export_enum("Medicine", "Held Items", "Berry", "Tool", "TM", "Ball")
var category: String = "Medicine"

@export_multiline var effect_description: String = ""

@export_group("Ações disponíveis na Bag")
# Controla se as opções "Use"/"Give" aparecem quando o jogador seleciona
# este item na Bag (ver item_list_screen.gd -> item_action_menu.gd).
# Nenhum item precisa ter as duas: Potion/Super Potion só têm Use, Focus
# Band só tem Give, Oran Berry tem as duas.
@export var can_use: bool = false
@export var can_give: bool = false

# Só itens Tool (ver grupo "Tool" logo abaixo) têm isso — controla se
# "Register"/"Unregister" aparece no menu de ações (ver item_action_menu.gd).
# Registrado = o item ocupa um dos 4 atalhos de Tool (GameState.
# tool_shortcuts), usável rapidamente no overworld sem abrir a Bag (esse
# atalho de teclado em si ainda não está implementado — só o registro/
# desregistro por enquanto). Diferente de can_use/can_give, o próprio texto
# da opção muda sozinho entre "Register" e "Unregister" dependendo se o
# item já está num atalho ou não (ver GameState.is_item_registered).
@export var can_register: bool = false

@export_group("Efeito")
# HP restaurado ao usar (Use, ver GameState.use_item) ou ao auto-consumir
# em batalha (Berry, ver Unit._check_berry_auto_use). 0 = este item não
# cura.
@export var heal_amount: int = 0

# Multiplicador de precisão dos ataques de quem carrega este item
# equipado no loadout (ver Unit.get_accuracy_multiplier). 1.0 = sem
# efeito. Nenhum AttackData implementado ainda varia accuracy de verdade
# (ver AttackData.accuracy, campo novo só por causa disso) — então esse
# multiplicador ainda não muda nada visível em batalha, mas o cálculo já
# existe pronto pra quando um roll de acerto de verdade for implementado.
@export var accuracy_multiplier: float = 1.0

# Se true, um ÚNICO slot de loadout pode guardar de 1 a 99 unidades deste
# item ao mesmo tempo (ver UnitData.slot_quantities/get_slot_quantity) — a
# quantidade é escolhida no momento do "Give" (ver item_list_screen.gd ->
# quantity_picker.gd). Só Ball e TM são Stackable hoje: os dois se
# CONSOMEM sozinhos em batalha (um por uso — ver battle.gd::
# execute_ball_throw/execute_tm_attack), diferente de Held Items (Focus
# Band) ou Berry, que não fazem sentido "empilhados" (um único efeito
# passivo, não tem "usar de novo"). false (padrão) = item comum, sempre
# exatamente 1 por slot, como já funcionava antes desse campo existir.
@export var stackable: bool = false

@export_group("Ball (só itens com category == \"Ball\")")
# Diferente de Medicine/Held Items/Berry, um item Ball não é "Use" nem um
# efeito passivo — é "Give" (ver can_give acima) pra alguma unidade
# carregar, e em BATALHA ela pode arremessá-lo como um projétil que tenta
# capturar uma unidade selvagem inimiga (ver battle.gd::execute_ball_throw/
# resolve_capture). Os campos abaixo só têm efeito pra category == "Ball";
# em qualquer outra categoria, ficam nos defaults sem uso nenhum.

# Multiplicador da fórmula de captura (ver resolve_capture) — cada item
# Ball tem o seu (ex: uma ball melhor tem bônus maior). Ignorado por
# completo se guaranteed_capture for true.
@export var ball_bonus: float = 1.0

# Se true, IGNORA a fórmula de captura inteira e captura com 100% de
# chance sempre (ex: Master Ball). false = usa a fórmula normal.
@export var guaranteed_capture: bool = false

# Sprite sheet horizontal usada tanto durante o VOO da bola quanto (só o
# primeiro quadro) parada balançando enquanto a captura é calculada.
# Convenção de nome de arquivo: ball_NOMEITEM.png. Diferente de Projectile/
# ImpactEffect (que adivinham a quantidade de quadros assumindo que são
# QUADRADOS), aqui a quantidade vem explícita em ball_frame_count logo
# abaixo — os quadros de uma sprite sheet de Ball não são necessariamente
# quadrados, e adivinhar errado corta a região errada (mostra pedaço de mais
# de um quadro ao mesmo tempo).
@export var ball_closed_texture: Texture2D

# Quantidade EXATA de quadros em ball_closed_texture (ver comentário acima
# e Projectile.launch/CaptureBall._first_frame, que recebem isso pra cortar
# a sprite sheet certinho). 8 é o valor da Master Ball; ajuste por item se
# uma Ball futura vier com uma tira de tamanho diferente.
@export var ball_frame_count: int = 8

# Imagem ÚNICA (não é sprite sheet) da bola ABERTA — aparece atrás da
# unidade no instante em que a bola a atinge, e de novo se a captura
# falhar. Convenção de nome de arquivo: ball_NOMEITEM_open.png.
@export var ball_open_texture: Texture2D

@export_group("TM (só itens com category == \"TM\")")
# Um TM "ensina" um ataque já existente — em vez de duplicar power/tipo/
# alcance/etc, ele só REFERENCIA o AttackData de verdade (ex: TM 10 -> Ice
# Fang aponta pro mesmo data/attacks/ice_fang.tres que qualquer unidade que
# aprenda Ice Fang de verdade usaria). Em batalha, usar o slot do TM executa
# ESTE ataque (mesmo dano/efetividade/status, ver battle.gd::
# execute_tm_attack) e consome 1 carga do ITEM (UnitData.slot_quantities),
# NÃO um "uso" de tm_attack.max_uses — TM 10 não fica sem PP de Ice Fang,
# fica sem TM 10.
@export var tm_attack: AttackData

@export_group("Tool (só itens com category == \"Tool\")")
# Diferente de Medicine/Berry, um item Tool não tem alvo nenhum (nenhuma
# UNIDADE recebe o efeito) — o efeito é sobre o TREINADOR (ver
# GameState.use_tool, chamado por item_list_screen.gd quando category ==
# "Tool" em vez do fluxo normal de Use, que abriria um seletor de unidade
# sem sentido nenhum aqui). Tool também nunca é consumido ao usar (mesmo
# item pode ser usado infinitas vezes — ver GameState.use_tool não mexendo
# em inventory).
#
# Cada efeito de Tool novo ganha o próprio campo aqui, do mesmo jeito que
# Ball/TM fazem acima — hoje só existe a Bicycle (toggles_bike), mas um
# futuro Super Rod/Itemfinder/etc. seguiria o mesmo padrão.

# Se true, usar este item liga/desliga GameState.is_biking (ver
# Player._process, que sincroniza sprite/velocidade sozinho a partir disso
# a cada frame — troca pra bike_<direção>/idle_bike_<direção> e passa a
# andar em BIKE_DURATION). Só a Bicycle tem isso true hoje.
@export var toggles_bike: bool = false
