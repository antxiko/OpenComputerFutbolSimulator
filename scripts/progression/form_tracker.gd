class_name FormTracker extends RefCounted

# Actualiza la "forma" del jugador (player.form: 0.70-1.30) tras cada partido.
# La forma es un multiplicador sobre el rendimiento — afecta a la probabilidad
# de ser elegido como shooter/asistente, riesgo de lesión, y morale recovery.
#
# Tras un partido jugado → form sube/baja según rating
# Tras un partido sin jugar → regresión lenta hacia 1.0 (pierde gas o se recupera)

const FORM_MIN: float = 0.70
const FORM_MAX: float = 1.30
const FORM_TARGET: float = 1.0


# Calcula rating del partido (-3.0 a +5.0) según stats del jugador.
static func compute_rating(goals: int, assists: int, yellows: int, reds: int, won: bool, lost: bool) -> float:
	var r: float = 0.0
	r += float(goals) * 2.0
	r += float(assists) * 1.0
	r -= float(yellows) * 0.5
	r -= float(reds) * 2.0
	if won:
		r += 0.5
	elif lost:
		r -= 0.5
	return clampf(r, -3.0, 5.0)


# Multiplicador de delta de form según personality del jugador.
# Líderes y temperamentales son más volátiles; flojos más estancados.
static func _personality_volatility(personality: String) -> float:
	match personality:
		"lider": return 1.20         # responde rápido a buenos partidos
		"temperamental": return 1.40  # muy volátil — buena/mala racha rápida
		"flojo": return 0.60          # cuesta salir de mala racha
		_: return 1.00                 # equilibrado o vacío


# Aplicar a player tras participar en partido. rating típico -3..+5.
static func update_after_match(player: Player, rating: float) -> void:
	# +5 (gran partido) → +0.20 form base. Personality multiplica delta.
	var delta: float = rating * 0.04 * _personality_volatility(player.personality)
	player.form = clampf(player.form + delta, FORM_MIN, FORM_MAX)


# Regresión a 1.0 para jugadores que no jugaron. Más lento que partido.
static func update_no_play(player: Player) -> void:
	var step: float = 0.02 * _personality_volatility(player.personality)
	if player.form > FORM_TARGET + step:
		player.form = maxf(FORM_TARGET, player.form - step)
	elif player.form < FORM_TARGET - step:
		player.form = minf(FORM_TARGET, player.form + step)


# Devuelve un icono compacto + color para mostrar en UI.
static func icon_for(player_form: float) -> Dictionary:
	if player_form >= 1.20:
		return { "icon": "↑↑", "color": Color(0.4, 1.0, 0.5) }
	elif player_form >= 1.10:
		return { "icon": "↑", "color": Color(0.6, 0.95, 0.6) }
	elif player_form >= 0.92:
		return { "icon": "=", "color": Color(0.85, 0.85, 0.85) }
	elif player_form >= 0.82:
		return { "icon": "↓", "color": Color(0.95, 0.7, 0.5) }
	else:
		return { "icon": "↓↓", "color": Color(1.0, 0.5, 0.5) }
