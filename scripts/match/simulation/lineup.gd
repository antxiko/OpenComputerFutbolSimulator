class_name Lineup extends RefCounted

# Un Lineup representa la alineación de un equipo para un partido.
# El "slot" es la posición que ocupa cada jugador EN ESTE PARTIDO,
# que puede no coincidir con su posición natural.

# Formaciones soportadas (slots, 11 jugadores).
# El primer slot siempre es GK; el resto va de defensa a ataque.
const FORMATIONS := {
	"4-3-3":   ["GK", "LB", "CB", "CB", "RB", "CDM", "CM", "CM", "LW", "ST", "RW"],
	"4-2-3-1": ["GK", "LB", "CB", "CB", "RB", "CDM", "CDM", "LM", "CAM", "RM", "ST"],
	"4-4-2":   ["GK", "LB", "CB", "CB", "RB", "LM", "CM", "CM", "RM", "ST", "ST"],
	"4-1-4-1": ["GK", "LB", "CB", "CB", "RB", "CDM", "LM", "CM", "CM", "RM", "ST"],
	"4-3-1-2": ["GK", "LB", "CB", "CB", "RB", "CDM", "CM", "CM", "CAM", "ST", "ST"],
	"3-5-2":   ["GK", "CB", "CB", "CB", "LWB", "CDM", "CM", "CAM", "RWB", "ST", "ST"],
	"3-4-3":   ["GK", "CB", "CB", "CB", "LWB", "CM", "CM", "RWB", "LW", "ST", "RW"],
	"5-3-2":   ["GK", "LWB", "CB", "CB", "CB", "RWB", "CDM", "CM", "CAM", "ST", "ST"],
	"5-4-1":   ["GK", "LWB", "CB", "CB", "CB", "RWB", "LM", "CM", "CM", "RM", "ST"],
}

var team: Team
var formation: String = "4-3-3"
var starting_eleven: Array[Player] = []     # tamaño 11
var slot_assignments: Array[String] = []     # tamaño 11, posición que ocupa cada uno
var subs_available: Array[Player] = []
var tactics: Tactics
var auto_picked: bool = false


# Penalización por dejar el lineup en automático ("vago tax").
# Se aplica como multiplicador < 1 a los stats del equipo durante el partido.
const AUTO_PENALTY: float = 0.95


func get_global_modifier() -> float:
	return AUTO_PENALTY if auto_picked else 1.0


func position_of(player_id: String) -> String:
	for i in starting_eleven.size():
		if starting_eleven[i].id == player_id:
			return slot_assignments[i]
	return ""


# Penalización por jugar fuera de posición.
# Si el jugador está en su posición principal: 1.0
# Si en una secundaria: 0.92
# Si fuera de su listado de posiciones: 0.78
static func position_familiarity(player: Player, slot: String) -> float:
	if player == null:
		return 1.0
	if player.positions.is_empty():
		return 0.85
	if player.positions[0] == slot:
		return 1.0
	if slot in player.positions:
		return 0.92
	# Vecinos plausibles (CB ↔ CDM, LB ↔ LWB, RW ↔ RM, etc.)
	if _are_adjacent(player.positions[0], slot):
		return 0.85
	return 0.78


static func _are_adjacent(a: String, b: String) -> bool:
	var groups: Array = [
		["LB", "LWB", "LM"],
		["RB", "RWB", "RM"],
		["CB", "CDM"],
		["CDM", "CM"],
		["CM", "CAM"],
		["CAM", "CF"],
		["LW", "LM"],
		["RW", "RM"],
		["LW", "ST"],
		["RW", "ST"],
		["CF", "ST"],
	]
	for g in groups:
		if a in g and b in g:
			return true
	return false


# Validación: el lineup tiene 11 jugadores únicos y un GK
func is_valid() -> Dictionary:
	if starting_eleven.size() != 11:
		return { "ok": false, "reason": "starting_eleven debe tener 11 jugadores (tiene %d)" % starting_eleven.size() }
	if slot_assignments.size() != 11:
		return { "ok": false, "reason": "slot_assignments debe tener 11 entradas" }
	var ids := {}
	for p in starting_eleven:
		if p == null:
			return { "ok": false, "reason": "starting_eleven contiene null" }
		if ids.has(p.id):
			return { "ok": false, "reason": "Jugador duplicado en el 11: %s" % p.id }
		ids[p.id] = true
	var gk_count := 0
	for s in slot_assignments:
		if s == "GK":
			gk_count += 1
	if gk_count != 1:
		return { "ok": false, "reason": "Debe haber exactamente 1 GK (hay %d)" % gk_count }
	return { "ok": true, "reason": "" }
