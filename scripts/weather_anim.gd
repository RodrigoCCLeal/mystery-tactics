extends Sprite2D
class_name WeatherAnim

# Animação de ENTRADA de um clima (ex: assets/sprites/weather/sun,
# assets/sprites/weather/rain) — toca UMA VEZ (não em loop) e avisa quando
# termina (sinal `finished`), mesmo espírito de scripts/impact_effect.gd
# (ver comentário grande lá), e instanciado dentro da CanvasLayer HUD em vez
# de solto em Battle (ver battle.gd::play_weather_anim) — assim `position`
# já é direto em pixel de TELA (mesmo espaço dos offsets de Control usados
# no resto do HUD, ver comentário de weather_label em battle.gd), sem
# precisar converter mundo->tela feito ImpactEffect/Projectile fazem pros
# efeitos de ataque (esses SIM precisam acompanhar a câmera; isto aqui não,
# é um efeito de HUD). "Tocar de novo" (ex: Chuva repetindo em posições
# NOVAS, ver battle.gd::play_weather_anim) é feito instanciando uma cópia
# NOVA a cada rodada, não dando loop nesta mesma instância — mantém este
# script simples (uma instância = um play do início ao fim, sempre).
#
# DOIS formatos de quadro possíveis, escolhidos por qual função é chamada:
# - play() — "vários arquivos separados" (ex: sun/000.png..024.png), cada
#   Texture2D já É um quadro inteiro, sem AtlasTexture nenhum. Ver Sol.
# - play_strip() — UMA tira horizontal de quadros QUADRADOS (largura=altura
#   de cada quadro, ex: rain/Rain.None.png = 80x16 = 5 quadros de 16x16),
#   fatiada em runtime via AtlasTexture — mesma técnica de ImpactEffect/
#   Projectile. Ver Chuva.
signal finished

const FRAME_DURATION = 0.05  # mesmo valor de ImpactEffect.FRAME_DURATION

var frame_index: int = 0
var frame_count: int = 1
var frame_timer: float = 0.0

# Modo "vários arquivos" (ver play()) — vazio quando quem tocou foi
# play_strip() em vez disso (ver _is_strip abaixo).
var frames: Array[Texture2D] = []

# Modo "tira única" (ver play_strip()) — _atlas_texture é o AtlasTexture
# fatiado, _strip_frame_size é o tamanho (largura=altura) de CADA quadro.
var _is_strip: bool = false
var _strip_frame_size: int = 1
var _atlas_texture: AtlasTexture

# centered = false nos dois modos: `position` vira o CANTO superior
# esquerdo do quadro (não o centro, padrão de Sprite2D) — bate direto com
# os offsets em pixel de tela calculados por battle.gd::play_weather_anim
# (mesmo canto de WeatherMask pro Sol; posições aleatórias dentro do campo
# de batalha pra Chuva).
func play(new_frames: Array[Texture2D]) -> void:
	_is_strip = false
	frames = new_frames
	frame_count = frames.size()
	frame_index = 0
	frame_timer = 0.0
	centered = false
	visible = not frames.is_empty()
	if frames.is_empty():
		finished.emit()
		queue_free()
		return
	texture = frames[0]

# start_delay (segundos, padrão 0.0) segura o COMEÇO da animação — o nó já
# existe (e já assumiu `position`) mas fica invisível e parado no quadro 0
# até o delay passar. Usado por battle.gd::play_weather_anim pra
# "dessincronizar" várias cópias de Chuva tocando ao mesmo tempo em
# posições diferentes (pedido do usuário: "start each instance of the
# animation with a delay of 0 to 0.2 seconds") — cada cópia recebe um delay
# ALEATÓRIO diferente, então nenhuma duas começam (nem terminam) no exato
# mesmo instante, mesmo que todas toquem o ciclo inteiro.
func play_strip(strip_texture: Texture2D, start_delay: float = 0.0) -> void:
	_is_strip = true
	frames = []
	frame_timer = 0.0
	frame_index = 0
	centered = false
	_strip_frame_size = int(strip_texture.get_height())
	frame_count = max(1, int(strip_texture.get_width()) / _strip_frame_size)
	_atlas_texture = AtlasTexture.new()
	_atlas_texture.atlas = strip_texture
	_atlas_texture.region = Rect2(0, 0, _strip_frame_size, _strip_frame_size)
	texture = _atlas_texture
	visible = false
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	visible = true

func _process(delta: float) -> void:
	# `visible == false` cobre tanto "ainda não chamaram play()/play_strip()
	# nenhum" quanto "play_strip() chamou, mas ainda está no delay de
	# start_delay" (ver comentário lá) — nos dois casos, não avança quadro
	# nenhum ainda.
	if not visible:
		return
	if not _is_strip and frames.is_empty():
		return
	frame_timer += delta
	if frame_timer < FRAME_DURATION:
		return
	frame_timer -= FRAME_DURATION
	frame_index += 1
	if frame_index >= frame_count:
		finished.emit()
		queue_free()
		return
	if _is_strip:
		_atlas_texture.region = Rect2(frame_index * _strip_frame_size, 0, _strip_frame_size, _strip_frame_size)
	else:
		texture = frames[frame_index]
