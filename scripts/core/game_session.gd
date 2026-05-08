class_name GameSession extends RefCounted

# Variables estáticas para pasar estado entre escenas (main_menu -> game_hub).
# En Godot 4, los static vars sobreviven a cambios de escena al estar en memoria,
# pero NO sobreviven a un reinicio del proceso (ahí es donde Save/Load entra).

# Modo de arranque del game_hub:
#   "new_game"  → empezar nueva partida con pending_user_team_id seleccionado.
#   "load"      → cargar autosave.
#   "default"   → comportamiento sin contexto (default state).
static var start_mode: String = "default"

# Equipo elegido por el usuario al empezar nueva partida.
static var pending_user_team_id: String = ""

# Slot a cargar cuando start_mode == "load". Si vacío, fallback a "autosave".
static var pending_load_slot: String = ""


# Reset del estado tras consumir.
static func consume() -> void:
	start_mode = "default"
	pending_user_team_id = ""
	pending_load_slot = ""
