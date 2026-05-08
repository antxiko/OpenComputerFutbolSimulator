class_name Cantera extends RefCounted

# Cantera: cuando una plantilla queda demasiado mermada (por retiros y ventas),
# se generan jugadores juveniles para llenar huecos.
#
# v1 simplificado:
#   - Si un equipo tiene < MIN_SQUAD_SIZE jugadores, generar canteranos hasta ese tamaño.
#   - Posición de los canteranos: hueco en posiciones más necesitadas.
#   - Tier: Y (joven), potencial: aleatorio influenciado por la reputación del club.
#   - Nombres: placeholder por ahora ("<SHORT> Canterano AÑO #N").
#   - Edad: 17-19.

const MIN_SQUAD_SIZE: int = 20

# Posiciones que toda plantilla debe tener cubiertas (mínimo 1)
const ESSENTIAL_SLOTS: Array[String] = ["GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LW", "RW", "ST"]


# Asegura que el equipo tenga al menos MIN_SQUAD_SIZE jugadores y todas las posiciones esenciales.
# Devuelve los jugadores nuevos creados.
static func fill_squad_if_needed(team: Team, season_year: int, seed_base: int) -> Array[Player]:
	var added: Array[Player] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base ^ hash(team.id) ^ season_year

	# 1) Asegurar posiciones esenciales
	for slot: String in ESSENTIAL_SLOTS:
		if not _has_player_for_slot(team, slot):
			var p: Player = _generate_youth(team, slot, season_year, rng)
			team.players.append(p)
			added.append(p)

	# 2) Rellenar hasta MIN_SQUAD_SIZE
	while team.players.size() < MIN_SQUAD_SIZE:
		var weakest_slot: String = _find_thinnest_slot(team)
		var p: Player = _generate_youth(team, weakest_slot, season_year, rng)
		team.players.append(p)
		added.append(p)

	# 3) Generar atributos para los nuevos
	for p: Player in added:
		var player_seed: int = seed_base ^ hash(p.id)
		PlayerFactory.generate_attributes(p, season_year, player_seed)

	return added


static func _has_player_for_slot(team: Team, slot: String) -> bool:
	for p: Player in team.players:
		if slot in p.positions:
			return true
	return false


static func _find_thinnest_slot(team: Team) -> String:
	# Cuenta cuántos jugadores hay por slot, devuelve el más escaso
	var counts: Dictionary = {}
	for slot in ESSENTIAL_SLOTS:
		counts[slot] = 0
	for p: Player in team.players:
		for slot in p.positions:
			if counts.has(slot):
				counts[slot] += 1
	var min_slot: String = ESSENTIAL_SLOTS[0]
	var min_count: int = 99
	for slot in ESSENTIAL_SLOTS:
		if counts[slot] < min_count:
			min_count = counts[slot]
			min_slot = slot
	return min_slot


static func _generate_youth(team: Team, slot: String, season_year: int, rng: RandomNumberGenerator) -> Player:
	var p := Player.new()
	# ID único: <short>_yYY_NNN donde YY = año generación
	var year_short: int = season_year % 100
	var idx: int = team.players.size() + 1
	p.id = "%s_y%02d_%03d" % [team.short_name.to_lower(), year_short, idx]
	# Nombre + nacionalidad desde el pool internacional (40% ES, 60% extranjero).
	# Excepción: Athletic (basque_only) genera siempre canteranos ES.
	var name_data: Dictionary
	if team.signing_policy == "basque_only":
		name_data = NamePool.generate_spanish(rng)
	else:
		name_data = NamePool.generate(rng)
	p.name = String(name_data["name"])
	p.nationality = String(name_data["nationality"])
	# Edad 17-19
	var age: int = rng.randi_range(17, 19)
	p.birth_date = {
		"year": season_year - age,
		"month": rng.randi_range(1, 12),
		"day": rng.randi_range(1, 28),
	}
	p.positions = [slot]
	p.preferred_foot = "L" if rng.randf() < 0.30 else "R"
	# Tier: Y siempre (juvenil); potencial: depende de reputación del club
	p.tier = "Y"
	p.potential_tier = _potential_for_youth(team.reputation, rng)
	p.shirt_number = 30 + rng.randi_range(0, 20)
	p.captain = false
	p.traits = []
	p.overrides = {}
	p.joined_year = season_year
	p.contract = ContractInfo.new()
	p.contract.until_year = season_year + rng.randi_range(3, 5)
	p.contract.salary_eur_year = rng.randi_range(200_000, 600_000)
	p.contract.release_clause_eur = 10_000_000
	p.condition = 100.0
	p.morale = 70.0
	p.injury = {}
	p.history = []
	return p


# Distribución de potencial según reputación del club.
# Clubes grandes captan más jóvenes con techo alto.
static func _potential_for_youth(reputation: int, rng: RandomNumberGenerator) -> String:
	var roll: float = rng.randf()
	if reputation >= 90:
		# Élite: muchos B/A, alguno S excepcional
		if roll < 0.05: return "S"
		if roll < 0.30: return "A"
		if roll < 0.65: return "B"
		if roll < 0.90: return "C"
		return "D"
	elif reputation >= 75:
		if roll < 0.02: return "S"
		if roll < 0.15: return "A"
		if roll < 0.50: return "B"
		if roll < 0.85: return "C"
		return "D"
	elif reputation >= 60:
		if roll < 0.05: return "A"
		if roll < 0.30: return "B"
		if roll < 0.75: return "C"
		return "D"
	elif reputation >= 45:
		if roll < 0.10: return "B"
		if roll < 0.50: return "C"
		return "D"
	else:
		if roll < 0.05: return "B"
		if roll < 0.35: return "C"
		return "D"
