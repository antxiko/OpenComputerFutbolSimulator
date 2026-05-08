extends SceneTree

# Test: cuántos jugadores se marcan como basque_eligible tras data_loader.

func _init() -> void:
	print("Test BasqueHeuristic + basque_eligible flag")
	print("=".repeat(70))

	# Tests de heurística pura
	var samples := [
		["Iñaki Williams", true],
		["Aymeric Laporte", true],
		["Mikel Vesga", true],
		["Oihan Sancet", true],
		["Yuri Berchiche", true],
		["Dani Vivian", true],
		["Marcos Llorente", true],  # Llorente tiene origen vasco
		["Lewandowski", false],
		["Vinicius Junior", false],
		["Antoine Griezmann", false],
		["Pedro Sánchez", false],
		["José Antonio Caro", false],
	]
	print("Heuristic checks:")
	var hits: int = 0
	var miss: int = 0
	for s in samples:
		var name: String = s[0]
		var expected: bool = s[1]
		var actual: bool = BasqueHeuristic.is_basque_name(name)
		var ok: String = "OK" if actual == expected else "MISS"
		if actual == expected: hits += 1
		else: miss += 1
		print("  [%s] %s -> %s (esperado %s)" % [ok, name, actual, expected])
	print()
	print("Hits: %d / %d (%d miss)" % [hits, hits + miss, miss])
	print()

	# Aplicar a data
	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		print("Errores cargando datos")
		quit(1)
		return

	var per_team: Dictionary = {}
	var total_eligible: int = 0
	var total: int = 0
	for t: Team in loaded.teams.values():
		var n: int = 0
		var n_total: int = 0
		for p: Player in t.players:
			n_total += 1
			total += 1
			if p.basque_eligible:
				n += 1
				total_eligible += 1
		per_team[t.short_name] = "%d/%d" % [n, n_total]
	print("Total basque_eligible: %d / %d (%.1f%%)" % [total_eligible, total, 100.0 * total_eligible / total])
	print()
	print("Por equipo (Athletic primero):")
	var sorted_keys: Array = per_team.keys()
	sorted_keys.sort()
	# Athletic primero
	if "ATH" in sorted_keys:
		print("  ATH: %s" % String(per_team["ATH"]))
	for k in sorted_keys:
		if k == "ATH":
			continue
		print("  %s: %s" % [k, String(per_team[k])])

	quit(0)
