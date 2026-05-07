extends Node

# Iteración 4: bucle de carrera multi-temporada (20 años).

const START_YEAR := 2026
const N_SEASONS := 20
const SEED_BASE := 42


func _ready() -> void:
	print("=" .repeat(100))
	print("OpenComputerFutbolSimulator — carrera %d-%d (%d temporadas)" % [
		START_YEAR, START_YEAR + N_SEASONS, N_SEASONS])
	print("=" .repeat(100))

	var loaded := DataLoader.load_all_teams(START_YEAR)
	print("Carga inicial: %d equipos | %d jugadores" % [
		loaded.teams.size(), loaded.player_id_index.size()])
	if loaded.errors.size() > 0:
		for e in loaded.errors:
			print("  - %s" % e)
		return

	var all_teams: Array = loaded.teams.values()

	print("\nProgreso (una línea por temporada):")
	print("─" .repeat(100))
	var t0: int = Time.get_ticks_msec()
	var history := CareerSimulator.run(all_teams, START_YEAR, N_SEASONS, SEED_BASE)
	var t1: int = Time.get_ticks_msec()
	print("─" .repeat(100))
	print("Tiempo total: %.1f s para %d temporadas" % [(t1 - t0) / 1000.0, N_SEASONS])

	# Tabla final del último año (Primera)
	if history.seasons.size() > 0:
		var last_year: int = history.start_year + history.seasons.size() - 1
		var primera_final: Array = []
		for t: Team in all_teams:
			if t.division == "primera":
				primera_final.append(t)
		print("\n" + "═" .repeat(100))
		print("Estado de los equipos al final de la carrera (división actual)")
		print("═" .repeat(100))
		var by_div: Dictionary = { "primera": [], "segunda": [] }
		for t: Team in all_teams:
			by_div[t.division].append(t)
		print("  Primera (%d): %s" % [
			by_div["primera"].size(),
			", ".join(by_div["primera"].map(func(t: Team) -> String: return t.short_name))])
		print("  Segunda (%d): %s" % [
			by_div["segunda"].size(),
			", ".join(by_div["segunda"].map(func(t: Team) -> String: return t.short_name))])

	CareerSimulator.print_history_summary(history, all_teams)
