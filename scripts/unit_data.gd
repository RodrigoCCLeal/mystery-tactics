class_name UnitData
extends Resource

# preloads (não class_name global) só por consistência com o resto do
# projeto — usados só por ensure_initialized() abaixo, pra calcular HP máximo
# (UnitScript.calc_hp_static) e a xp "legítima" de um nível (ExpGroups).
const UnitScript = preload("res://scripts/unit.gd")
const ExpGroups = preload("res://scripts/exp_groups.gd")

# Dados de UM tipo de personagem (identificado pela numeração de 4 dígitos,
# ex: 0001): aparência + stats BASE. Os stats aqui NÃO são o que a unidade
# usa em combate direto — são a matéria-prima da fórmula de nível, calculada
# em unit.gd (Unit.recalculate_stats()).
#
# Cada personagem vira um arquivo .tres separado (res://data/units/*.tres).
# O nó Unit (cena) fica genérico e recebe esses dados via apply_persisted_data()
# (time do jogador) ou apply_fresh_data() (inimigos-teste, ver comentário
# desses métodos em unit.gd).
# No futuro, uma tela de seleção de equipe só precisa listar UnitData
# e deixar o jogador escolher quais entram na batalha.

@export var unit_name: String = ""
@export var sprite_frames: SpriteFrames
@export var portrait: Texture2D   # retrato pro HUD de combate — ainda não usado em lugar nenhum

# Tempo (em segundos) entre o INÍCIO da animação attack_<dir>/shoot_<dir>/
# charge_<dir> do atacante e o instante em que o golpe realmente "conecta"
# (o HitFrame do AnimData.xml original do sprite sheet). battle.gd usa isso
# pra atrasar a reação (hurt_<dir> + desconto de HP) do defensor até esse
# instante, em vez de tocar tudo no mesmo frame em que o ataque começa.
# Cada espécie tem uma animação diferente (frames/durações diferentes), então
# esse valor precisa ser calibrado por espécie — não dá pra usar um só global.
@export var attack_hit_delay: float = 0.3
@export var special_hit_delay: float = 0.3

# Tipo elemental (Grass, Fire, Water, Ice, Ground, etc). Pode ter 1 ou 2 tipos.
# Não é usado em cálculo nenhum ainda — guardado aqui pra quando formos
# calcular dano/efetividade de ataques.
@export var types: Array[String] = []

# Se false, a unidade "flutua"/voa e ignora restrições de terreno (ex: pode
# atravessar água mesmo sem ser do tipo Water). Por padrão toda unidade é
# grounded — hoje nenhuma tem essa flag negativa, é só a base pra isso.
@export var grounded: bool = true

# Os 6 slots de ação (ataque/habilidade/item) que essa unidade carrega pra
# batalha — o "loadout" atual dela. Pode ter menos de 6 preenchidos (o resto
# fica null = slot vazio). Trocável fora de batalha num menu futuro; dentro
# de uma batalha em andamento, fica travado (Unit só lê isso uma vez, em
# apply_persisted_data()/apply_fresh_data()).
@export var slots: Array[ActionData] = []

# Quantas unidades de um item STACKABLE (ver ItemData.stackable — hoje só
# Ball e TM) estão no slot de MESMO índice em `slots`. Índice i aqui
# corresponde exatamente ao índice i de `slots` — mantidos em paralelo (mesmo
# esquema de Unit.slot_uses, só que este é PERSISTIDO entre batalhas, porque
# representa quantas unidades FÍSICAS do item ainda restam, não um contador
# que "recarrega" a cada combate. Só tem valor relevante quando slots[i] é
# um ItemData stackable — pra qualquer outro tipo de slot (ataque,
# habilidade, item comum) fica 0/sem uso. Nunca acessar este array direto —
# usar get_slot_quantity()/set_slot_quantity() abaixo, que crescem o array
# sozinhos até o índice pedido (slots também pode ter menos de 6 entradas,
# então este array também pode).
@export var slot_quantities: Array[int] = []

func get_slot_quantity(index: int) -> int:
	if index < 0 or index >= slot_quantities.size():
		return 0
	return slot_quantities[index]

func set_slot_quantity(index: int, amount: int) -> void:
	while slot_quantities.size() <= index:
		slot_quantities.append(0)
	slot_quantities[index] = amount

# TODAS as ações que essa espécie pode aprender, cada uma com o nível mínimo
# (LearnsetEntry) — não é o loadout equipado, é o "catálogo" de onde slots
# deveria ser escolhido (num menu futuro de equipar ataques/habilidades).
@export var learnset: Array[LearnsetEntry] = []

# Ações do learnset já disponíveis num dado nível (level <= o informado) —
# EXCETO Habilidade Hidden ainda não revelada (ver hidden_ability_revealed
# logo abaixo): por padrão ela não aparece como opção pra equipar, só depois
# de usar um Ability Patch nesta unidade. Usado pelo futuro menu de
# equipar — hoje slots ainda é preenchido à mão.
func get_available_actions(level: int) -> Array[ActionData]:
	var available: Array[ActionData] = []
	for entry in learnset:
		if entry.level > level:
			continue
		if entry.is_hidden_ability and not hidden_ability_revealed:
			continue
		available.append(entry.action)
	return available

# true se `action` for uma Habilidade marcada Hidden NESTA espécie (ver
# LearnsetEntry.is_hidden_ability) — procura o LearnsetEntry cuja action
# seja exatamente essa (mesma instância compartilhada, ver comentário de
# ALL_SPECIES em game_state.gd) e devolve a flag dele. false tanto pra
# "não encontrada no learnset" quanto pra "encontrada, mas não é Hidden" —
# o chamador não precisa distinguir os dois casos. Independente de
# hidden_ability_revealed — continua reportando a Habilidade como Hidden
# (pro tooltip/tag "(Hidden)") mesmo depois de revelada; só
# get_available_actions() acima muda de comportamento com a revelação.
func is_ability_hidden(action: ActionData) -> bool:
	for entry in learnset:
		if entry.action == action:
			return entry.is_hidden_ability
	return false

# true se esta unidade tem alguma Habilidade Hidden no learnset E ela ainda
# não foi revelada (ver hidden_ability_revealed) — é o que um Ability Patch
# (ver ItemData.reveals_hidden_ability/GameState.use_item) precisa checar
# antes de deixar o jogador "gastar" o item numa unidade sem Habilidade
# Hidden nenhuma pra revelar, ou que já revelou a dela.
func has_unrevealed_hidden_ability() -> bool:
	if hidden_ability_revealed:
		return false
	for entry in learnset:
		if entry.is_hidden_ability:
			return true
	return false

# Loadout AUTOMÁTICO de inimigo: as até `max_slots` ações mais RECENTES que
# essa espécie já teria aprendido até `level` — uma fila FIFO de tamanho
# max_slots (quem aprendeu por último entra, quem é mais antigo sai quando
# não tem mais espaço). Diferente do time do jogador (que usa `slots` tal
# como foi montado/editado no menu de Loadout), inimigo nunca teve um loadout
# escolhido à mão — ver Unit.apply_fresh_data(), único lugar que chama isso.
#
# Ordena por nível de aprendizado; em caso de empate (duas ações no mesmo
# nível), mantém a ordem de declaração no learnset — sort_custom() do
# GDScript não garante estabilidade, então o índice original entra como
# critério de desempate explícito.
func get_recent_loadout(level: int, max_slots: int = 6) -> Array[ActionData]:
	var indexed: Array = []
	for i in learnset.size():
		indexed.append({"entry": learnset[i], "order": i})
	indexed.sort_custom(func(a, b):
		if a["entry"].level != b["entry"].level:
			return a["entry"].level < b["entry"].level
		return a["order"] < b["order"]
	)

	var loadout: Array[ActionData] = []
	for item in indexed:
		var entry: LearnsetEntry = item["entry"]
		if entry.level > level:
			continue
		loadout.append(entry.action)
		if loadout.size() > max_slots:
			loadout.remove_at(0)   # descarta a mais antiga — fila cheia
	return loadout

@export_group("Stats base")
@export var weight: int = 1             # 0 a 4 — inerente à unidade, não muda com o nível
@export var hp_base: int = 45
@export var attack_base: int = 45
@export var defense_base: int = 45
@export var special_attack_base: int = 45
@export var special_defense_base: int = 45
@export var speed_base: int = 45

# Nível de IA usado pela unidade em batalha (ver battle.gd::plan_enemy_action
# e as 4 táticas reais: _plan_easy_action/_plan_medium_action/
# _plan_hard_action/_plan_rocket_action — "Champion" ainda não tem tática
# própria, cai pra Medium por enquanto, pedido explícito do usuário: "Skip
# for now"). "Easy" é o padrão porque é o comportamento de QUALQUER unidade
# selvagem a menos que a própria espécie diga o contrário (pedido do
# usuário: "Wild Pokémon will still operate on Easy IQ unless stated
# otherwise") — times de Trainer normalmente SOBRESCREVEM isso na hora de
# spawnar (ver Trainer.iq/GameState.current_trainer_iq), então este campo
# só importa de verdade pra batalhas selvagens ou pra um Trainer que não
# tenha `iq` configurado.
@export_enum("Easy", "Medium", "Hard", "Rocket", "Champion") var iq: String = "Easy"

# Quão fácil é capturar essa espécie com uma Ball — entra direto na fórmula
# de captura (ver battle.gd::resolve_capture): quanto MAIOR, mais fácil.
# Escala 0.0 a 1.0 (em vez da escala 0-255 dos jogos originais) só pra já
# vir pronto pra multiplicar direto na fórmula sem precisar normalizar toda
# vez — os valores usados nas espécies já implementadas são os catch rates
# REAIS desses jogos, só divididos por 255 (ex: 45/255 ≈ 0.176).
@export_range(0.0, 1.0) var catch_rate: float = 0.2

@export_group("Experiência")
# Grupo de crescimento — define quanta exp acumulada é necessária pra cada
# nível (ver ExpGroups.total_exp_for_level). Os 6 grupos são os mesmos dos
# jogos Pokémon, de onde essa curva foi tirada.
@export_enum("Erratic", "Fast", "Medium Fast", "Medium Slow", "Slow", "Fluctuating")
var growth_group: String = "Medium Slow"

# Exp BASE concedida quando essa espécie é derrotada — entra na fórmula
# b*L*a/7 (ver ExpGroups.calc_exp_gain) junto com o nível de quem foi
# derrotado e o multiplicador de quem recebe.
@export var base_exp_yield: int = 64

@export_group("Evolução")
# Lista de possíveis evoluções — vazio (padrão) = não evolui. Cada
# EvolutionOption (ver evolution_option.gd) carrega sua PRÓPRIA espécie-alvo
# e pré-requisitos (nível mínimo, ação equipada); normalmente só tem UMA
# entrada (evolução linear, ex: Swinub -> Piloswine), mas pode ter VÁRIAS —
# nesse caso, se mais de uma ficar disponível ao mesmo tempo,
# party_screen.gd::_try_evolve() abre uma tela de escolha em vez de evoluir
# direto (pedido do usuário: "a unit might be able to evolve into different
# options. when able to evolve, show a selection screen with the evolution
# options"). Ver party_screen.gd::_get_available_evolutions() pra como os
# pré-requisitos de cada opção são checados.
@export var evolution_options: Array[EvolutionOption] = []

@export_group("Progresso (persistido entre batalhas)")
# Diferente de tudo acima (que é fixo, "da espécie"), estes três mudam com o
# jogo — nível, xp acumulada TOTAL (não "desde o último nível", ver
# Unit.gain_exp) e o HP com que essa unidade vai entrar na PRÓXIMA batalha.
# É por isso que GameState.roster guarda uma instância PRÓPRIA de UnitData
# por slot (.duplicate(), não o Resource compartilhado direto do disco) —
# senão duas unidades da mesma espécie no time dividiriam nível/HP.
#
# current_hp = -1 é sentinela de "ainda não inicializada" (só antes do
# primeiro ensure_initialized(), chamado uma vez por slot em
# GameState._ready()).
@export var level: int = 1
@export var xp: int = 0
@export var current_hp: int = -1

# Nome da área (EncounterArea.area_name, ver GameState.current_area) onde
# esta unidade foi capturada — "" (padrão) pras 3 unidades iniciais do
# jogador (nunca foram "capturadas", só começaram no time) e pra qualquer
# unidade antiga de antes desse campo existir. Carimbado UMA vez, na hora da
# captura (ver battle.gd::resolve_capture), nunca mudado depois — é
# histórico, não estado atual. Mostrado em "Summary" (ver unit_summary.gd).
@export var caught_location: String = ""

# false (padrão) = se esta unidade tem uma Habilidade Hidden no learnset
# (ver LearnsetEntry.is_hidden_ability), ela fica de fora de
# get_available_actions() — não aparece como opção pra equipar no Loadout.
# Vira true pra sempre depois que o jogador usa um Ability Patch nesta
# unidade específica (ver ItemData.reveals_hidden_ability/GameState.
# use_item) — a partir daí a Habilidade Hidden entra na lista normal de
# opções, junto com as outras. Progresso da UNIDADE, não da espécie (por
# isso mora aqui e não em LearnsetEntry) — duas unidades da mesma espécie
# podem ter revelado (ou não) independentemente uma da outra.
@export var hidden_ability_revealed: bool = false

# Preenche level/xp/current_hp na primeira vez que esta instância é usada.
# Sobe pro nível default já com a xp EXATA que esse nível exigiria de
# verdade (em vez de 0), pra não destoar da conta cumulativa de
# Unit.gain_exp() nas próximas batalhas. Idempotente: se já foi inicializada
# antes (current_hp >= 0), não faz nada — battle.gd e a Party não precisam
# se preocupar em chamar isso mais de uma vez.
func ensure_initialized(default_level: int) -> void:
	if current_hp >= 0:
		return
	level = default_level
	xp = ExpGroups.total_exp_for_level(level, growth_group)
	current_hp = UnitScript.calc_hp_static(hp_base, level, weight)

# Preenche level/xp/current_hp com o progresso REAL de uma unidade selvagem
# recém-capturada (ver battle.gd::resolve_capture) — mesmos três campos que
# ensure_initialized() preenche, mas com os valores de BATALHA (nível e HP
# com que ela estava lutando, não um nível "de primeira vez"). xp usa a
# mesma conta de ensure_initialized (xp EXATA que aquele nível exigiria),
# pra não destoar da curva acumulativa de Unit.gain_exp() caso essa unidade
# um dia entre no time ativo. Diferente de ensure_initialized, NÃO é
# idempotente — sempre sobrescreve, mesmo se current_hp já não for -1 (não
# faz sentido capturar a mesma instância duas vezes, mas não custa deixar
# isso explícito).
func apply_capture_progress(captured_level: int, captured_hp: int) -> void:
	level = captured_level
	xp = ExpGroups.total_exp_for_level(level, growth_group)
	current_hp = captured_hp

# Nome da animação "parada, virada pra baixo" certa pra mostrar num retrato
# fora de batalha (party_screen.gd/pc_slot.gd) — precisava do MESMO fallback
# que unit.gd::_idle_anim_name() já usa em batalha (ver lá pro comentário
# grande com as 3 regras), só fixado em "down" (retrato nunca vira de
# direção). Sem isso, espécie sem idle_<dir> nenhuma (ex: Beedrill/0015, só
# tem hover_down — voa "pairando" o tempo todo, nunca "parada no chão") ficava
# de fora do menu de time inteiro: os dois lugares checavam só
# has_animation("idle_down") e escondiam o retrato (e, por só desenhar a
# unidade quando o retrato existe... na prática ela sumia da lista).
# `fainted` (current_hp <= 0) tem prioridade sobre tudo: sleep_down se
# existir, senão cai pro mesmo idle/hover de sempre. "" só no caso teórico de
# uma espécie sem NENHUMA das três (não deveria acontecer com nada já
# implementado).
func portrait_anim_name(fainted: bool = false) -> String:
	if sprite_frames == null:
		return ""
	if fainted and sprite_frames.has_animation("sleep_down"):
		return "sleep_down"
	var has_idle = sprite_frames.has_animation("idle_down")
	var has_hover = sprite_frames.has_animation("hover_down")
	if not has_hover:
		return "idle_down" if has_idle else ""
	if grounded and has_idle:
		return "idle_down"
	return "hover_down"
