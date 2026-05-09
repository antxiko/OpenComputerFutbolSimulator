class_name Aging extends RefCounted

# Procesa el envejecimiento entre temporadas.
# - Edad +1 (implícita: nuestro modelo calcula edad desde birth_date, así que basta avanzar el year)
# - Probabilidad de retiro según edad
# - Re-cálculo de atributos con la nueva edad (curva en PlayerFactory)

const RETIREMENT_BY_AGE := {
	32: 0.02,
	33: 0.05,
	34: 0.10,
	35: 0.20,
	36: 0.35,
	37: 0.55,
	38: 0.75,
	39: 0.92,
}
# 40+ siempre se retira


# Procesa un equipo. new_season_year es el año de la PRÓXIMA temporada
# (los jugadores tendrán esa edad cuando arranque).
# Devuelve el array de jugadores retirados (ya removidos de team.players).
static func age_team(team: Team, new_season_year: int, seed_base: int) -> Array[Player]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base ^ hash(team.id) ^ new_season_year

	var retired: Array[Player] = []
	var still_active: Array[Player] = []
	for p: Player in team.players:
		var age: int = p.age_at(new_season_year, 7, 1)
		var retire_p: float = 0.0
		if age >= 40:
			retire_p = 1.0
		elif RETIREMENT_BY_AGE.has(age):
			retire_p = float(RETIREMENT_BY_AGE[age])
		if rng.randf() < retire_p:
			retired.append(p)
		else:
			still_active.append(p)
			# Re-generar atributos para que la curva de edad aplique sobre la nueva edad.
			# Usamos el MISMO seed que en la generación inicial para que la progresión
			# sea determinista (el jugador tiene su "destino" estadístico).
			var player_seed: int = seed_base ^ hash(p.id)
			PlayerFactory.generate_attributes(p, new_season_year, player_seed)
			# Restaurar condition al inicio de temporada
			p.condition = 100.0
	team.players = still_active
	# v0.3.2: aplicar bonus de training_focus a los jugadores que se quedaron
	_apply_training_focus_bonus(team)
	return retired


# Aplica +1 al atributo correspondiente al focus de entrenamiento del equipo.
# Solo a jugadores ≤30 años (jóvenes mejoran más con entrenamiento).
static func _apply_training_focus_bonus(team: Team) -> void:
	if team.training_focus == "" or team.training_focus == "general":
		return
	var attr_key: String = ""
	match team.training_focus:
		"ataque": attr_key = "ataque"
		"defensa": attr_key = "defensa"
		"fisico": attr_key = "fisico"
		"porteria": attr_key = "porteria"
		_: return
	for p: Player in team.players:
		# Solo jugadores jóvenes mejoran significativamente con training
		if attr_key == "porteria" and p.primary_position() != "GK":
			continue
		if p.attributes.has(attr_key):
			var current: int = int(p.attributes[attr_key])
			# +1 absoluto, capado a 99
			p.attributes[attr_key] = mini(99, current + 1)


# Aplica aging a TODOS los equipos. Devuelve un dict { team_id: Array[Player retirados] }.
static func age_all(teams: Array, new_season_year: int, seed_base: int) -> Dictionary:
	var retirements: Dictionary = {}
	for t: Team in teams:
		var retired: Array[Player] = age_team(t, new_season_year, seed_base)
		retirements[t.id] = retired
	return retirements
