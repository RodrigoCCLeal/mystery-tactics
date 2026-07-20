extends "res://scripts/npc.gd"
class_name Bed

# Cama interagível — pedido do usuário: "create a new 2d interactable node
# 'Bed'. It has no sprite and heals your team after a yes/no prompt just
# like the nurse. Except the text is 'Would you like to rest?'". Mesmo
# efeito de nurse.gd (GameState.heal_active_roster()), só que com um
# segundo efeito extra: descansar também avança o relógio pro PRÓXIMO
# período do dia (ver GameState.advance_to_next_time_of_day) — pedido do
# usuário: "When resting on a bed, the time of day advances the the next
# one Morning -> Day -> Night".
#
# "Sem sprite" — mesmo espírito de open_pc.gd: o móvel físico (a cama de
# verdade) já é pintado como decoração normal na TileMapLayerObjects/Ground
# do cômodo; este node é só o GATILHO invisível de interação em cima
# daquela célula. Herda de npc.gd pelo mesmo motivo de sempre (grid_pos +
# grupo "npc", ver comentário grande em npc.gd/open_pc.gd).

const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/ui/popups/yes_no_prompt.tscn")

# Quanto tempo a tela fica TOTALMENTE preta (depois do fade-in, antes do
# fade-out) — dá um instante de "cochilo" antes de reaparecer, em vez de
# escurecer e clarear direto em sequência (que passaria rápido demais pra
# registrar como "o jogador dormiu"). Mesmo espírito de door.gd::
# hold_open_duration.
const SLEEP_HOLD_DURATION := 0.5
const FADE_DURATION := 0.3

func _ready() -> void:
	super._ready()
	anim.visible = false   # sem sprite nenhum, ver comentário grande acima

# Sobrescreve npc.gd::_build_sprite_frames() — mesmo motivo de open_pc.gd:
# não existe `sheet` nenhum pra fatiar (Bed não é um personagem), só
# precisamos que idle_<direção> EXISTA (npc.gd::_ready()/face_towards()
# chamam anim.play() sem checar se a animação existe) — nunca é mostrado de
# verdade (anim.visible fica false pra sempre, ver _ready() acima), então um
# quadro-placeholder 1x1 (nenhum arquivo de imagem, PlaceholderTexture2D
# basta) já resolve.
func _build_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	var blank := PlaceholderTexture2D.new()
	blank.size = Vector2(1, 1)
	for dir in SHEET_DIRECTIONS:
		var anim_name = "idle_" + dir
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.add_frame(anim_name, blank)
	return frames

# X de frente pra Bed (mesmo caminho de qualquer Npc — ver world.gd::
# _try_interact, que já vira ela pro jogador ANTES de chamar isto).
func interact() -> void:
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("Would you like to rest?")
	prompt.answered.connect(_on_answered)
	get_tree().paused = true

# Pedido do usuário: "Bed prompt works, but is missing a fade to black" —
# escurece a tela (SceneTransition.fade_to(), MESMO ColorRect usado por
# door.gd::use_door(), ver scene_transition.gd), aplica cura + avanço de
# horário com a tela JÁ preta (o jogador nunca vê a troca acontecer, igual
# uma "elipse" de cochilo), segura um instante, e clareia de novo — tudo
# com a árvore ainda pausada (ver interact() acima), por isso
# scene_transition.gd precisou ganhar PROCESS_MODE_ALWAYS.
func _on_answered(yes: bool) -> void:
	if not yes:
		get_tree().paused = false
		return
	await SceneTransition.fade_to(1.0, FADE_DURATION)
	GameState.heal_active_roster()
	GameState.advance_to_next_time_of_day()
	await get_tree().create_timer(SLEEP_HOLD_DURATION).timeout
	await SceneTransition.fade_to(0.0, FADE_DURATION)
	get_tree().paused = false
