shader_type canvas_item;

// Filtro do Town Map (ver town_map_screen.gd).
//
// Em vez de desenhar um retângulo cinza por cima de cada lugar não
// visitado, o script monta uma textura MINÚSCULA (cell_mask) com UM pixel
// por célula da grade do mapa (30x25). Cada pixel diz o que fazer com
// aquela célula:
//   canal R = 1 -> célula de um lugar ainda não visitado: fica cinza;
//   canal G = 1 -> célula do lugar embaixo do mouse: fica mais clara.
// Aqui no shader, cada pixel da imagem do mapa descobre em qual célula
// está e consulta a máscara. Assim um único shader cuida do mapa inteiro.

uniform sampler2D cell_mask : filter_nearest;
uniform vec2 tex_size;        // tamanho da imagem do mapa, em pixels
uniform vec2 grid_origin;     // onde a célula (0,0) começa na imagem
uniform float cell_size;      // tamanho de uma célula, em pixels
uniform vec2 grid_size;       // colunas, linhas
uniform float grey_strength = 0.85;  // 0 = sem cinza, 1 = cinza total
uniform float grey_darken = 0.8;     // escurece um pouco o cinza
uniform float hover_boost = 0.15;    // quanto o hover clareia

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec2 cell = floor((UV * tex_size - grid_origin) / cell_size);
	if (cell.x >= 0.0 && cell.y >= 0.0 && cell.x < grid_size.x && cell.y < grid_size.y) {
		vec4 m = texelFetch(cell_mask, ivec2(cell), 0);
		float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		vec3 grey = vec3(lum) * grey_darken;
		col.rgb = mix(col.rgb, mix(col.rgb, grey, grey_strength), m.r);
		col.rgb += vec3(m.g * hover_boost);
	}
	COLOR = col;
}
