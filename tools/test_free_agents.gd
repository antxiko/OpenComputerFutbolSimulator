extends SceneTree

# Test: cuántos free agents se generan y cuántos son fichados.

func _init() -> void:
	print("Test mercado verano con free agents")
	print("=".repeat(70))

	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		quit(1)
		return
	var all_teams: Array = loaded.teams.values()

	for year in [2026, 2027, 2028]:
		var market_result := TransferMarket.run(all_teams, year, 100 + year)
		print()
		print("=== Año %d ===" % year)
		print("  Renovaciones: %d" % market_result.renewals.size())
		print("  Liberados (a free agents): %d" % market_result.released.size())
		print("  Fichajes free agent: %d" % market_result.free_agent_signings.size())
		print("  Transferencias normales: %d" % market_result.transfers.size())
		print("  Free agents que NO firmaron (jubilados/fuera): %d" % (market_result.released.size() - market_result.free_agent_signings.size()))
		print()
		print("  Top 5 free agent signings:")
		var sorted_fa: Array = market_result.free_agent_signings.duplicate()
		sorted_fa.sort_custom(func(a, b): return int(a["overall"]) > int(b["overall"]))
		for i in mini(5, sorted_fa.size()):
			var fa: Dictionary = sorted_fa[i]
			print("    %s (ovr %d, salario %s €) %s -> %s" % [
				String(fa["player_name"]), int(fa["overall"]),
				_fmt(int(fa["salary"])),
				String(fa["prev_team_name"]), String(fa["signing_team_name"]),
			])

	quit(0)


static func _fmt(n: int) -> String:
	if n >= 1_000_000:
		return "%.1fM" % (float(n) / 1_000_000)
	if n >= 1_000:
		return "%dk" % (n / 1_000)
	return str(n)
