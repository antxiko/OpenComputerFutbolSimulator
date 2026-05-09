class_name FinancesInfo extends Resource

# Presupuestos / valores de referencia (en euros).
@export var budget_transfers_eur: int = 0
@export var wage_budget_eur_year: int = 0
@export var tv_revenue_eur_year: int = 0

# Caja líquida del club. Disminuye con gastos, aumenta con ingresos.
# Inicializada en _initialize_finances la primera vez que se carga.
@export var cash_balance: int = 0

# Resumen de la última temporada cerrada.
@export var last_season_summary: Dictionary = {}

# Patrocinios activos. Cada uno es un Dictionary:
#   { "type": "kit_main"/"kit_sleeve"/"training"/"naming",
#     "sponsor_name": String,
#     "amount_per_year": int,
#     "until_year": int }
@export var sponsors: Array = []

# Proyectos en curso (ej: ampliación de estadio que tarda N temporadas).
@export var ongoing_projects: Array = []


static func from_dict(d: Dictionary) -> FinancesInfo:
	var f := FinancesInfo.new()
	f.budget_transfers_eur = int(d.get("budget_transfers_eur", 0))
	f.wage_budget_eur_year = int(d.get("wage_budget_eur_year", 0))
	f.tv_revenue_eur_year = int(d.get("tv_revenue_eur_year", 0))
	f.cash_balance = int(d.get("cash_balance", 0))
	f.last_season_summary = d.get("last_season_summary", {}).duplicate(true)
	f.sponsors = d.get("sponsors", []).duplicate(true)
	f.ongoing_projects = d.get("ongoing_projects", []).duplicate(true)
	return f
