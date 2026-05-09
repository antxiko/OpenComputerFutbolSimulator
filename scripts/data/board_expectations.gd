class_name BoardExpectations extends Resource

# Expectativas del board (junta directiva) para una temporada del usuario.
# Generadas al inicio de cada temporada según reputación del club.
# Evaluadas mid-season (jornada 19) y final (post-Liga).
#
# Si el rendimiento queda BAJO las expectativas durante 6 jornadas seguidas
# en mid-season → posible despido. La evaluación final ajusta manager_reputation.

@export var year: int = 0
# Posición target en Liga (1 = campeón). Por reputación del club:
#   rep >= 90: top 3 (ganar liga, podio aceptable)
#   rep 80-89: top 6 (Champions / Europa)
#   rep 70-79: top 10 (mitad alta)
#   rep 60-69: salvación cómoda (no top 16)
#   rep < 60: solo no descender
@export var target_liga_pos: int = 12
# Resultado mínimo aceptable en Copa: 0=no exigida, 1=cuartos, 2=semis, 3=final, 4=ganarla
@export var target_cup_round: int = 0
# Ratio de salud financiera mínima al final (cash_balance >= ratio × wage_budget anual)
@export var target_finances_ratio: float = 0.0
# ¿Se ha hecho la evaluación mid-season ya?
@export var mid_season_evaluated: bool = false
# Resultado de la evaluación mid-season: "ok", "warning", "failing"
@export var mid_season_verdict: String = ""
# ¿Cumplió las expectativas al final? "exceeded", "met", "missed"
@export var final_verdict: String = ""
# Contador de jornadas consecutivas por debajo de la posición target (para despido)
@export var consecutive_underperform_jornadas: int = 0


static func generate_for_team(team: Team, season_year: int) -> BoardExpectations:
	var b := BoardExpectations.new()
	b.year = season_year
	var rep: int = team.reputation if team != null else 50

	# Posición esperada según reputación
	if rep >= 90:
		b.target_liga_pos = 3      # podio
		b.target_cup_round = 3     # final de Copa
		b.target_finances_ratio = 0.30
	elif rep >= 85:
		b.target_liga_pos = 4      # Champions
		b.target_cup_round = 2     # semis
		b.target_finances_ratio = 0.25
	elif rep >= 80:
		b.target_liga_pos = 6      # europa
		b.target_cup_round = 2
		b.target_finances_ratio = 0.20
	elif rep >= 70:
		b.target_liga_pos = 10
		b.target_cup_round = 1     # cuartos
		b.target_finances_ratio = 0.15
	elif rep >= 60:
		b.target_liga_pos = 16     # zona tranquila
		b.target_cup_round = 0
		b.target_finances_ratio = 0.10
	else:
		b.target_liga_pos = 18     # no descender (Primera tiene 20)
		b.target_cup_round = 0
		b.target_finances_ratio = 0.05

	return b


# Genera el cuerpo del mensaje del board al inicio de la temporada.
func summary_text(team_name: String) -> String:
	var lines: Array = []
	lines.append("Bienvenido a la temporada %d-%d en %s." % [year, year + 1, team_name])
	lines.append("")
	lines.append("La junta directiva espera lo siguiente:")
	lines.append("• Liga: terminar al menos en posición %d." % target_liga_pos)
	if target_cup_round > 0:
		var cup_text: String = ""
		match target_cup_round:
			1: cup_text = "alcanzar cuartos de Copa del Rey"
			2: cup_text = "alcanzar semifinales de Copa del Rey"
			3: cup_text = "llegar a la final de Copa del Rey"
			4: cup_text = "ganar la Copa del Rey"
		lines.append("• Copa: " + cup_text + ".")
	if target_finances_ratio > 0.0:
		lines.append("• Finanzas: mantener cash positivo (≥ %.0f%% de la masa salarial)." % (target_finances_ratio * 100.0))
	lines.append("")
	lines.append("Buena suerte.")
	return "\n".join(lines)


func to_dict() -> Dictionary:
	return {
		"year": year,
		"target_liga_pos": target_liga_pos,
		"target_cup_round": target_cup_round,
		"target_finances_ratio": target_finances_ratio,
		"mid_season_evaluated": mid_season_evaluated,
		"mid_season_verdict": mid_season_verdict,
		"final_verdict": final_verdict,
		"consecutive_underperform_jornadas": consecutive_underperform_jornadas,
	}


static func from_dict(d: Dictionary) -> BoardExpectations:
	var b := BoardExpectations.new()
	b.year = int(d.get("year", 0))
	b.target_liga_pos = int(d.get("target_liga_pos", 12))
	b.target_cup_round = int(d.get("target_cup_round", 0))
	b.target_finances_ratio = float(d.get("target_finances_ratio", 0.0))
	b.mid_season_evaluated = bool(d.get("mid_season_evaluated", false))
	b.mid_season_verdict = String(d.get("mid_season_verdict", ""))
	b.final_verdict = String(d.get("final_verdict", ""))
	b.consecutive_underperform_jornadas = int(d.get("consecutive_underperform_jornadas", 0))
	return b
