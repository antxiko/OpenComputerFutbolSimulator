class_name ConditionRecovery extends RefCounted

# Recuperación parcial de condition entre partidos basada en el calendario real.
#
# Antes: cada partido reseteaba condition a 100, lo que ignoraba el cansancio
# acumulado en partidos cercanos. Ahora la recuperación depende de los días
# de descanso desde el último partido del jugador:
#
#   Días desde último partido  →  Condition de partida
#   0 (mismo día, raro)        →  45  (lesionable)
#   1                          →  55
#   2                          →  70
#   3                          →  82
#   4                          →  92
#   ≥5                         →  100 (fresco)
#
# Esto premia rotaciones cuando hay partidos seguidos (Liga + Champions).
#
# Uso: antes de cada partido, llamar `apply_to_team(team, match_date)` en
# vez de hacer `for p: p.condition = 100.0`. Después del partido, llamar
# `record_match_played(player, match_date)`.


# Aplica la condition apropiada a TODOS los players del equipo según los días
# que han pasado desde su último partido individual.
static func apply_to_team(team: Team, match_date: Dictionary) -> void:
	if team == null:
		return
	for p: Player in team.players:
		apply_to_player(p, match_date)


static func apply_to_player(p: Player, match_date: Dictionary) -> void:
	# Si no tenemos fecha del partido o el player nunca jugó, asumir fresco.
	if match_date == null or match_date.is_empty():
		p.condition = 100.0
		return
	if p.last_match_date == null or p.last_match_date.is_empty():
		p.condition = 100.0
		return
	var days: int = DateUtil.diff_days(p.last_match_date, match_date)
	if days >= 5:
		p.condition = 100.0
	elif days == 4:
		p.condition = 92.0
	elif days == 3:
		p.condition = 82.0
	elif days == 2:
		p.condition = 70.0
	elif days == 1:
		p.condition = 55.0
	else:
		p.condition = 45.0


# Marca a los titulares de un lineup como "han jugado este partido en la fecha X".
# Llamado tras MatchEngine.simulate.
static func record_match_played(lineup: Lineup, match_date: Dictionary) -> void:
	if lineup == null or match_date == null or match_date.is_empty():
		return
	for p: Player in lineup.starting_eleven:
		p.last_match_date = match_date.duplicate()
