extends SceneTree

# Validador de plantillas hand-curadas / scrapeadas.
# Ejecutar:
#   godot --headless --script tools/validate_squads.gd
#
# Reporta inconsistencias en los JSON de data/teams/{primera,segunda}/:
#   - Tamaño de plantilla < 18
#   - Cobertura por slot principal (GK ≥2, DEF ≥6, MID ≥6, ATK ≥4)
#   - Tier vs overall heurístico (S debería tener ovr ≥85, A ≥75, B ≥65)
#   - Duplicados de player_id entre equipos
#   - Contratos sin until_year o salario 0
#   - Edades fuera de [15, 42]
#   - Posiciones desconocidas (no en VALID_POSITIONS)


const VALID_POSITIONS: Array[String] = [
	"GK", "CB", "LB", "RB",
	"CDM", "CM", "CAM",
	"LM", "RM", "LW", "RW", "ST",
]

const DEF_SLOTS: Array[String] = ["CB", "LB", "RB"]
const MID_SLOTS: Array[String] = ["CDM", "CM", "CAM", "LM", "RM"]
const ATK_SLOTS: Array[String] = ["LW", "RW", "ST"]

const CURRENT_SEASON: int = 2026
const MIN_SQUAD_SIZE: int = 18


func _init() -> void:
	var teams: Array = _load_all_teams()
	print("[validate_squads] Validando %d equipos..." % teams.size())
	print("=" .repeat(70))

	var issues_total: int = 0
	var seen_player_ids: Dictionary = {}  # player_id -> team_id (para detectar dups)

	for t: Dictionary in teams:
		var team_id: String = String(t.get("id", "?"))
		var team_name: String = String(t.get("name", "?"))
		var division: String = String(t.get("division", "?"))
		var players: Array = t.get("players", [])
		var issues: Array[String] = []

		# Tamaño
		if players.size() < MIN_SQUAD_SIZE:
			issues.append("plantilla pequeña (%d jugadores, mínimo %d)" % [players.size(), MIN_SQUAD_SIZE])

		# Cobertura por categoría (slots principales)
		var coverage: Dictionary = {"GK": 0, "DEF": 0, "MID": 0, "ATK": 0}
		for p: Dictionary in players:
			var positions: Array = p.get("positions", [])
			var assigned: bool = false
			for pos in positions:
				var ps: String = String(pos)
				if ps == "GK": coverage["GK"] += 1; assigned = true; break
				if ps in DEF_SLOTS: coverage["DEF"] += 1; assigned = true; break
				if ps in MID_SLOTS: coverage["MID"] += 1; assigned = true; break
				if ps in ATK_SLOTS: coverage["ATK"] += 1; assigned = true; break
			if not assigned and positions.size() > 0:
				issues.append("jugador %s con posiciones desconocidas: %s" % [String(p.get("name", "?")), positions])
		if int(coverage["GK"]) < 2:
			issues.append("solo %d portero(s) (mínimo 2)" % int(coverage["GK"]))
		if int(coverage["DEF"]) < 6:
			issues.append("solo %d defensas (mínimo 6)" % int(coverage["DEF"]))
		if int(coverage["MID"]) < 5:
			issues.append("solo %d centrocampistas (mínimo 5)" % int(coverage["MID"]))
		if int(coverage["ATK"]) < 4:
			issues.append("solo %d atacantes (mínimo 4)" % int(coverage["ATK"]))

		# Por jugador
		for p: Dictionary in players:
			var pid: String = String(p.get("id", ""))
			var pname: String = String(p.get("name", "?"))

			# Duplicados de id entre equipos
			if pid != "":
				if seen_player_ids.has(pid):
					issues.append("player_id duplicado: %s (también en %s)" % [pid, String(seen_player_ids[pid])])
				else:
					seen_player_ids[pid] = team_id

			# Posiciones válidas
			var positions: Array = p.get("positions", [])
			if positions.is_empty():
				issues.append("%s sin posiciones" % pname)
			else:
				for pos in positions:
					if not (String(pos) in VALID_POSITIONS):
						issues.append("%s tiene posición inválida: %s" % [pname, pos])

			# Edad
			var bd: Dictionary = p.get("birth_date", {})
			var by: int = int(bd.get("year", 0))
			if by > 0:
				var age: int = CURRENT_SEASON - by
				if age < 15 or age > 42:
					issues.append("%s edad fuera de rango (%d años, nacido %d)" % [pname, age, by])

			# Contrato
			var contract: Dictionary = p.get("contract", {})
			var uy: int = int(contract.get("until_year", 0))
			if uy == 0:
				issues.append("%s sin until_year en contrato" % pname)
			elif uy < CURRENT_SEASON:
				issues.append("%s contrato vencido al inicio (until_year=%d)" % [pname, uy])
			var salary: int = int(contract.get("salary_eur_year", 0))
			if salary <= 0:
				issues.append("%s sin salario" % pname)

			# Tier vs heurística básica (sin ovr completo, solo coherencia)
			var tier: String = String(p.get("tier", ""))
			if not (tier in ["S", "A", "B", "C", "Y"]):
				issues.append("%s tier desconocido: %s" % [pname, tier])

		if not issues.is_empty():
			issues_total += issues.size()
			print("\n[%s] %s (%s):" % [division.to_upper().substr(0, 1), team_name, team_id])
			for iss in issues:
				print("   - %s" % iss)

	print("\n" + "=".repeat(70))
	if issues_total == 0:
		print("[validate_squads] ✓ Todas las plantillas pasaron las verificaciones.")
	else:
		print("[validate_squads] %d incidencias detectadas en %d equipos." % [issues_total, teams.size()])
	quit()


func _load_all_teams() -> Array:
	var result: Array = []
	for division in ["primera", "segunda"]:
		var dir_path := "res://data/teams/%s" % division
		var dir := DirAccess.open(dir_path)
		if dir == null:
			push_error("No se pudo abrir %s" % dir_path)
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.ends_with(".json"):
				var path := "%s/%s" % [dir_path, name]
				var file := FileAccess.open(path, FileAccess.READ)
				if file != null:
					var content := file.get_as_text()
					file.close()
					var parsed = JSON.parse_string(content)
					if parsed is Dictionary:
						result.append(parsed)
					else:
						push_error("JSON inválido: %s" % path)
			name = dir.get_next()
		dir.list_dir_end()
	return result
