class_name UserSettings extends RefCounted

# Preferencias del usuario persistidas en user://settings.json.
# Separado del save game porque son preferencias de UI/sistema, no estado
# de partida. Persisten incluso si el user borra todos los saves.
#
# Estructura del JSON:
#   {
#     "ui_theme": "dark"|"light",
#     "version": 1
#   }


const SETTINGS_PATH := "user://settings.json"
const VERSION := 1

const DEFAULT_SETTINGS := {
	"ui_theme": "dark",
	"version": VERSION,
}


# Carga settings desde el JSON. Si no existe o está corrupto, devuelve defaults.
static func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return DEFAULT_SETTINGS.duplicate(true)
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return DEFAULT_SETTINGS.duplicate(true)
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return DEFAULT_SETTINGS.duplicate(true)
	# Merge con defaults para tolerar settings con campos faltantes
	var result: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	for k in parsed.keys():
		result[k] = parsed[k]
	return result


# Guarda settings al JSON. Retorna true si éxito.
static func save_settings(settings: Dictionary) -> bool:
	var to_save: Dictionary = settings.duplicate(true)
	to_save["version"] = VERSION
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo abrir %s para escritura" % SETTINGS_PATH)
		return false
	file.store_string(JSON.stringify(to_save, "  "))
	file.close()
	return true


# Helpers específicos
static func get_theme_name() -> String:
	var s: Dictionary = load_settings()
	return String(s.get("ui_theme", "dark"))


static func set_theme_name(name: String) -> bool:
	var s: Dictionary = load_settings()
	s["ui_theme"] = name
	return save_settings(s)
