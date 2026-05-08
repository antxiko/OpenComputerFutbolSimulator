extends SceneTree

# Test: simulate 1 mercado de fichajes y verificar que Athletic ahora puede fichar.

func _init() -> void:
	print("Test Athletic market — ¿consigue Athletic fichar tras el fix?")
	print("=".repeat(70))

	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		print("Errores cargando datos")
		quit(1)
		return
	var all_teams: Array = loaded.teams.values()

	# Simular 5 mercados consecutivos para ver si Athletic ficha alguna vez
	for year in [2026, 2027, 2028, 2029, 2030]:
		var market_result := TransferMarket.run(all_teams, year, 100 + year)
		var ath_signings: Array = []
		var ath_departures: Array = []
		for tr: TransferMarket.Transfer in market_result.transfers:
			if tr.to_team_id == "athletic_club":
				ath_signings.append("%s (de %s, %dM€)" % [tr.player_name, tr.from_team_name, tr.fee_eur / 1000000])
			if tr.from_team_id == "athletic_club":
				ath_departures.append("%s (a %s, %dM€)" % [tr.player_name, tr.to_team_name, tr.fee_eur / 1000000])
		print()
		print("Año %d (total transfers liga: %d):" % [year, market_result.transfers.size()])
		print("  Athletic fichajes (%d):" % ath_signings.size())
		for s in ath_signings:
			print("    + " + s)
		print("  Athletic ventas (%d):" % ath_departures.size())
		for s in ath_departures:
			print("    - " + s)

	quit(0)
