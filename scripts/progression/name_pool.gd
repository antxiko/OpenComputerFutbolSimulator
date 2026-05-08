class_name NamePool extends RefCounted

# Carga el pool de nombres y apellidos por nacionalidad desde JSON.
# Usado por Cantera para generar canteranos con nombres reales.

const POOL_PATH := "res://data/name_pools/name_pools.json"

static var _loaded: bool = false
static var _weights: Dictionary = {}      # iso -> float
static var _first_names: Dictionary = {}  # iso -> Array[String]
static var _last_names: Dictionary = {}   # iso -> Array[String]
static var _total_weight: float = 0.0


static func _load_if_needed() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(POOL_PATH):
		push_warning("name_pools.json no encontrado en %s" % POOL_PATH)
		return
	var file := FileAccess.open(POOL_PATH, FileAccess.READ)
	if file == null:
		return
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_weights = parsed.get("weights", {})
	_first_names = parsed.get("first_names", {})
	_last_names = parsed.get("last_names", {})
	_total_weight = 0.0
	for k in _weights.keys():
		_total_weight += float(_weights[k])


# Devuelve { name, nationality } generando nombre+apellido coherentes.
# rng se pasa para determinismo según el id del jugador.
static func generate(rng: RandomNumberGenerator) -> Dictionary:
	_load_if_needed()
	if _total_weight <= 0.0:
		return { "name": "Sin Nombre", "nationality": "ES" }
	# 1) Escoger nacionalidad por peso
	var roll: float = rng.randf() * _total_weight
	var acc: float = 0.0
	var chosen: String = "ES"
	for k in _weights.keys():
		acc += float(_weights[k])
		if roll <= acc:
			chosen = String(k)
			break
	# 2) Sacar nombre + apellido del pool de esa nacionalidad
	var firsts: Array = _first_names.get(chosen, [])
	var lasts: Array = _last_names.get(chosen, [])
	if firsts.is_empty() or lasts.is_empty():
		# Fallback ES
		firsts = _first_names.get("ES", ["Pablo"])
		lasts = _last_names.get("ES", ["García"])
		chosen = "ES"
	var first: String = String(firsts[rng.randi() % firsts.size()])
	var last: String = String(lasts[rng.randi() % lasts.size()])
	return {
		"name": "%s %s" % [first, last],
		"nationality": chosen,
	}


# Variante: forzar nacionalidad española (útil para canteranos de Athletic
# por su signing_policy basque_only — todos los canteranos serán ES y
# normalmente jugarán para Athletic).
static func generate_spanish(rng: RandomNumberGenerator) -> Dictionary:
	_load_if_needed()
	var firsts: Array = _first_names.get("ES", ["Pablo"])
	var lasts: Array = _last_names.get("ES", ["García"])
	var first: String = String(firsts[rng.randi() % firsts.size()])
	var last: String = String(lasts[rng.randi() % lasts.size()])
	return {
		"name": "%s %s" % [first, last],
		"nationality": "ES",
	}
