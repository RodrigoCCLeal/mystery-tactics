class_name ExpGroups
extends RefCounted

# Utilitário estático (nunca instanciado — só funções/consts) com as curvas
# de experiência dos 6 grupos de crescimento (mesmos dos jogos Pokémon, de
# onde essas fórmulas foram tiradas). Nenhum estado aqui, só matemática.

const MAX_LEVEL = 100

# EXP TOTAL acumulada necessária pra estar em `level` (não é "exp que falta
# pro próximo nível" — é o total desde o zero). Nível 1 sempre exige 0 exp
# por definição (convenção padrão desses jogos: o restante das fórmulas só
# vale a partir do nível 2). Todas as divisões truncam (floor), igual ao
# resto do projeto — como os numeradores aqui são sempre não-negativos,
# divisão inteira do GDScript já dá o mesmo resultado que floor().
static func total_exp_for_level(level: int, group: String) -> int:
	if level <= 1:
		return 0
	var n = level
	match group:
		"Fast":
			return (4 * n * n * n) / 5
		"Medium Fast":
			return n * n * n
		"Medallium Slow":
			return (6 * n * n * n) / 5 - 15 * n * n + 100 * n - 140
		"Slow":
			return (5 * n * n * n) / 4
		"Erratic":
			return _erratic(n)
		"Fluctuating":
			return _fluctuating(n)
		_:
			push_warning("ExpGroups: grupo de crescimento desconhecido '%s', usando Medium Fast" % group)
			return n * n * n

static func _erratic(n: int) -> int:
	if n <= 49:
		return (n * n * n * (100 - n)) / 50
	elif n <= 67:
		return (n * n * n * (150 - n)) / 100
	elif n <= 97:
		var inner = (1911 - 10 * n) / 3   # divisão inteira = floor, igual à fórmula original
		return (n * n * n * inner) / 500
	else:
		return (n * n * n * (160 - n)) / 100

static func _fluctuating(n: int) -> int:
	if n <= 14:
		var inner = (n + 1) / 3   # divisão inteira = floor
		return (n * n * n * (inner + 24)) / 50
	elif n <= 35:
		return (n * n * n * (n + 14)) / 50
	else:
		var inner2 = n / 2   # divisão inteira = floor
		return (n * n * n * (inner2 + 32)) / 50

# Quanto falta de exp acumulada pra chegar no PRÓXIMO nível, a partir do xp
# atual — só informativo por enquanto (não é mostrado em lugar nenhum ainda,
# mas o HUD vai precisar disso no futuro).
static func exp_to_next_level(current_level: int, current_xp: int, group: String) -> int:
	if current_level >= MAX_LEVEL:
		return 0
	return total_exp_for_level(current_level + 1, group) - current_xp

# Fórmula de ganho de exp ao derrotar uma unidade:
#   b * L * a / 7
# b = exp base da unidade derrotada (UnitData.base_exp_yield)
# L = nível da unidade derrotada
# a = 1.5 se foi quem deu o golpe que derrotou, 1 se só está no time
# Trunca no final (mesma convenção do resto do projeto).
static func calc_exp_gain(base_exp: int, defeated_level: int, multiplier: float) -> int:
	return int(base_exp * defeated_level * multiplier / 7.0)

# Progresso (0.0 a 1.0) da xp acumulada DENTRO do nível atual — quanto falta
# pro próximo, normalizado. Usado pela barra de XP azul da tela de Party
# (ver party_screen.gd). Nível máximo sempre devolve 1.0 (barra cheia, não
# tem "próximo nível" pra medir contra).
static func level_progress_ratio(current_level: int, current_xp: int, group: String) -> float:
	if current_level >= MAX_LEVEL:
		return 1.0
	var floor_xp = total_exp_for_level(current_level, group)
	var ceil_xp = total_exp_for_level(current_level + 1, group)
	var span = ceil_xp - floor_xp
	if span <= 0:
		return 1.0
	return clamp(float(current_xp - floor_xp) / float(span), 0.0, 1.0)
