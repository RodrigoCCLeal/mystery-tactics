# Guia: como adicionar conteúdo em Mystery Tactics

Este guia explica, passo a passo, como adicionar os 5 tipos de conteúdo mais comuns no jogo: **Ataques**, **Unidades** (espécies), **NPCs**, **Habilidades** e **Itens**. Para cada um, mostro exatamente quais arquivos abrir, quais campos preencher, e onde "registrar" a coisa nova pra ela aparecer de verdade no jogo.

A ideia central do projeto: quase todo "dado" (ataque, unidade, habilidade, item) é um arquivo `.tres` — um Resource do Godot, criado a partir de uma classe `.gd` que define os campos (`@export var ...`). Você não escreve dado nenhum direto em GDScript; você cria um `.tres` novo e preenche os campos no formato texto (ou no Inspector do editor, se preferir montar visualmente). Os `.gd` abaixo são as "fôrmas"; os `.tres` são o "conteúdo".

---

## 1. Como adicionar um Ataque

### 1.1 Onde tudo mora

- **Fôrma (campos disponíveis):** `scripts/attack_data.gd` (herda de `scripts/action_data.gd`, que dá `action_name`, `max_uses` e `range`)
- **Dado (o ataque em si):** um arquivo novo em `data/attacks/nome_do_ataque.tres`
- **Execução (o que acontece em batalha):** `scripts/battle.gd` — mas pra um ataque *comum* você não precisa mexer em código nenhum aqui, só nos dois pontos acima

### 1.2 Campos principais de `AttackData`

| Campo | O que é |
|---|---|
| `action_name` | Nome mostrado na UI (vem de `ActionData`) |
| `max_uses` | PP do ataque — todo ataque precisa de um valor > 0 aqui |
| `range` | Alcance (distância Chebyshev — diagonal conta 1 igual reto) |
| `is_special` | `false` = Físico, `true` = Especial |
| `is_status` | `true` = ataque de Status — não causa dano nenhum (ver seção 1.5) |
| `element_type` | Tipo elemental: `"Fire"`, `"Water"`, `"Normal"`, etc. |
| `power` | Poder base. `0` = sem dano direto |
| `accuracy` | 0.0 a 1.0 (hoje não afeta nada — nenhum ataque erra ainda) |
| `makes_contact` | Se encosta fisicamente no alvo |
| `is_projectile` | `false` = corpo a corpo (acerta só na distância EXATA de `range`). `true` = viaja em linha reta até `range` tiles, acerta o primeiro inimigo no caminho |
| `secondary_status` / `secondary_status_chance` | Status secundário (ex: `"Burned"`, 0.1 = 10%) e a chance dele acontecer |
| `secondary_status_2` / `secondary_status_chance_2` | Um SEGUNDO efeito secundário, independente do primeiro (ex: Ice Fang = Freeze + Flinch) |
| `tags` | Rótulos livres tipo `["Sound"]`, `["Wind"]` — hoje só documentação, nenhum código lê ainda |

### 1.3 Efeitos visuais (opcionais)

Três sistemas independentes, todos opcionais — um ataque pode ter zero, um, ou vários ao mesmo tempo:

- **`projectile_texture`** (ou `projectile_frames` se a arte vier em vários arquivos separados): só funciona com `is_projectile = true`. Uma tira horizontal de quadros quadrados, ou uma lista de texturas separadas.
- **`impact_texture`** / **`impact_texture_2`** (ou `impact_frames`): toca parado EM CIMA DO ALVO no instante do impacto. `_2` é uma segunda camada simultânea (ex: Ice Fang = mordida + cacos de gelo).
- **`cast_frames_by_direction`**: toca saindo de QUEM ATACA, viajando na direção mirada — pra efeitos tipo "onda sonora"/"rugido" que nascem no próprio usuário (ex: Growl). A imagem precisa ser uma grade **8 colunas (direção, sentido horário a partir de "down") × 6 linhas (quadros da animação)** — ver `scripts/cast_effect.gd` pro detalhe exato da ordem das colunas.

Se seu ataque não tem arte pronta ainda, é normal deixar esses campos vazios — o ataque funciona mecanicamente sem eles (só sem efeito visual).

### 1.4 Exemplo real: `data/attacks/growl.tres`

```
[gd_resource type="Resource" script_class="AttackData" format=3]

[ext_resource type="Script" uid="uid://ds0uxvdng0s2r" path="res://scripts/attack_data.gd" id="1"]
[ext_resource type="Texture2D" uid="uid://bh2y8ksgnqn6a" path="res://assets/sprites/Move/Growl.Dir8.png" id="2"]

[resource]
script = ExtResource("1")
element_type = "Normal"
power = 0
range = 3
is_status = true
area_shape = "Cone"
stat_change_stat = "attack"
stat_change_amount = -1
cast_frames_by_direction = ExtResource("2")
action_name = "Growl"
max_uses = 40
tags = Array[String](["Sound"])
```

O jeito mais fácil de descobrir o `uid://` de uma imagem: procure o arquivo `NomeDaImagem.png.import` na mesma pasta da imagem e leia o campo `uid=` lá dentro.

### 1.5 Ataques de Status (sem dano) e Área em Cone

Além de Físico/Especial, existe uma terceira categoria: **Status** (`is_status = true`). Um ataque de Status nunca causa dano — ele só aplica um efeito (hoje, mudança de stat; ver `AttackData.stat_change_stat`/`stat_change_amount`, que usa o vocabulário `"attack"`, `"defense"`, `"special_attack"`, `"special_defense"`, `"speed"` e um número, positivo ou negativo).

Um ataque de Status também pode ter `area_shape = "Cone"` (em vez de `"Single"`, o padrão) — nesse caso ele não mira 1 inimigo só, mira uma DIREÇÃO, e atinge todo inimigo dentro de um leque que se abre a partir de quem ataca (largura 1/3/5 a cada tile de distância). A geometria mora em `battle.gd::get_cone_cells()`.

**Se seu ataque só causa dano normal (não é Status), não precisa tocar em `is_status`/`stat_change_*`/`area_shape` — deixe tudo no padrão.**

### 1.6 Registrar o ataque numa espécie

Um ataque só é útil se alguma espécie souber usá-lo. Abra o `.tres` da espécie (`data/units/NNNN.tres`) e:

1. Adicione um `[ext_resource type="Resource" path="res://data/attacks/seu_ataque.tres" id="N"]` (N = próximo número livre)
2. Adicione um `[sub_resource type="Resource" id="LearnsetEntry_XXXX_nome"]` com `script = ExtResource("5")` (o id do `learnset_entry.gd`, normalmente já importado no arquivo), `action = ExtResource("N")`, e opcionalmente `level = X` (se omitido, o padrão é nível 1 — ver `scripts/learnset_entry.gd`)
3. Adicione esse `SubResource(...)` dentro do array `learnset = Array[...]([...])` no bloco `[resource]`

Isso só coloca o ataque no "catálogo" da espécie (`learnset`) — pra ele vir **já equipado** de fábrica, adicione o mesmo `ExtResource("N")` também dentro do array `slots = Array[...]([...])` (máximo 6 entradas).

---

## 2. Como adicionar uma Unidade (espécie)

### 2.1 Onde tudo mora

- **Fôrma:** `scripts/unit_data.gd`
- **Dado:** `data/units/NNNN.tres` (NNNN = o número da espécie, 4 dígitos com zero à esquerda, ex: `0202.tres`)
- **Sprites:** `assets/sprites/Pokemon/NNNN/` — as folhas de animação (Idle-Anim.png, Walk-Anim.png, Attack-Anim.png, Hurt-Anim.png, etc.) mais um `frames.tres` (o `SpriteFrames` do Godot, construído a partir delas — ver seção 2.4) e um `Normal.png` (retrato)
- **Registro obrigatório:** `scripts/game_state.gd`, dentro da constante `ALL_SPECIES`

### 2.2 Campos principais de `UnitData`

| Campo | O que é |
|---|---|
| `unit_name` | Nome mostrado na UI |
| `sprite_frames` | O `SpriteFrames` (ver seção 2.4) |
| `portrait` | Textura única pro retrato (HUD) |
| `attack_hit_delay` / `special_hit_delay` | Segundos entre o INÍCIO da animação de ataque e o instante em que o golpe "conecta" — calibrado por espécie, ver seção 2.4 |
| `types` | Array de 1 ou 2 strings: `["Fire"]`, `["Grass", "Poison"]` |
| `weight` | 0 a 4 — afeta HP máximo e alcance de movimento |
| `hp_base` / `attack_base` / `defense_base` / `special_attack_base` / `special_defense_base` / `speed_base` | Stats base (a "matéria-prima" da fórmula de nível) |
| `catch_rate` | 0.0 a 1.0 — quanto MAIOR, mais fácil de capturar (é o catch rate real do jogo original, dividido por 255) |
| `growth_group` | Um de: `Erratic`, `Fast`, `Medium Fast`, `Medium Slow`, `Slow`, `Fluctuating` — define a curva de XP |
| `base_exp_yield` | XP concedida ao derrotar essa espécie |
| `slots` | Array de até 6 `ActionData` (Ataques/Habilidades/Itens) — o loadout de FÁBRICA |
| `learnset` | Array de `LearnsetEntry` (nível + ação) — o catálogo completo do que essa espécie pode aprender |
| `evolution_options` | Array de `EvolutionOption` — ver seção 2.3 |

### 2.3 Evolução (`evolution_options`)

Cada entrada de `evolution_options` é um `EvolutionOption` (`scripts/evolution_option.gd`) com três campos:

| Campo | O que é |
|---|---|
| `target` | Espécie-alvo (o MESMO `Resource` compartilhado de `data/units/`, sem `.duplicate()` — quem duplica é `party_screen.gd::_perform_evolution()` na hora de aplicar) |
| `min_level` | Nível mínimo pra esta opção ficar disponível (0 = sem exigência) |
| `requires_action` | `ActionData` que precisa estar EQUIPADO (`UnitData.slots`, não só no `learnset`) pra esta opção ficar disponível (`null` = sem exigência) |

Normalmente `evolution_options` tem só UMA entrada (evolução linear — ex: Swinub -> Piloswine no nível 33). Mas pode ter VÁRIAS: se, na hora de abrir o menu "Evolve" (tela de Party), mais de uma opção estiver com os pré-requisitos satisfeitos ao mesmo tempo, o jogo abre uma tela de escolha (`evolution_choice_screen.tscn`) em vez de evoluir direto — é assim que uma espécie pode ramificar pra destinos diferentes dependendo de qual condição o jogador cumpriu primeiro.

Exemplo (Metapod evoluindo pra Butterfree no nível 10, uma opção só):

```
[ext_resource type="Script" path="res://scripts/evolution_option.gd" id="evo_opt_script"]
[ext_resource type="Resource" path="res://data/units/0012.tres" id="6"]

[sub_resource type="Resource" id="EvolutionOption_1"]
script = ExtResource("evo_opt_script")
target = ExtResource("6")
min_level = 10

[resource]
...
evolution_options = Array[ExtResource("evo_opt_script")]([SubResource("EvolutionOption_1")])
```

Pra uma espécie com DUAS opções, é só criar dois `EvolutionOption` (com `target`/pré-requisitos diferentes) e listar os dois dentro do mesmo array `evolution_options`.

**Armadilha nova:** evoluir muda o `weight` da unidade pra o da NOVA espécie — se isso fizer o time ativo passar de `GameState.MAX_TEAM_WEIGHT`, a evolução é RECUSADA (mensagem de erro na tela, nada muda) até o jogador abrir espaço de peso no time. Não precisa configurar nada pra isso acontecer — `party_screen.gd::_attempt_evolution()` já checa sozinho antes de qualquer evolução, usando o `weight` que a espécie-alvo já tem.

### 2.4 Construindo o `frames.tres` (a parte mais trabalhosa)

Se você já tem as folhas de sprite (formato PMD Sprite Collab: `Idle-Anim.png`, `Walk-Anim.png`, etc., cada uma com um `AnimData.xml` do lado), o `frames.tres` segue uma receita fixa — o padrão foi construído olhando `assets/sprites/Pokemon/0473/frames.tres` (Mamoswine) e vale pra qualquer espécie nova:

1. **Ordem das linhas** em cada PNG (de cima pra baixo, cada bloco tem `<FrameHeight>` pixels de altura): `Down(0), DownRight(1), Right(2), UpRight(3), Up(4), UpLeft(5), Left(6), DownLeft(7)`.
2. **Ordem das colunas** = índice do quadro, esquerda pra direita, na mesma ordem da lista `<Duration>` do `AnimData.xml`.
3. Cada direção vira uma animação separada dentro do `SpriteFrames`, nomeada `"<tipo>_<direção>"` (ex: `"walk_up_left"`), com a duração de cada quadro copiada DIRETO do `<Duration>` do XML (sem dividir por nada).
4. **`speed = 60.0` pra TODA animação, sempre** (só o `loop` muda por tipo):
   - `attack`, `hurt`, `shoot`, `charge`: `loop = false`
   - `idle`, `sleep`: `loop = true` (Sleep só registra a direção `"down"` — nenhuma espécie tem Sleep-Anim.png com as 8 direções)
   - `walk`: `loop = true`
   - **Por quê 60 e não um valor "artístico" por tipo:** o formato PMD Sprite Collab mede `<Duration>` em ticks de 1/60s (o motor original desses sprites roda a 60 FPS) — é por isso que um quadro de "hold" parado no Idle costuma ter `Duration` bem maior (30~40) que um quadro de transição (2~4): não é um erro de arte, é literalmente "segura esse quadro por 30 ticks". O campo `speed` do `SpriteFrames` do Godot é en FPS, e o tempo real de cada quadro = `duration / speed` — então `speed = 60.0` é o ÚNICO valor que devolve o tempo real gravado no XML (`duration/60` segundos). Um valor diferente (ex: 15.0 pro walk, 6.0 pro idle) SEMPRE distorce o tempo real por um fator fixo (nesse caso, 4x e 10x mais lento, respectivamente) — passa despercebido só quando os quadros têm duração pequena e uniforme (`1,1,1,1...`), mas fica bem visível (animação "arrastada") em qualquer espécie com `Duration` maior/desigual de verdade, como Idle de Rattata/Raticate (`40,2,2,2,4,2,2,2`) ou Wobbuffet (`40,4,4,4,4,4,4,4,4`).
5. **`attack_hit_delay`** = (soma dos `<Duration>` dos quadros de ataque, do quadro 0 até o `HitFrame` do XML, exclusive) / 60.0. `special_hit_delay` usa a mesma conta em cima de Shoot/Charge.

Se a arte vier como VÁRIOS ARQUIVOS SEPARADOS em vez de uma tira só (ex: golpes como Water Gun/Confusion), não use esse recibo — isso é o padrão diferente descrito na seção 1.3 (`projectile_frames`/`impact_frames`).

### 2.5 Exemplo real: `data/units/0202.tres` (Wobbuffet, sem ataques)

```
[gd_resource type="Resource" script_class="UnitData" format=3]

[ext_resource type="Script" uid="uid://dcmk5dnw33yee" path="res://scripts/unit_data.gd" id="1"]
[ext_resource type="SpriteFrames" path="res://assets/sprites/Pokemon/0202/frames.tres" id="2"]
[ext_resource type="Texture2D" uid="uid://dxk2a21pyswk0" path="res://assets/sprites/Pokemon/0202/Normal.png" id="3"]

[resource]
script = ExtResource("1")
unit_name = "Wobbuffet"
sprite_frames = ExtResource("2")
portrait = ExtResource("3")
attack_hit_delay = 0.35
special_hit_delay = 0.35
types = Array[String](["Psychic"])
weight = 3
hp_base = 190
attack_base = 33
defense_base = 58
special_attack_base = 33
special_defense_base = 58
speed_base = 33
catch_rate = 0.0588
growth_group = "Medium Fast"
base_exp_yield = 142
```

(Uma espécie pode não ter `slots`/`learnset` nenhum — nesse caso ela nunca ataca em batalha, só existe pra ser alvo/testado.)

### 2.6 Registrar a espécie

Abra `scripts/game_state.gd`, ache a constante `ALL_SPECIES` (é o catálogo de TODAS as espécies do jogo) e adicione uma linha:

```gdscript
const ALL_SPECIES: Array[UnitData] = [
	preload("res://data/units/0001.tres"),
	...
	preload("res://data/units/SEUNUMERO.tres"),   # <- nova linha
]
```

Sem isso, a espécie existe como arquivo mas o jogo não sabe que ela existe.

### 2.7 Colocando a espécie em jogo

Depois de registrada em `ALL_SPECIES`, você tem 3 jeitos de fazer ela aparecer de verdade:

- **Encontro selvagem:** edite um arquivo em `data/areas/*.tres` (ex: `starting_area.tres`) — é uma `EncounterArea` (`scripts/encounter_area.gd`), com uma lista de `EncounterGroup` (`scripts/encounter_group.gd`: uma lista de `EncounterEntry` + um peso relativo), e cada `EncounterEntry` (`scripts/encounter_entry.gd`) é só `species` + `level`. Pesos não precisam somar 100 — são normalizados na hora do sorteio.
- **Time inicial do jogador:** `GameState.roster` (topo de `game_state.gd`) — só pros primeiros 3 slots do jogo novo.
- **Reserva pra teste rápido:** ver `GameState._seed_testing_storage()`, que já bota uma cópia de CADA espécie de `ALL_SPECIES` na reserva do PC, nível 10, automaticamente — se sua espécie está em `ALL_SPECIES`, ela já aparece lá sem fazer mais nada.

---

## 3. Como adicionar um NPC

### 3.1 Onde tudo mora

- **Fôrma comum (aparência + posição):** `scripts/npc.gd` — você NÃO edita esse arquivo; ele é a base que todo NPC herda
- **Comportamento específico:** um `.gd` NOVO que estende `npc.gd`, sobrescrevendo só o método `interact()`
- **Cena:** um `.tscn` novo (pode duplicar `scenes/nurse.tscn` como ponto de partida)
- **Colocação no mundo:** `scenes/test.tscn`, dentro do nó `Actors`

### 3.2 Passo a passo

1. Crie `scripts/seu_npc.gd`:
   ```gdscript
   extends "res://scripts/npc.gd"

   func interact() -> void:
	   # o que acontece quando o jogador fala com esse NPC
	   print("Oi!")
   ```
2. Crie a cena (ou duplique `scenes/nurse.tscn`), com o script acima anexado à raiz (que deve ser um `Node2D` com um `AnimatedSprite2D` filho chamado exatamente `AnimatedSprite2D` — é o que `npc.gd` espera em `@onready var anim`).
3. No Inspector dessa cena, preencha `sheet` (a spritesheet, formato charset: 4 colunas de ciclo × 4 linhas de direção, ordem baixo/esquerda/direita/cima — mesmo layout de `assets/sprites/Human/NPC/*.png`) e `facing` (direção inicial).
4. Abra `scenes/test.tscn`, arraste uma instância da sua cena pra dentro do nó `Actors`, e posicione onde quiser (o `npc.gd` calcula a célula do grid sozinho a partir da posição em pixel — não precisa calcular grid_pos à mão).

**Isso é tudo.** Você não precisa mexer em colisão nem em `test.gd` — `npc.gd` já se registra sozinho no grupo `"npc"` em `_ready()`, e o resto do jogo (bloqueio de movimento, detecção de "tem alguém na minha frente") já sabe ler isso automaticamente.

### 3.3 Exemplo real: `scripts/nurse.gd`

```gdscript
extends "res://scripts/npc.gd"

const YES_NO_PROMPT_SCENE: PackedScene = preload("res://scenes/yes_no_prompt.tscn")

func interact() -> void:
	var prompt = YES_NO_PROMPT_SCENE.instantiate()
	add_child(prompt)
	prompt.setup("Would you like to heal your Pokémon?")
	prompt.answered.connect(_on_answered)
	get_tree().paused = true

func _on_answered(yes: bool) -> void:
	if yes:
		GameState.heal_active_roster()
	get_tree().paused = false
```

Pra um NPC mais simples que só mostra um texto (sem pergunta Sim/Não), dá pra reaproveisar esse mesmo padrão trocando `yes_no_prompt.tscn` por qualquer outra cena de popup — ou, pro caso mais simples possível, só um `print()`/`log_message()` de teste enquanto não existe uma caixa de diálogo genérica de "falar e fechar".

### 3.4 Caso especial: `LootBall` (objeto de recompensa que some)

Um `LootBall` é um `Npc` (herda de `npc.gd`, igual qualquer NPC da seção 3) especializado em UMA coisa: dar uma recompensa ao ser interagido e desaparecer da cena pra sempre. Pense nele como "um NPC cuja `interact()` já vem pronta" — você não escreve script nenhum novo, só configura uma instância de `scripts/loot_ball.gd` no Inspector.

- **Fôrma:** `scripts/loot_ball.gd` (você não edita esse arquivo, só configura instâncias)
- **Cena base:** `scenes/npc/loot_ball.tscn`
- **Visual:** vem de um tile do TileSet do overworld (`assets/tiles/tilesets/OW/outside.tres`, coordenada `(4, 118)` hoje — pra usar outro tile, edite `ATLAS_COORD`/`TILESET_TEXTURE` no topo do script), não de um charset de personagem — por isso não tem campo `sheet` pra preencher.

Campos do Inspector:

| Campo | O que é |
|---|---|
| `loot_id` | Identificador ÚNICO desta instância — obrigatório se você quer que ela fique sumida depois de sair e voltar pra cena (ver `GameState.collected_loot`). Sem `loot_id`, a bolinha reaparece toda vez que a cena recarrega. |
| `open_message` | Texto da primeira caixa, ao interagir (ex: "You found something!") |
| `reward_type` | `"Item"`, `"Unit"` ou `"Battle"` |
| `reward_item` / `reward_item_amount` | Só pra `reward_type = "Item"` — soma ao inventário (`GameState.add_item`) |
| `reward_unit` / `reward_unit_level` | Só pra `reward_type = "Unit"` — sempre com `.duplicate()` (mesmo motivo de sempre: sem isso, duas LootBalls da mesma espécie dividiriam nível/HP) |
| `add_to_active_team` | Só pra `reward_type = "Unit"`. `false` (padrão) = vai pra primeira vaga livre da RESERVA do PC, sempre cabe. `true` = vai DIRETO pro time ativo (`GameState.add_to_first_empty_roster_slot`) — se não couber (time cheio OU passaria do limite de peso, ver `GameState.MAX_TEAM_SIZE`/`MAX_TEAM_WEIGHT`), mostra um erro e a LootBall **não é consumida** — o jogador pode abrir espaço no PC e voltar. |
| (nenhum campo extra) | `reward_type = "Battle"` dispara um encontro selvagem normal, sorteado da `EncounterArea` ATUAL do jogador — mesma tabela que a grama alta usaria naquele ponto do mapa, não uma equipe fixa |

Passo a passo pra adicionar uma:

1. Abra a cena do overworld (`test.tscn`/`world.tscn`), arraste uma instância de `scenes/npc/loot_ball.tscn` pra dentro do nó `Actors`, posicione onde quiser.
2. Preencha `loot_id` (único!) e `reward_type` no Inspector, mais os campos da recompensa escolhida (ver tabela acima).

**Isso é tudo** — igual qualquer NPC (seção 3.2), você não precisa mexer em colisão nem em `test.gd`/`world.gd`: `npc.gd` já cuida do grupo `"npc"` (bloqueio de movimento + detecção de "tem algo na minha frente"), e `loot_ball.gd` já cuida de tocar a caixa de texto, dar a recompensa, marcar `GameState.collected_loot` e sumir (`queue_free()`).

**Armadilha:** se `reward_item`/`reward_unit` ficar vazio no Inspector (esqueceu de preencher), a LootBall avisa no Output e NÃO se marca como coletada — ela continua lá, interagível, esperando você corrigir a configuração e testar de novo.

---

## 4. Como adicionar uma Habilidade

### 4.1 Onde tudo mora

- **Fôrma:** `scripts/ability_data.gd`
- **Dado:** `data/abilities/nome_da_habilidade.tres`

### 4.2 Campos principais de `AbilityData`

Habilidade é sempre PASSIVA — nunca aparece como botão clicável, só fica equipada e o jogo checa ela automaticamente quando relevante.

| Campo | O que é |
|---|---|
| `element_type` | Tipo elemental que a Habilidade favorece (vazio = não boosta dano por tipo) |
| `hp_threshold` | Só tem efeito quando `hp_current/hp_max` for MENOR que isso (1.0 = sempre ativa) |
| `damage_multiplier` | Multiplica o dano de ataques do tipo `element_type`, quando `hp_threshold` é satisfeito |
| `immune_type` | Imunidade TOTAL (dano ×0) a esse tipo, quando equipada em quem DEFENDE (ex: Levitate = `"Ground"`) |
| `grants_levitation` | `true` = a unidade "flutua", ignora restrição de terreno mesmo com `UnitData.grounded = true` |
| `sheer_force` | `true` = todo ataque com efeito secundário perde o efeito, mas ganha +30% de dano |

### 4.3 Exemplo real: `data/abilities/sheer_force.tres`

```
[gd_resource type="Resource" script_class="AbilityData" format=3]

[ext_resource type="Script" path="res://scripts/ability_data.gd" id="1"]

[resource]
script = ExtResource("1")
action_name = "Sheer Force"
sheer_force = true
```

### 4.4 Equipando a Habilidade

Diferente de Ataque (que pode ficar só no `learnset`), Habilidade só faz efeito se estiver dentro do array `slots` da unidade (`data/units/NNNN.tres`) — adicione o `ExtResource` dela lá, igual um ataque. Pode (e normalmente deve) também entrar no `learnset`, só pra documentar que "essa espécie tem essa Habilidade" — mas quem faz efeito de verdade é `slots`.

---

## 5. Como adicionar um Item

### 5.1 Onde tudo mora

- **Fôrma:** `scripts/item_data.gd`
- **Dado:** `data/items/nome_do_item.tres`
- **Colocar no inventário do jogador (pra testar):** `scripts/game_state.gd`, função `_seed_starting_inventory()`

### 5.2 Campos principais de `ItemData`

| Campo | O que é |
|---|---|
| `category` | Um de: `"Medicine"`, `"Held Items"`, `"Berry"`, `"Tool"`, `"TM"`, `"Ball"` |
| `icon` | Textura mostrada na Bag |
| `effect_description` | Texto livre, mostrado na UI |
| `can_use` / `can_give` | Controla se "Use"/"Give" aparecem no menu de ações do item |
| `can_register` | Só itens Tool — controla se "Register"/"Unregister" (atalho rápido) aparece |
| `heal_amount` | HP restaurado ao usar (0 = não cura) |
| `accuracy_multiplier` | Multiplicador de precisão de quem carrega o item equipado |
| `stackable` | `true` = um slot guarda de 1 a 99 unidades (hoje só Ball e TM usam isso) |

Campos extras **só relevantes pra uma categoria específica** (ficam sem uso em qualquer outra categoria):

- **Ball:** `ball_bonus` (multiplicador de captura), `guaranteed_capture` (100% de captura, ex: Master Ball), `ball_closed_texture` + `ball_frame_count` (sprite sheet do voo), `ball_open_texture`
- **TM:** `tm_attack` — aponta pro `AttackData` de verdade que esse TM ensina (o TM não duplica os dados do ataque, só referencia)
- **Tool:** `toggles_bike` (hoje o único efeito de Tool que existe — um Tool novo precisaria de um campo próprio, do mesmo jeito)

### 5.3 Exemplo real: `data/items/tm10_ice_fang.tres`

```
[gd_resource type="Resource" script_class="ItemData" format=3]

[ext_resource type="Script" path="res://scripts/item_data.gd" id="1"]
[ext_resource type="Resource" path="res://data/attacks/ice_fang.tres" id="2"]

[resource]
script = ExtResource("1")
action_name = "TM10 Ice Fang"
category = "TM"
can_give = true
stackable = true
tm_attack = ExtResource("2")
```

### 5.4 Colocando o item em jogo

Hoje não existe loja nem drop de itens — o único jeito de um item aparecer na Bag do jogador é sendo adicionado explicitamente em `GameState._seed_starting_inventory()`:

```gdscript
func _seed_starting_inventory() -> void:
	add_item(preload("res://data/items/potion.tres"), 3)
	...
	add_item(preload("res://data/items/seu_item.tres"), 1)   # <- nova linha
```

`add_item(item, quantidade)` — chame de novo com o mesmo item pra aumentar a quantidade.

---

## 6. Armadilhas conhecidas (economize um tempo)

- **Nunca coloque comentários `#` entre dois blocos `[node ...]` dentro de um `.tscn`.** O parser do Godot para de instanciar tudo que vem depois do comentário, silenciosamente — sem erro nenhum no console, só os nós somem. Comentário só é seguro ANTES do primeiro `[node]` do arquivo.
- **Sempre que uma unidade precisa de progresso PRÓPRIO (nível, XP, HP atual)**, use `.duplicate()` no `preload()` — sem isso, várias unidades da mesma espécie compartilham a MESMA instância de `UnitData`, e subir de nível uma sobe todas.
- **`uid://` de qualquer asset** fica no arquivo `NomeDoAsset.png.import` (ou `.tres.import`), campo `uid=` — não precisa adivinhar nem gerar, é só ler.
- **Ao adicionar uma linha nova a um array `.tres`** (`learnset`, `slots`, `groups`, etc.), lembre de: (1) declarar o `[ext_resource]` ou `[sub_resource]` correspondente ANTES do bloco `[resource]`, com um `id` que não colida com nenhum outro já usado no mesmo arquivo, e (2) adicionar essa referência dentro do array certo.
