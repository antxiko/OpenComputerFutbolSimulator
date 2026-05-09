class_name InjurySystem extends RefCounted

# Sistema de lesiones persistentes entre partidos.
#
# Estado en Player.injury:
#   {} (vacío) si está sano.
#   { tipo: "leve"|"media"|"grave", dias_restantes: int } si lesionado.
#
# Generación durante el partido: TickResolver.try_inflict_injury (probabilidad
# baja por tick).
# Curación: heal_after_days() llamado entre jornadas (típicamente 7 días).
#
# Severidades (calibración):
#   60% leve:  3-7 días   (~1 partido perdido)
#   30% media: 10-21 días (~2-4 partidos)
#   10% grave: 30-90 días (~1-3 meses)


# Cura todos los lesionados pasando `days` días.
# Devuelve la lista de jugadores recuperados en este paso.
static func heal_after_days(all_teams: Array, days: int) -> Array:
	var recovered: Array = []
	for team: Team in all_teams:
		for p: Player in team.players:
			if p.injury == null or p.injury.is_empty():
				continue
			var rem: int = int(p.injury.get("dias_restantes", 0)) - days
			if rem <= 0:
				p.injury = {}
				recovered.append(p)
			else:
				p.injury["dias_restantes"] = rem
	return recovered


# True si el jugador está actualmente lesionado.
static func is_injured(p: Player) -> bool:
	if p.injury == null or p.injury.is_empty():
		return false
	return int(p.injury.get("dias_restantes", 0)) > 0


# Resumen legible: "leve, 4 días" / "media, 17 días" / "" si sano.
static func injury_summary(p: Player) -> String:
	if not is_injured(p):
		return ""
	return "%s, %d días" % [String(p.injury.get("tipo", "?")), int(p.injury.get("dias_restantes", 0))]


# Inflinge una lesión a un jugador. Severidad determinada por el RNG dado.
# Modifica p.injury en sitio.
# Si team se proporciona, aplica el factor del physio (calidad alta = lesiones
# más cortas) y del upgrade gimnasio_top del estadio.
static func inflict(p: Player, rng: RandomNumberGenerator, team: Team = null) -> Dictionary:
	var roll: float = rng.randf()
	var dias: int
	var tipo: String
	if roll < 0.60:
		dias = rng.randi_range(3, 7)
		tipo = "leve"
	elif roll < 0.90:
		dias = rng.randi_range(10, 21)
		tipo = "media"
	else:
		dias = rng.randi_range(30, 90)
		tipo = "grave"
	# Modificadores del club
	if team != null:
		var factor: float = 1.0
		if team.staff != null:
			factor *= team.staff.injury_duration_factor()
		if team.stadium != null and "gimnasio_top" in team.stadium.upgrades:
			factor *= 0.85  # gimnasio top reduce 15% adicional
		dias = maxi(2, int(float(dias) * factor))
	p.injury = { "tipo": tipo, "dias_restantes": dias }
	return p.injury
