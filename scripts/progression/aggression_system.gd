class_name AggressionSystem extends RefCounted

# Atributo aggression 0-100 por jugador.
# Determina cuántas tarjetas tiende a recibir.
#
# Inicialización:
#   1. Si aggression == 0 (sin inicializar):
#      a. Buscar nombre normalizado en data/aggression_overrides.json
#         (top tarjeteros 25-26 scrapeados de Marca).
#      b. Si no está, usar default por posición + jitter aleatorio basado
#         en el id del jugador (determinista).
#
# Update después de temporada: ajustar según tarjetas recibidas. Players
# con muchas amarillas suben +1/+5; con pocas bajan -1.

const OVERRIDES_PATH := "res://data/aggression_overrides.json"

# Default por posición principal (sesgo realista — defensores físicos > atacantes)
const POSITION_BASE := {
	"GK": 35,
	"CB": 60, "LB": 50, "RB": 50, "LWB": 50, "RWB": 50,
	"CDM": 60, "CM": 48, "CAM": 38, "LM": 42, "RM": 42,
	"LW": 38, "RW": 38, "CF": 42, "ST": 42,
}


# Cache del JSON para no leerlo cada llamada.
static var _overrides_cache: Dictionary = {}
static var _overrides_loaded: bool = false


static func _load_overrides() -> void:
	if _overrides_loaded:
		return
	_overrides_loaded = true
	if not FileAccess.file_exists(OVERRIDES_PATH):
		return
	var file := FileAccess.open(OVERRIDES_PATH, FileAccess.READ)
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var players_data: Dictionary = parsed.get("players", {})
	for k in players_data.keys():
		var rec: Dictionary = players_data[k]
		_overrides_cache[String(k)] = int(rec.get("aggression", 50))


# Normaliza nombre quitando acentos y bajando a minúsculas.
static func _normalize(s: String) -> String:
	# Mapeo manual de acentos comunes (Godot no tiene unicodedata)
	var out: String = s.to_lower()
	var pairs: Array = [
		["á","a"], ["é","e"], ["í","i"], ["ó","o"], ["ú","u"], ["ü","u"], ["ñ","n"],
		["à","a"], ["è","e"], ["ì","i"], ["ò","o"], ["ù","u"],
		["â","a"], ["ê","e"], ["î","i"], ["ô","o"], ["û","u"],
		["ç","c"],
	]
	for p in pairs:
		out = out.replace(String(p[0]), String(p[1]))
	return out.strip_edges()


# Inicializa aggression de un jugador si está a 0.
static func init_player(player: Player) -> void:
	if player.aggression > 0:
		return
	_load_overrides()
	# 1) Override desde scrape — match conservador para evitar colisiones de
	# nombres comunes (e.g., "mikel" matcheando varios jugadores).
	var key: String = _normalize(player.name)
	# 1a) Match exacto sobre nombre completo normalizado
	if _overrides_cache.has(key):
		player.aggression = clampi(_overrides_cache[key], 10, 99)
		return
	# 1b) Match por tokens
	var key_tokens: PackedStringArray = key.split(" ", false)
	if key_tokens.size() == 0:
		_apply_position_default(player)
		return
	var key_last: String = key_tokens[-1]
	for k in _overrides_cache.keys():
		var ok_str: String = String(k)
		var ok_tokens: PackedStringArray = ok_str.split(" ", false)
		if ok_tokens.size() == 0:
			continue
		if ok_tokens.size() == 1:
			# Override de una sola palabra (apellido único): match SOLO si
			# coincide con el último apellido del jugador y tiene >= 5 chars.
			if ok_tokens[0].length() >= 5 and ok_tokens[0] == key_last:
				player.aggression = clampi(_overrides_cache[k], 10, 99)
				return
		else:
			# Override de varias palabras: requerir que TODOS los tokens
			# (excluyendo iniciales tipo "j.") aparezcan en el nombre del jugador.
			var all_match: bool = true
			for tok in ok_tokens:
				var t: String = String(tok)
				if t.ends_with("."):
					continue  # ignorar iniciales
				if t.length() < 3:
					continue
				if not (t in key):
					all_match = false
					break
			if all_match:
				player.aggression = clampi(_overrides_cache[k], 10, 99)
				return
	_apply_position_default(player)


static func _apply_position_default(player: Player) -> void:
	var primary: String = player.primary_position()
	var base: int = int(POSITION_BASE.get(primary, 50))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(player.id)
	base += rng.randi_range(-8, 8)
	player.aggression = clampi(base, 10, 99)


# Actualiza aggression según las tarjetas de la temporada que acaba de terminar.
static func update_after_season(all_teams: Array) -> void:
	for t: Team in all_teams:
		for p: Player in t.players:
			var y: int = p.yellow_cards_season
			var r: int = p.red_cards_season
			var delta: int = 0
			if y >= 10:
				delta += 5
			elif y >= 7:
				delta += 3
			elif y >= 4:
				delta += 1
			elif y <= 2:
				delta -= 1
			delta += r * 3  # cada roja +3
			if delta != 0:
				p.aggression = clampi(p.aggression + delta, 10, 99)


# Helpers
static func is_aggressive(p: Player) -> bool:
	return p.aggression >= 70
