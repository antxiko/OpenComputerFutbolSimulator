class_name MatchEngine extends RefCounted

# Orquestador del partido. Toma dos Lineups + seed y devuelve un MatchResult.

# Eventos de tipo turnover/avance NO se logean por defecto para evitar spam.
const LOG_VERBOSE: bool = false


static func simulate(home: Lineup, away: Lineup, seed_value: int) -> MatchResult:
	var validation_h: Dictionary = home.is_valid()
	var validation_a: Dictionary = away.is_valid()
	if not validation_h["ok"]:
		push_error("Lineup local inválido: %s" % validation_h["reason"])
		return null
	if not validation_a["ok"]:
		push_error("Lineup visitante inválido: %s" % validation_a["reason"])
		return null

	var state := MatchState.new()
	state.init_from_lineups(home, away, seed_value)
	state.set_starting_on_pitch()

	# Evento KICKOFF
	state.events.append(MatchEvent.make(0, 0, MatchEvent.T_KICKOFF,
		home.team.id, "", "mid", "Saque inicial: %s vs %s" % [home.team.name, away.team.name]))

	# Bucle principal
	var halftime_emitted: bool = false
	while state.clock_seconds < MatchState.FULL_DURATION:
		var events: Array[MatchEvent] = TickResolver.resolve(state)
		state.events.append_array(events)

		# Inyectar evento de descanso si cruzamos los 45'
		if not halftime_emitted and state.clock_seconds >= MatchState.HALF_DURATION:
			state.half = 2
			halftime_emitted = true
			state.events.append(MatchEvent.make(45, 0, MatchEvent.T_HALFTIME,
				"", "", "", "Descanso. %s %d-%d %s" % [
					home.team.name, state.score_home, state.score_away, away.team.name]))
			# Tras el descanso, saque de centro lo da el equipo visitante (convención)
			state.possession_team_id = away.team.id
			state.zone = "mid"

		# Sustituciones simples (gestión IA) — comprobar cada 5 minutos a partir del 60'
		if state.clock_seconds % 300 < 70 and state.minute() >= 60:
			_consider_substitutions(state)

	# Evento FULLTIME
	state.events.append(MatchEvent.make(90, 0, MatchEvent.T_FULLTIME,
		"", "", "", "Final del partido. %s %d-%d %s" % [
			home.team.name, state.score_home, state.score_away, away.team.name]))

	return _build_result(state, seed_value)


# Sustituciones automáticas básicas. v1: si un titular está por debajo de 60% de
# condición y hay un suplente disponible en su misma posición con condición plena,
# se hace el cambio (máximo MAX_SUBS_PER_TEAM por equipo).
static func _consider_substitutions(state: MatchState) -> void:
	for lineup in [state.home_lineup, state.away_lineup]:
		var team_id: String = lineup.team.id
		if state.subs_made[team_id] >= MatchState.MAX_SUBS_PER_TEAM:
			continue
		# Encuentra al titular más cansado
		var weakest_idx: int = -1
		var weakest_cond: float = 100.0
		for i in lineup.starting_eleven.size():
			var p: Player = lineup.starting_eleven[i]
			if not state.on_pitch.get(p.id, false):
				continue  # ya sustituido o expulsado
			var cond: float = state.condition.get(p.id, 100.0)
			if cond < weakest_cond:
				weakest_cond = cond
				weakest_idx = i
		if weakest_idx < 0 or weakest_cond > 60.0:
			continue
		var to_replace: Player = lineup.starting_eleven[weakest_idx]
		var slot: String = lineup.slot_assignments[weakest_idx]
		# Encuentra suplente compatible
		var sub: Player = null
		for s in lineup.subs_available:
			if state.on_pitch.get(s.id, false):
				continue
			if state.red_carded.get(s.id, false):
				continue
			# Compatibilidad: misma posición primaria O secundaria (no jugar GK fuera de sitio)
			if slot == "GK":
				if s.primary_position() == "GK":
					sub = s
					break
			else:
				if s.primary_position() == "GK":
					continue
				if Lineup.position_familiarity(s, slot) >= 0.85:
					sub = s
					break
		if sub == null:
			continue
		# Hacer cambio
		state.on_pitch[to_replace.id] = false
		state.on_pitch[sub.id] = true
		lineup.starting_eleven[weakest_idx] = sub
		# slot_assignments queda igual: el suplente ocupa el slot del salido
		state.subs_made[team_id] += 1
		state.events.append(MatchEvent.make(state.minute(), state.second_in_minute(),
			MatchEvent.T_SUBSTITUTION, team_id, sub.id, "",
			"Cambio: entra %s por %s" % [sub.name, to_replace.name],
			to_replace.id))


# Construye el resultado final.
static func _build_result(state: MatchState, seed_value: int) -> MatchResult:
	var r := MatchResult.new()
	r.home_team_id = state.home_lineup.team.id
	r.away_team_id = state.away_lineup.team.id
	r.home_team_name = state.home_lineup.team.name
	r.away_team_name = state.away_lineup.team.name
	r.score_home = state.score_home
	r.score_away = state.score_away
	r.seed = seed_value
	r.events = state.events
	r.stats = state.stats.duplicate(true)
	# Compactar goleadores
	for pid in state.goals_scored.keys():
		var n: int = state.goals_scored[pid]
		if n > 0:
			r.scorers[pid] = n
	# Compactar tarjetas
	for pid in state.yellow_count.keys():
		var y: int = state.yellow_count[pid]
		var red: bool = state.red_carded.get(pid, false)
		if y > 0 or red:
			r.cards[pid] = { "yellows": y, "red": red }
	return r
