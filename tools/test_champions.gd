extends SceneTree

# Test rápido de Champions: carga equipos, escoge top 4 por reputación,
# genera 12 europeos y simula la edición completa.

func _init() -> void:
	print("Test Champions League — simulación completa")
	print("=".repeat(70))

	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		push_error("Errores cargando datos")
		quit(1)
		return
	var all_teams: Array = loaded.teams.values()

	# Top 4 por reputación entre los Primera
	var primera: Array = all_teams.filter(func(t: Team) -> bool: return t.division == "primera")
	primera.sort_custom(func(a: Team, b: Team) -> bool: return a.reputation > b.reputation)
	var top4: Array = primera.slice(0, 4)
	print("Top 4 españoles (por reputación):")
	for t: Team in top4:
		print("  %s (rep %d)" % [t.name, t.reputation])

	# Generar 12 europeos
	var t0: int = Time.get_ticks_msec()
	var euros: Array = EuropeanTeams.generate_all(2026, 12345)
	print()
	print("Equipos europeos generados (%d):" % euros.size())
	for t: Team in euros:
		print("  %s (rep %d, %d jugadores)" % [t.name, t.reputation, t.players.size()])

	# Simular Champions
	print()
	print("Simulando Champions League 2026-27...")
	var t1: int = Time.get_ticks_msec()
	var bracket := ChampionsSimulator.run(top4, euros, 2026, 9999)
	var t2: int = Time.get_ticks_msec()
	print("Tiempo: %.2fs" % ((t2 - t1) / 1000.0))
	print()
	print(ChampionsSimulator.summarize(bracket))

	quit(0)
