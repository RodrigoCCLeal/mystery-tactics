shader_type canvas_item;

// Corta (deixa transparente) a parte de baixo do sprite quando "sunk" está
// ligado — é assim que o personagem parece "afundar" na grama alta, sem
// precisar de nenhuma peça de arte extra pro efeito. sink_line é a fração
// da altura do QUADRO ATUAL (de cima=0.0 pra baixo=1.0) onde o corte
// acontece; 0.75 = só o 1/4 de baixo some. Ajustável no Inspector
// (AnimatedSprite2D -> Material -> Shader Parameters).
uniform bool sunk = false;
uniform float sink_line : hint_range(0.0, 1.0) = 0.75;

// IMPORTANTE: quando a textura é um AtlasTexture (é o caso aqui — cada
// quadro é um recorte de walk_sheet/run_sheet, que tem 4 colunas x 4
// linhas), o UV que o Godot manda pro shader é relativo ao ATLAS INTEIRO,
// não ao quadro visível. Ou seja, comparar UV.y direto com 0.5 cortava
// tudo ou nada dependendo da linha (direção) do atlas em que o quadro
// atual está — era exatamente o bug "some inteiro ou não some nada,
// depende da direção". region_rect (xy = origem, zw = tamanho, os dois em
// fração do atlas inteiro) é atualizado em player.gd toda vez que o quadro
// muda, e serve pra reconverter UV bruto em "UV local" (0 a 1 dentro só do
// quadro que está sendo desenhado agora).
uniform vec4 region_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (sunk && region_rect.w > 0.0) {
		float local_y = (UV.y - region_rect.y) / region_rect.w;
		if (local_y > sink_line) {
			tex_color.a = 0.0;
		}
	}
	COLOR = tex_color;
}
