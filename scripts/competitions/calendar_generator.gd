class_name CalendarGenerator extends RefCounted

# Genera el calendario de una liga de N equipos (N par) usando algoritmo round-robin.
#
# Para N equipos:
#   - Cada equipo juega contra cada otro 2 veces (ida y vuelta) = 2 * (N - 1) jornadas
#   - Cada jornada tiene N/2 partidos
#   - La segunda vuelta intercambia local/visitante respecto a la primera
#
# Output: Array[Jornada] donde cada Jornada = Array[Fixture] = Array[{ home_id, away_id }]


static func generate(team_ids: Array, seed_value: int = 0) -> Array:
	# Si el número es impar, añadimos un "bye" (no implementado, exigimos par)
	if team_ids.size() % 2 != 0:
		push_error("CalendarGenerator requiere número par de equipos (recibido: %d)" % team_ids.size())
		return []

	# Mezclar para que la posición inicial no determine los emparejamientos
	var shuffled: Array = team_ids.duplicate()
	if seed_value != 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		shuffled.shuffle()  # GDScript no acepta rng directo; aceptamos no-determinismo aquí

	var n: int = shuffled.size()
	var rounds_first_half: int = n - 1
	var first_half: Array = []  # Array[Array[Dictionary]]

	# Algoritmo de rotación: el primer equipo queda fijo, los demás rotan.
	var rotation: Array = shuffled.duplicate()  # working list
	for r in rounds_first_half:
		var jornada: Array = []
		# Emparejamientos: rotation[0] con rotation[-1], rotation[1] con rotation[-2], etc.
		for i in n / 2:
			var home_id: String = rotation[i]
			var away_id: String = rotation[n - 1 - i]
			# Alternar localía por jornada para que no se acumulen en un mismo equipo
			if r % 2 == 1 and i == 0:
				var tmp: String = home_id
				home_id = away_id
				away_id = tmp
			jornada.append({ "home_id": home_id, "away_id": away_id })
		first_half.append(jornada)
		# Rotar: mantener rotation[0], mover rotation[1] al final, rotar el resto un paso
		var fixed: String = rotation[0]
		var tail: Array = rotation.slice(1)
		var rotated: Array = [fixed, tail[-1]] + tail.slice(0, -1)
		rotation = rotated

	# Segunda vuelta: misma estructura con local/visitante invertido
	var second_half: Array = []
	for jornada in first_half:
		var jornada_vuelta: Array = []
		for fixture: Dictionary in jornada:
			jornada_vuelta.append({
				"home_id": fixture["away_id"],
				"away_id": fixture["home_id"],
			})
		second_half.append(jornada_vuelta)

	return first_half + second_half


# Validador: cada equipo debe jugar exactamente (N-1)*2 partidos, mitad local mitad visitante.
static func validate(calendar: Array, team_ids: Array) -> Dictionary:
	var n: int = team_ids.size()
	var expected_matches: int = (n - 1) * 2
	var stats: Dictionary = {}
	for tid in team_ids:
		stats[tid] = { "home": 0, "away": 0, "vs": {} }
	for jornada in calendar:
		for fixture: Dictionary in jornada:
			var h: String = fixture["home_id"]
			var a: String = fixture["away_id"]
			stats[h]["home"] += 1
			stats[a]["away"] += 1
			var key_h: String = "%s_h" % a
			var key_a: String = "%s_a" % h
			stats[h]["vs"][key_h] = stats[h]["vs"].get(key_h, 0) + 1
			stats[a]["vs"][key_a] = stats[a]["vs"].get(key_a, 0) + 1
	var errors: Array[String] = []
	for tid in team_ids:
		var s: Dictionary = stats[tid]
		var total: int = s["home"] + s["away"]
		if total != expected_matches:
			errors.append("%s juega %d partidos (esperado %d)" % [tid, total, expected_matches])
		if s["home"] != n - 1:
			errors.append("%s juega %d como local (esperado %d)" % [tid, s["home"], n - 1])
		if s["away"] != n - 1:
			errors.append("%s juega %d como visitante (esperado %d)" % [tid, s["away"], n - 1])
		# Cada rival, una vez como local y otra como visitante
		for other in team_ids:
			if String(other) == tid:
				continue
			var key_h2: String = "%s_h" % other
			var key_a2: String = "%s_a" % other
			if int(s["vs"].get(key_h2, 0)) != 1:
				errors.append("%s vs %s (en casa de %s): %d veces" % [
					tid, other, other, int(s["vs"].get(key_h2, 0))])
			if int(s["vs"].get(key_a2, 0)) != 1:
				errors.append("%s vs %s (en casa de %s): %d veces" % [
					tid, other, tid, int(s["vs"].get(key_a2, 0))])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"jornadas": calendar.size(),
		"matches_per_jornada": (calendar[0].size() if calendar.size() > 0 else 0),
		"total_matches": calendar.size() * (calendar[0].size() if calendar.size() > 0 else 0),
	}
