extends SceneTree

# Test rápido del SaveSystem.
# - Carga datos.
# - Simula 5 jornadas.
# - Guarda partida.
# - Modifica condition de un jugador.
# - Carga partida.
# - Verifica que la condition se restauró.

func _init() -> void:
	print("=" .repeat(70))
	print("Test SaveSystem")
	print("=" .repeat(70))

	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		print("Errores de carga, abortando")
		quit(1)
		return
	var all_teams: Array = loaded.teams.values()
	var primera: Array = all_teams.filter(func(t: Team) -> bool: return t.division == "primera")
	var segunda: Array = all_teams.filter(func(t: Team) -> bool: return t.division == "segunda")
	print("Equipos: %d (primera %d, segunda %d)" % [all_teams.size(), primera.size(), segunda.size()])

	var ids: Array = primera.map(func(t: Team) -> String: return t.id)
	var calendar: Array = CalendarGenerator.generate(ids, 42)
	var table := LeagueTable.new()
	table.init_with_teams(primera)

	# Simular 5 jornadas
	var team_index: Dictionary = {}
	for t in primera: team_index[t.id] = t
	var seed_counter: int = 42000
	for j in 5:
		for fixture in calendar[j]:
			var home: Team = team_index[fixture["home_id"]]
			var away: Team = team_index[fixture["away_id"]]
			for p in home.players: p.condition = 100.0
			for p in away.players: p.condition = 100.0
			var hl := AutoLineup.pick(home, home.tactics_default.formation)
			var al := AutoLineup.pick(away, away.tactics_default.formation)
			seed_counter += 1
			var r: MatchResult = MatchEngine.simulate(hl, al, seed_counter)
			table.record_match(r)
	print("Simuladas 5 jornadas. Tabla líder:")
	var top_row: LeagueTable.TeamRow = table.sorted_rows()[0]
	print("  %s — %d pts" % [top_row.team_name, top_row.points()])

	# Modificar reputación y condition de un equipo (Real Madrid) para detectar diferencias
	var rma: Team = null
	for t in primera:
		if t.id == "real_madrid":
			rma = t
			break
	rma.reputation = 77  # cambio detectable
	rma.players[0].condition = 33.3
	print("Pre-save: Real Madrid rep=%d, jugador[0].condition=%.1f" % [rma.reputation, rma.players[0].condition])

	# Guardar
	var save_table_segunda := LeagueTable.new()
	save_table_segunda.init_with_teams(segunda)
	var res: Dictionary = SaveSystem.save_game("test_slot", 2027, all_teams, 5, 0, table, save_table_segunda)
	print("Save: %s" % str(res))

	# Modificar el estado en memoria DESPUÉS de guardar
	rma.reputation = 99
	rma.players[0].condition = 100.0
	print("Post-modify: rep=%d, condition=%.1f" % [rma.reputation, rma.players[0].condition])

	# Cargar
	var save_data: SaveSystem.SaveData = SaveSystem.load_game("test_slot")
	if save_data == null:
		print("ERROR: load_game devolvió null")
		quit(1)
		return
	print("Loaded: year=%d, primera_jornada=%d" % [save_data.year, save_data.primera_jornada])

	# Verificar
	var loaded_rma: Team = null
	for t: Team in save_data.teams:
		if t.id == "real_madrid":
			loaded_rma = t
			break
	print("Loaded RMA: rep=%d, jugador[0].condition=%.1f" % [loaded_rma.reputation, loaded_rma.players[0].condition])
	if loaded_rma.reputation == 77 and abs(loaded_rma.players[0].condition - 33.3) < 0.1:
		print("✓ Save/Load CORRECTO — estado preservado.")
	else:
		print("✗ Save/Load FALLA — estado no se preservó.")

	# Verificar tabla
	var restored_table: LeagueTable = SaveSystem.restore_table(save_data.primera_table_snapshot, save_data.teams)
	var restored_top: LeagueTable.TeamRow = restored_table.sorted_rows()[0]
	print("Restored tabla líder: %s — %d pts" % [restored_top.team_name, restored_top.points()])

	# Limpieza
	SaveSystem.delete_save("test_slot")
	print("\nTest completado.")
	quit(0)
