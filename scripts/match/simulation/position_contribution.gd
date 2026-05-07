class_name PositionContribution extends RefCounted

# Cuánto contribuye cada posición a la fuerza ofensiva/defensiva en cada zona.
# Las zonas son relativas al equipo en cuestión:
#   "def" = tercio defensivo propio (cerca de su portería)
#   "mid" = centro del campo
#   "atk" = tercio ofensivo (cerca de la portería rival)
#
# Cuando el equipo A tiene el balón en su zona "atk", el equipo B está defendiendo
# en su propia zona "def" (mismo tercio del campo). Por eso la consulta cruzada es:
#     A.zone_strength("attack", "atk") vs B.zone_strength("defense", "def")
#     A.zone_strength("attack", "mid") vs B.zone_strength("defense", "mid")
#     A.zone_strength("attack", "def") vs B.zone_strength("defense", "atk")  # presión alta del rival

const PRESENCE := {
	"GK":  { "attack": { "def": 0.05, "mid": 0.0,  "atk": 0.0  }, "defense": { "def": 1.0,  "mid": 0.0,  "atk": 0.0  } },
	"CB":  { "attack": { "def": 0.30, "mid": 0.10, "atk": 0.05 }, "defense": { "def": 1.0,  "mid": 0.30, "atk": 0.0  } },
	"LB":  { "attack": { "def": 0.20, "mid": 0.40, "atk": 0.20 }, "defense": { "def": 0.90, "mid": 0.40, "atk": 0.05 } },
	"RB":  { "attack": { "def": 0.20, "mid": 0.40, "atk": 0.20 }, "defense": { "def": 0.90, "mid": 0.40, "atk": 0.05 } },
	"LWB": { "attack": { "def": 0.10, "mid": 0.55, "atk": 0.30 }, "defense": { "def": 0.70, "mid": 0.50, "atk": 0.10 } },
	"RWB": { "attack": { "def": 0.10, "mid": 0.55, "atk": 0.30 }, "defense": { "def": 0.70, "mid": 0.50, "atk": 0.10 } },
	"CDM": { "attack": { "def": 0.40, "mid": 0.55, "atk": 0.10 }, "defense": { "def": 0.55, "mid": 1.0,  "atk": 0.10 } },
	"CM":  { "attack": { "def": 0.20, "mid": 0.70, "atk": 0.30 }, "defense": { "def": 0.30, "mid": 0.80, "atk": 0.10 } },
	"CAM": { "attack": { "def": 0.05, "mid": 0.50, "atk": 0.80 }, "defense": { "def": 0.05, "mid": 0.40, "atk": 0.10 } },
	"LM":  { "attack": { "def": 0.10, "mid": 0.55, "atk": 0.55 }, "defense": { "def": 0.20, "mid": 0.55, "atk": 0.20 } },
	"RM":  { "attack": { "def": 0.10, "mid": 0.55, "atk": 0.55 }, "defense": { "def": 0.20, "mid": 0.55, "atk": 0.20 } },
	"LW":  { "attack": { "def": 0.0,  "mid": 0.40, "atk": 0.90 }, "defense": { "def": 0.05, "mid": 0.30, "atk": 0.30 } },
	"RW":  { "attack": { "def": 0.0,  "mid": 0.40, "atk": 0.90 }, "defense": { "def": 0.05, "mid": 0.30, "atk": 0.30 } },
	"CF":  { "attack": { "def": 0.0,  "mid": 0.30, "atk": 0.85 }, "defense": { "def": 0.0,  "mid": 0.10, "atk": 0.30 } },
	"ST":  { "attack": { "def": 0.0,  "mid": 0.20, "atk": 1.0  }, "defense": { "def": 0.0,  "mid": 0.05, "atk": 0.30 } },
}


# Suma la fuerza del equipo (lineup) en una zona/rol concretos.
static func zone_strength(lineup: Lineup, role: String, zone: String) -> float:
	var total: float = 0.0
	for i in lineup.starting_eleven.size():
		var player: Player = lineup.starting_eleven[i]
		var slot: String = lineup.slot_assignments[i]
		var presence: float = float(_get_nested(PRESENCE, [slot, role, zone], 0.0))
		if presence <= 0.0:
			continue
		var ovr: int = PlayerFactory.compute_overall(player, slot)
		var familiarity: float = Lineup.position_familiarity(player, slot)
		var fatigue_factor: float = clampf(player.condition / 100.0, 0.5, 1.0)
		total += presence * float(ovr) * familiarity * fatigue_factor
	# Modificador global del lineup (auto-pick penalty, etc.)
	total *= lineup.get_global_modifier()
	# Modificador táctico
	total *= tactics_modifier(lineup.tactics, role, zone)
	return total


# Multiplicador derivado de la táctica para un (rol, zona).
static func tactics_modifier(tactics: Tactics, role: String, zone: String) -> float:
	if tactics == null:
		return 1.0
	var mult: float = 1.0

	# Mentality afecta global atk/def
	if role == "attack":
		match tactics.mentality:
			"muy_ofensivo": mult *= 1.20
			"ofensivo":     mult *= 1.10
			"defensivo":    mult *= 0.92
			"muy_defensivo":mult *= 0.84
			_: pass
	else:  # defense
		match tactics.mentality:
			"muy_ofensivo": mult *= 0.90
			"ofensivo":     mult *= 0.95
			"defensivo":    mult *= 1.05
			"muy_defensivo":mult *= 1.10
			_: pass

	# Pressing afecta sobre todo defensa por zona
	if role == "defense":
		match tactics.pressing:
			"alto":
				if zone == "atk": mult *= 1.30
				elif zone == "mid": mult *= 1.10
				else: mult *= 0.95
			"medio":
				pass
			"bajo":
				if zone == "atk": mult *= 0.75
				elif zone == "mid": mult *= 0.95
				else: mult *= 1.10

	# Tempo afecta ataque (más rápido = más caos, más oportunidades pero menos preciso)
	if role == "attack":
		match tactics.tempo:
			"rapido": mult *= 1.05
			"lento":  mult *= 0.97
			_: pass

	return mult


# Probabilidad de que un jugador concreto sea el "actor" en una jugada
# del equipo en una zona. Útil para escoger goleador/asistente etc.
static func actor_weight(player: Player, slot: String, role: String, zone: String) -> float:
	var presence: float = float(_get_nested(PRESENCE, [slot, role, zone], 0.0))
	if presence <= 0.0:
		return 0.0
	var ovr: int = PlayerFactory.compute_overall(player, slot)
	return presence * float(ovr)


# Helper para acceso anidado seguro a dicts.
static func _get_nested(d: Dictionary, keys: Array, default_val: Variant) -> Variant:
	var cur: Variant = d
	for k in keys:
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(k):
			return default_val
		cur = cur[k]
	return cur
