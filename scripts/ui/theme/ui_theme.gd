class_name UITheme extends Resource

# Paleta semántica de colores para todo el simulador.
# Se crean instancias de UITheme con valores concretos en UIThemeManager
# (dark_theme / light_theme). El resto del código consulta las propiedades
# via UIThemeManager.current.<role> en vez de hardcodear colores.

# ============================================================================
# Backgrounds (fondos)
# ============================================================================
@export var bg_primary: Color = Color(0.10, 0.11, 0.12)    # fondo general de la ventana
@export var bg_secondary: Color = Color(0.14, 0.15, 0.17)  # paneles secundarios
@export var bg_card: Color = Color(0.17, 0.18, 0.20)       # tarjetas / cards
@export var bg_overlay: Color = Color(0.0, 0.0, 0.0, 0.65) # modal overlays

# ============================================================================
# Texto
# ============================================================================
@export var text_primary: Color = Color(0.90, 0.91, 0.93)    # textos principales
@export var text_secondary: Color = Color(0.65, 0.67, 0.72)  # subtítulos / labels
@export var text_muted: Color = Color(0.42, 0.44, 0.48)      # placeholders / disabled
@export var text_on_accent: Color = Color(1.0, 1.0, 1.0)     # texto sobre fondos accent

# ============================================================================
# Acentos semánticos
# ============================================================================
@export var accent_primary: Color = Color(0.86, 0.15, 0.15)   # rojo principal (CTA, logo)
@export var accent_success: Color = Color(0.13, 0.77, 0.37)   # verde positivo (V, +)
@export var accent_warning: Color = Color(0.98, 0.75, 0.14)   # amarillo (morale, atención)
@export var accent_danger: Color = Color(0.94, 0.27, 0.27)    # rojo derrota (D)
@export var accent_info: Color = Color(0.23, 0.51, 0.96)      # azul informativo

# ============================================================================
# Sidebar
# ============================================================================
@export var sidebar_bg: Color = Color(0.12, 0.13, 0.15)
@export var sidebar_active_bg: Color = Color(0.24, 0.12, 0.12)
@export var sidebar_active_text: Color = Color(0.97, 0.44, 0.44)
@export var sidebar_hover_bg: Color = Color(0.17, 0.18, 0.20)
@export var sidebar_text: Color = Color(0.78, 0.79, 0.82)

# ============================================================================
# Bordes
# ============================================================================
@export var border_subtle: Color = Color(0.22, 0.23, 0.26)
@export var border_strong: Color = Color(0.32, 0.33, 0.36)

# ============================================================================
# Mini pitch (campo cenital del Dashboard)
# ============================================================================
@export var pitch_bg: Color = Color(0.10, 0.30, 0.14)
@export var pitch_lines: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var player_team_a: Color = Color(0.94, 0.27, 0.27)
@export var player_team_b: Color = Color(0.23, 0.51, 0.96)
@export var player_gk: Color = Color(0.98, 0.75, 0.14)
@export var player_label_bg: Color = Color(0.0, 0.0, 0.0, 0.70)

# ============================================================================
# Tier colors (jugadores por tier — reemplaza colores hardcoded en plantilla)
# ============================================================================
@export var tier_s: Color = Color(1.0, 0.85, 0.20)
@export var tier_a: Color = Color(0.60, 1.0, 0.70)
@export var tier_b: Color = Color(0.60, 0.80, 1.0)
@export var tier_c: Color = Color(0.85, 0.85, 0.85)
@export var tier_y: Color = Color(0.90, 0.70, 1.0)


# Convenience: devuelve el color de tier por string.
func color_for_tier(t: String) -> Color:
	match t:
		"S": return tier_s
		"A": return tier_a
		"B": return tier_b
		"C": return tier_c
		"Y": return tier_y
	return text_primary
