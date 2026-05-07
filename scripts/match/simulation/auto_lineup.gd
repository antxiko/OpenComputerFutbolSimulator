class_name AutoLineup extends RefCounted

# Auto-selecciona los 11 mejores jugadores de un equipo para una formación dada.
# El lineup resultante tiene auto_picked = true, lo que aplica la "vago tax"
# (-5% a todos los stats del equipo durante el partido).


static func pick(team: Team, formation: String = "") -> Lineup:
	if formation == "":
		formation = team.tactics_default.formation if team.tactics_default else "4-3-3"
	if not Lineup.FORMATIONS.has(formation):
		push_error("Formación desconocida: %s — usando 4-3-3" % formation)
		formation = "4-3-3"

	var slots: Array = Lineup.FORMATIONS[formation]
	var available: Array[Player] = team.players.duplicate()
	# Excluir lesionados a más de 0 días
	available = available.filter(func(p: Player) -> bool:
		return not _is_injured(p)
	)

	var selected: Array[Player] = []
	var assigned: Array[String] = []

	for slot_str: String in slots:
		var best: Player = null
		var best_score: float = -1.0
		for p in available:
			var score: float = _fit_score(p, slot_str)
			if score > best_score:
				best_score = score
				best = p
		if best == null:
			push_error("No hay candidato para slot %s en %s" % [slot_str, team.name])
			continue
		selected.append(best)
		assigned.append(slot_str)
		available.erase(best)

	# Banquillo: 7 mejores restantes, garantizando al menos un GK si lo hay
	var subs: Array[Player] = _pick_subs(available, 7)

	var lineup := Lineup.new()
	lineup.team = team
	lineup.formation = formation
	lineup.starting_eleven = selected
	lineup.slot_assignments = assigned
	lineup.subs_available = subs
	lineup.tactics = team.tactics_default.duplicate() if team.tactics_default else Tactics.new()
	lineup.auto_picked = true
	return lineup


static func _fit_score(player: Player, slot: String) -> float:
	var familiarity: float = Lineup.position_familiarity(player, slot)
	var overall_at_slot: int = PlayerFactory.compute_overall(player, slot)
	# Penalizamos algo más a los Y (juveniles) para que la IA prefiera senior salvo si Y es muy bueno
	var youth_penalty: float = 0.92 if player.tier == "Y" else 1.0
	return float(overall_at_slot) * familiarity * youth_penalty


static func _is_injured(player: Player) -> bool:
	if player.injury == null or player.injury.is_empty():
		return false
	var days: int = int(player.injury.get("dias_restantes", 0))
	return days > 0


static func _pick_subs(remaining: Array[Player], count: int) -> Array[Player]:
	# Ordenar por overall genérico
	remaining.sort_custom(func(a: Player, b: Player) -> bool:
		return PlayerFactory.compute_overall(a) > PlayerFactory.compute_overall(b)
	)
	var subs: Array[Player] = []
	var has_gk: bool = false
	# Garantizar 1 GK en el banquillo si existe
	for p in remaining:
		if p.primary_position() == "GK":
			subs.append(p)
			has_gk = true
			break
	# Resto, hasta count
	for p in remaining:
		if subs.size() >= count:
			break
		if p in subs:
			continue
		subs.append(p)
	return subs
