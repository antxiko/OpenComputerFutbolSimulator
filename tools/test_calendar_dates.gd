extends SceneTree

func _init() -> void:
	print("Test DateUtil")
	print("=".repeat(60))
	# Día semana de fechas conocidas
	var samples := [
		[2026, 1, 1, "jueves"],
		[2026, 8, 22, "sábado"],
		[2027, 1, 1, "viernes"],
		[2027, 8, 21, "sábado"],
		[2028, 1, 1, "sábado"],
		[2028, 5, 28, "domingo"],
	]
	for s in samples:
		var dow: int = DateUtil.day_of_week(int(s[0]), int(s[1]), int(s[2]))
		var name: String = DateUtil.DOW_NAMES[dow]
		var ok: String = "OK" if name == String(s[3]) else "MISS"
		print("  [%s] %d-%02d-%02d → %s (esperado %s)" % [ok, s[0], s[1], s[2], name, s[3]])

	# Test next_dow
	print()
	print("next_dow(2026-08-18, sábado):", DateUtil.next_dow(DateUtil.make(2026, 8, 18), DateUtil.DOW_SA))

	# Test calendario con fechas
	print()
	print("Calendario Liga 2026-27 (10 primeras jornadas):")
	var ids := []
	for i in 20:
		ids.append("team%02d" % i)
	var calendar: Array = CalendarGenerator.generate_with_dates(ids, 2026, 42, [])
	for j_idx in mini(10, calendar.size()):
		var jornada: Array = calendar[j_idx]
		var sample = jornada[0]
		print("  J%d: %s — %s vs %s (%d partidos)" % [
			j_idx + 1,
			DateUtil.format_short(sample["match_date"]),
			String(sample["home_id"]),
			String(sample["away_id"]),
			jornada.size(),
		])

	# Última jornada
	if calendar.size() > 0:
		var last: Array = calendar[-1]
		var last_sample = last[0]
		print()
		print("Jornada %d (última): %s" % [
			calendar.size(),
			DateUtil.format_long(last_sample["match_date"]),
		])

	# Distribución de partidos en una jornada (todos los días)
	print()
	print("Distribución jornada 1:")
	for f: Dictionary in calendar[0]:
		print("  %s — %s vs %s" % [
			DateUtil.format_short(f["match_date"]),
			String(f["home_id"]),
			String(f["away_id"]),
		])

	quit(0)
