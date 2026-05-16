class_name UIThemeManager extends RefCounted

# Gestor global del tema activo. Sin autoload — usa static var y métodos
# para evitar tener que modificar project.godot.
#
# Uso típico:
#   var bg = UIThemeManager.get_current().bg_primary
#   UIThemeManager.apply("light")  # cambia y persiste
#
# Themes disponibles: "dark" (default), "light".


const THEME_DARK := "dark"
const THEME_LIGHT := "light"

static var _current: UITheme = null
static var _current_name: String = ""


# Devuelve el tema activo, inicializando con "dark" la primera vez.
static func get_current() -> UITheme:
	if _current == null:
		_current = dark_theme()
		_current_name = THEME_DARK
	return _current


static func get_current_name() -> String:
	if _current == null:
		get_current()
	return _current_name


# Aplica un tema por nombre. Si el nombre no se reconoce, no hace nada.
# Devuelve true si se aplicó un cambio, false si ya estaba activo o nombre inválido.
static func apply(theme_name: String) -> bool:
	if theme_name == _current_name and _current != null:
		return false
	match theme_name:
		THEME_DARK:
			_current = dark_theme()
			_current_name = THEME_DARK
			return true
		THEME_LIGHT:
			_current = light_theme()
			_current_name = THEME_LIGHT
			return true
	return false


# ============================================================================
# Factories
# ============================================================================
static func dark_theme() -> UITheme:
	var t := UITheme.new()
	# Backgrounds
	t.bg_primary = Color8(26, 27, 31)
	t.bg_secondary = Color8(37, 38, 43)
	t.bg_card = Color8(45, 46, 51)
	t.bg_overlay = Color(0.0, 0.0, 0.0, 0.70)
	# Texto
	t.text_primary = Color8(229, 231, 235)
	t.text_secondary = Color8(161, 165, 174)
	t.text_muted = Color8(107, 114, 128)
	t.text_on_accent = Color(1.0, 1.0, 1.0)
	# Acentos
	t.accent_primary = Color8(220, 38, 38)
	t.accent_success = Color8(34, 197, 94)
	t.accent_warning = Color8(251, 191, 36)
	t.accent_danger = Color8(239, 68, 68)
	t.accent_info = Color8(59, 130, 246)
	# Sidebar
	t.sidebar_bg = Color8(31, 32, 36)
	t.sidebar_active_bg = Color8(61, 31, 31)
	t.sidebar_active_text = Color8(248, 113, 113)
	t.sidebar_hover_bg = Color8(42, 43, 48)
	t.sidebar_text = Color8(199, 202, 209)
	# Bordes
	t.border_subtle = Color8(58, 59, 64)
	t.border_strong = Color8(79, 80, 87)
	# Mini pitch
	t.pitch_bg = Color8(42, 45, 58)
	t.pitch_lines = Color(1.0, 1.0, 1.0, 0.85)
	t.player_team_a = Color8(239, 68, 68)
	t.player_team_b = Color8(59, 130, 246)
	t.player_gk = Color8(251, 191, 36)
	t.player_label_bg = Color(0.0, 0.0, 0.0, 0.80)
	# Tiers
	t.tier_s = Color8(255, 217, 51)
	t.tier_a = Color8(153, 255, 178)
	t.tier_b = Color8(153, 204, 255)
	t.tier_c = Color8(217, 217, 217)
	t.tier_y = Color8(229, 178, 255)
	return t


static func light_theme() -> UITheme:
	var t := UITheme.new()
	# Backgrounds
	t.bg_primary = Color8(245, 245, 247)
	t.bg_secondary = Color8(234, 234, 236)
	t.bg_card = Color8(255, 255, 255)
	t.bg_overlay = Color(0.0, 0.0, 0.0, 0.55)
	# Texto
	t.text_primary = Color8(17, 24, 39)
	t.text_secondary = Color8(107, 114, 128)
	t.text_muted = Color8(156, 163, 175)
	t.text_on_accent = Color(1.0, 1.0, 1.0)
	# Acentos
	t.accent_primary = Color8(220, 38, 38)
	t.accent_success = Color8(22, 163, 74)
	t.accent_warning = Color8(245, 158, 11)
	t.accent_danger = Color8(220, 38, 38)
	t.accent_info = Color8(37, 99, 235)
	# Sidebar
	t.sidebar_bg = Color8(255, 255, 255)
	t.sidebar_active_bg = Color8(254, 242, 242)
	t.sidebar_active_text = Color8(220, 38, 38)
	t.sidebar_hover_bg = Color8(245, 245, 247)
	t.sidebar_text = Color8(75, 85, 99)
	# Bordes
	t.border_subtle = Color8(229, 231, 235)
	t.border_strong = Color8(209, 213, 219)
	# Mini pitch
	t.pitch_bg = Color8(46, 125, 50)
	t.pitch_lines = Color(1.0, 1.0, 1.0, 0.95)
	t.player_team_a = Color8(220, 38, 38)
	t.player_team_b = Color8(37, 99, 235)
	t.player_gk = Color8(245, 158, 11)
	t.player_label_bg = Color(0.0, 0.0, 0.0, 0.70)
	# Tiers (en theme light bajamos saturación para que no quemen sobre blanco)
	t.tier_s = Color8(217, 119, 6)    # ámbar
	t.tier_a = Color8(22, 163, 74)    # verde
	t.tier_b = Color8(37, 99, 235)    # azul
	t.tier_c = Color8(75, 85, 99)     # gris medio
	t.tier_y = Color8(147, 51, 234)   # violeta
	return t
