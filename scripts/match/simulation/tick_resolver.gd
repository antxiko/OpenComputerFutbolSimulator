class_name TickResolver extends RefCounted

# Resuelve un tick (una jugada/posesión). Muta el state y devuelve los eventos generados.
#
# Granularidad: cada tick avanza el reloj 25-70 segundos (configurable).
# Modelo de zonas: def → mid → atk (POV del equipo en posesión).

const TICK_DUR_MIN: int = 18
const TICK_DUR_MAX: int = 50

# Probabilidades de evento per-tick (independientes del outcome principal)
const FOUL_BASE_PROB: float = 0.17        # ~28-35 faltas por partido total
const YELLOW_GIVEN_FOUL: float = 0.16
const RED_PROB_PER_TICK: float = 0.0005
const INJURY_BASE_PROB: float = 0.005     # ~0.7-1 lesión por partido en promedio


static func resolve(state: MatchState) -> Array[MatchEvent]:
	var events: Array[MatchEvent] = []
	var rng: RandomNumberGenerator = state.rng

	# 1) Calcular fuerzas
	var poss_lineup: Lineup = state.lineup_for(state.possession_team_id)
	var def_lineup: Lineup = state.lineup_for(state.other_team_id(state.possession_team_id))
	var atk_str: float = PositionContribution.zone_strength(poss_lineup, "attack", state.zone)
	var def_str: float = PositionContribution.zone_strength(def_lineup, "defense", state.zone)
	# Delta amplificado: la diferencia normalizada respecto al máximo.
	# Para fuerzas similares delta ≈ 0; cuando un lado dobla al otro, delta ≈ 0.5.
	var delta: float = (atk_str - def_str) / max(maxf(atk_str, def_str), 1.0)
	delta = clampf(delta, -0.6, 0.6)

	# 2) Decidir outcome principal
	var outcome: String = _decide_outcome(state.zone, delta, rng)

	# 3) Aplicar outcome → eventos
	match outcome:
		"advance":
			_advance_zone(state)
			# La mayoría de avances no son interesantes, no se logean.
		"keep":
			pass
		"lose":
			_resolve_turnover(state, false)
		"shot":
			events.append_array(_resolve_shot(state, poss_lineup, def_lineup))
		"corner":
			events.append(_make_event(state, MatchEvent.T_CORNER, _pick_actor(poss_lineup, "attack", state.zone, rng).id, "Córner"))
			state.stats[state.possession_team_id]["corners"] += 1
			# El córner puede convertirse en tiro
			if rng.randf() < 0.30:
				events.append_array(_resolve_shot(state, poss_lineup, def_lineup, true))
			else:
				_resolve_turnover(state, false)
		"offside":
			events.append(_make_event(state, MatchEvent.T_OFFSIDE, _pick_actor(poss_lineup, "attack", state.zone, rng).id, "Fuera de juego"))
			state.stats[state.possession_team_id]["offsides"] += 1
			_resolve_turnover(state, false)

	# 4) Eventos aleatorios independientes (faltas, tarjetas, lesiones)
	_maybe_foul(state, def_lineup, events, rng)
	_maybe_injury(state, events, rng)

	# 5) Avanzar reloj
	var dur: int = rng.randi_range(TICK_DUR_MIN, TICK_DUR_MAX)
	state.clock_seconds += dur
	state.stats[state.possession_team_id]["possession_secs"] += dur

	# 6) Reducir condición física a los que están en pista
	_update_fatigue(state, dur)

	return events


# ============================================================================
# Decisión de outcome
# ============================================================================
# Recibe delta ya calculado por el llamante (rango ~ -0.6..+0.6).
static func _decide_outcome(zone: String, delta: float, rng: RandomNumberGenerator) -> String:
	var probs: Dictionary = {}

	if zone == "def":
		probs = {
			"advance": 0.48 + delta * 0.40,
			"keep":    0.30,
			"lose":    0.18 - delta * 0.30,
			"foul":    0.04,
		}
	elif zone == "mid":
		probs = {
			"advance": 0.40 + delta * 0.40,
			"keep":    0.25,
			"lose":    0.27 - delta * 0.30,
			"offside": 0.04,
			"foul":    0.04,
		}
	else:  # atk
		probs = {
			"shot":    0.30 + delta * 0.30,
			"keep":    0.12,
			"corner":  0.14,
			"offside": 0.05,
			"lose":    0.33 - delta * 0.30,
			"foul":    0.06,
		}
	# "foul" como outcome principal aquí significa "falta a favor del atacante" (juego parado)
	# La falta como evento aleatorio (cometida por defensor) se gestiona en _maybe_foul.

	# Normalizar (clamp a >=0 y normalizar)
	var total: float = 0.0
	for k in probs.keys():
		probs[k] = maxf(probs[k], 0.0)
		total += probs[k]
	if total <= 0.0:
		return "keep"

	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k in probs.keys():
		acc += probs[k]
		if roll <= acc:
			return k
	return "keep"


# ============================================================================
# Movimiento de zona y posesión
# ============================================================================
static func _advance_zone(state: MatchState) -> void:
	match state.zone:
		"def": state.zone = "mid"
		"mid": state.zone = "atk"
		"atk": state.zone = "atk"


static func _resolve_turnover(state: MatchState, _from_shot: bool) -> void:
	# Cambia posesión y se invierte la zona (lo que era atk del A es def del B)
	state.possession_team_id = state.other_team_id(state.possession_team_id)
	state.zone = _inverse_zone(state.zone)


static func _inverse_zone(zone: String) -> String:
	match zone:
		"def": return "atk"
		"mid": return "mid"
		"atk": return "def"
		_: return "mid"


# ============================================================================
# Resolución de tiros
# ============================================================================
static func _resolve_shot(
	state: MatchState,
	poss: Lineup,
	defense: Lineup,
	from_set_piece: bool = false
) -> Array[MatchEvent]:
	var events: Array[MatchEvent] = []
	var rng: RandomNumberGenerator = state.rng

	state.stats[state.possession_team_id]["shots"] += 1

	# Goleador potencial
	var shooter: Player = _pick_actor(poss, "attack", "atk", rng)
	if shooter == null:
		return events
	var shooter_slot: String = _slot_of(poss, shooter.id)

	# Asistente potencial (excluye al shooter)
	var assist_player: Player = _pick_assistant(poss, shooter, rng)

	# Atributos relevantes
	var tiro: int = int(shooter.attributes.get("tiro", 50))
	var ataque: int = int(shooter.attributes.get("ataque", 50))
	var mentalidad: int = int(shooter.attributes.get("mentalidad", 50))

	# 1) ¿Es a portería? Modulado por tiro+composure (target ~32-38% on-target)
	var on_target_p: float = 0.09 + (float(tiro) / 100.0) * 0.35 + (float(mentalidad) / 100.0) * 0.05
	if from_set_piece:
		on_target_p *= 0.85  # ángulos más cerrados desde córner

	# 2) ¿Es bloqueado por defensores?
	var def_str: float = PositionContribution.zone_strength(defense, "defense", "def")
	var atk_str: float = PositionContribution.zone_strength(poss, "attack", "atk")
	var block_p: float = 0.13 + clampf((def_str - atk_str) / maxf(atk_str + def_str, 1.0), -0.08, 0.14)

	var roll1: float = rng.randf()
	if roll1 < block_p:
		state.stats[state.possession_team_id]["shots_blocked"] += 1
		events.append(_make_event(state, MatchEvent.T_SHOT_BLOCKED, shooter.id,
			"Tiro bloqueado de %s" % shooter.name))
		_resolve_turnover(state, true)
		return events

	if rng.randf() >= on_target_p:
		state.stats[state.possession_team_id]["shots_off_target"] += 1
		events.append(_make_event(state, MatchEvent.T_SHOT_OFF, shooter.id,
			"%s dispara fuera" % shooter.name))
		_resolve_turnover(state, true)
		return events

	# 3) On target — el portero rival hace su intento de parada
	state.stats[state.possession_team_id]["shots_on_target"] += 1
	var keeper: Player = _find_goalkeeper(defense)
	var save_p: float = 0.50
	if keeper != null:
		var porteria: int = int(keeper.attributes.get("porteria", 50))
		var keeper_mental: int = int(keeper.attributes.get("mentalidad", 50))
		# Calibrado para ~62-68% de paradas (target ~2.5-2.8 goles/partido)
		save_p = 0.30 + (float(porteria) / 100.0) * 0.50 + (float(keeper_mental) / 100.0) * 0.05
		# Tiro del shooter rebaja la chance de parada
		save_p -= (float(tiro) / 100.0) * 0.10
		save_p = clampf(save_p, 0.22, 0.93)

	if rng.randf() < save_p and keeper != null:
		state.stats[state.other_team_id(state.possession_team_id)]["saves"] += 1
		events.append(_make_event(state, MatchEvent.T_SAVE, keeper.id,
			"Parada de %s a tiro de %s" % [keeper.name, shooter.name]))
		_resolve_turnover(state, true)
		return events

	# ¡GOL!
	state.stats[state.possession_team_id]["goals"] += 1
	state.goals_scored[shooter.id] = state.goals_scored.get(shooter.id, 0) + 1
	if state.is_home(state.possession_team_id):
		state.score_home += 1
	else:
		state.score_away += 1

	var desc: String = "¡GOL de %s!" % shooter.name
	var assist_id: String = ""
	if assist_player != null and rng.randf() < 0.65:  # 65% de los goles tienen asistencia
		assist_id = assist_player.id
		desc += " (asistencia: %s)" % assist_player.name

	var ev: MatchEvent = _make_event(state, MatchEvent.T_GOAL, shooter.id, desc)
	ev.secondary_player_id = assist_id
	events.append(ev)

	# Saque de centro: la posesión la toma el equipo encajante en mid
	state.possession_team_id = state.other_team_id(state.possession_team_id)
	state.zone = "mid"
	return events


# ============================================================================
# Faltas / tarjetas (eventos aleatorios secundarios)
# ============================================================================
static func _maybe_foul(state: MatchState, def_lineup: Lineup, events: Array[MatchEvent], rng: RandomNumberGenerator) -> void:
	if rng.randf() >= FOUL_BASE_PROB:
		return
	# El defensor comete falta
	var fouler: Player = _pick_actor(def_lineup, "defense", _inverse_zone(state.zone), rng)
	if fouler == null:
		return
	state.stats[def_lineup.team.id]["fouls"] += 1
	events.append(_make_event_for_team(state, def_lineup.team.id, MatchEvent.T_FOUL,
		fouler.id, "Falta de %s" % fouler.name))

	# ¿Tarjeta?
	if rng.randf() < YELLOW_GIVEN_FOUL:
		state.yellow_count[fouler.id] = state.yellow_count.get(fouler.id, 0) + 1
		state.stats[def_lineup.team.id]["yellows"] += 1
		events.append(_make_event_for_team(state, def_lineup.team.id, MatchEvent.T_YELLOW,
			fouler.id, "Amarilla a %s" % fouler.name))
		# Doble amarilla → roja
		if state.yellow_count[fouler.id] >= 2 and not state.red_carded.get(fouler.id, false):
			state.red_carded[fouler.id] = true
			state.on_pitch[fouler.id] = false
			state.stats[def_lineup.team.id]["reds"] += 1
			events.append(_make_event_for_team(state, def_lineup.team.id, MatchEvent.T_RED,
				fouler.id, "Roja por doble amarilla a %s" % fouler.name))
	# Roja directa rara
	if rng.randf() < RED_PROB_PER_TICK and not state.red_carded.get(fouler.id, false):
		state.red_carded[fouler.id] = true
		state.on_pitch[fouler.id] = false
		state.stats[def_lineup.team.id]["reds"] += 1
		events.append(_make_event_for_team(state, def_lineup.team.id, MatchEvent.T_RED,
			fouler.id, "Roja directa a %s" % fouler.name))


# ============================================================================
# Selección de actores
# ============================================================================
static func _pick_actor(lineup: Lineup, role: String, zone: String, rng: RandomNumberGenerator) -> Player:
	var weights: Array = []
	var players: Array = []
	var total: float = 0.0
	for i in lineup.starting_eleven.size():
		var p: Player = lineup.starting_eleven[i]
		var slot: String = lineup.slot_assignments[i]
		var w: float = PositionContribution.actor_weight(p, slot, role, zone)
		if w > 0.0:
			weights.append(w)
			players.append(p)
			total += w
	if total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i in players.size():
		acc += weights[i]
		if roll <= acc:
			return players[i]
	return players[-1]


static func _pick_assistant(lineup: Lineup, shooter: Player, rng: RandomNumberGenerator) -> Player:
	# Asistente: peso = pase * presence en mid+atk de jugadores creativos. Excluye al shooter.
	var weights: Array = []
	var players: Array = []
	var total: float = 0.0
	for i in lineup.starting_eleven.size():
		var p: Player = lineup.starting_eleven[i]
		if p.id == shooter.id:
			continue
		var slot: String = lineup.slot_assignments[i]
		var w_mid: float = PositionContribution.actor_weight(p, slot, "attack", "mid")
		var w_atk: float = PositionContribution.actor_weight(p, slot, "attack", "atk")
		# Bonus por pase
		var pase_bonus: float = float(p.attributes.get("pase", 50)) / 50.0
		var w: float = (w_mid * 0.4 + w_atk * 0.6) * pase_bonus
		if w > 0.0:
			weights.append(w)
			players.append(p)
			total += w
	if total <= 0.0:
		return null
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i in players.size():
		acc += weights[i]
		if roll <= acc:
			return players[i]
	return players[-1]


static func _find_goalkeeper(lineup: Lineup) -> Player:
	for i in lineup.starting_eleven.size():
		if lineup.slot_assignments[i] == "GK":
			return lineup.starting_eleven[i]
	return null


static func _slot_of(lineup: Lineup, player_id: String) -> String:
	for i in lineup.starting_eleven.size():
		if lineup.starting_eleven[i].id == player_id:
			return lineup.slot_assignments[i]
	return ""


# ============================================================================
# Fatiga
# ============================================================================
static func _update_fatigue(state: MatchState, seconds: int) -> void:
	# Cada segundo en pista resta condición. Ratio: 100 cond / 90min = ~0.018 por segundo.
	# Lo modulamos por intensidad (mid: 1.0, atk: 1.2, def: 0.8) y físico del jugador.
	var base_drop_per_sec: float = 0.020
	var intensity: float = 1.0
	match state.zone:
		"atk": intensity = 1.20
		"def": intensity = 0.85
	var drop: float = base_drop_per_sec * float(seconds) * intensity

	for team_lineup in [state.home_lineup, state.away_lineup]:
		for p in team_lineup.starting_eleven:
			if not state.on_pitch.get(p.id, false):
				continue
			var stamina_factor: float = 1.0 - (float(p.attributes.get("fisico", 50)) - 50.0) / 200.0
			# fisico=50 → factor 1.0; fisico=90 → factor 0.8; fisico=20 → factor 1.15
			var actual_drop: float = drop * stamina_factor
			state.condition[p.id] = maxf(state.condition[p.id] - actual_drop, 10.0)
			# Reflejar en el Player resource para que sea visible fuera del partido
			p.condition = state.condition[p.id]


# ============================================================================
# Helpers para crear eventos
# ============================================================================
static func _make_event(state: MatchState, type: String, player_id: String, description: String) -> MatchEvent:
	return MatchEvent.make(state.minute(), state.second_in_minute(), type,
		state.possession_team_id, player_id, state.zone, description)


static func _make_event_for_team(state: MatchState, team_id: String, type: String, player_id: String, description: String) -> MatchEvent:
	return MatchEvent.make(state.minute(), state.second_in_minute(), type,
		team_id, player_id, state.zone, description)


# Lesiones aleatorias durante el partido.
static func _maybe_injury(state: MatchState, events: Array, rng: RandomNumberGenerator) -> void:
	if rng.randf() >= INJURY_BASE_PROB:
		return
	# Escoger jugador en pista (uniforme entre los 22 que jueguen)
	var candidates: Array = []
	for lineup in [state.home_lineup, state.away_lineup]:
		for p: Player in lineup.starting_eleven:
			if state.on_pitch.get(p.id, false) and not state.red_carded.get(p.id, false):
				candidates.append({ "player": p, "team_id": lineup.team.id })
	if candidates.is_empty():
		return
	var idx: int = rng.randi() % candidates.size()
	var pick: Dictionary = candidates[idx]
	var p: Player = pick["player"]
	# Si ya está lesionado (caso raro: lesión en tick anterior pero aún visible), saltar
	if InjurySystem.is_injured(p):
		return
	var info: Dictionary = InjurySystem.inflict(p, rng)
	state.on_pitch[p.id] = false  # se marcha del campo
	events.append(MatchEvent.make(state.minute(), state.second_in_minute(),
		MatchEvent.T_INJURY, String(pick["team_id"]), p.id, state.zone,
		"Lesión %s de %s (%d días)" % [info["tipo"], p.name, int(info["dias_restantes"])]))
