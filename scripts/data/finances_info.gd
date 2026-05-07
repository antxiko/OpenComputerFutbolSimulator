class_name FinancesInfo extends Resource

@export var budget_transfers_eur: int = 0
@export var wage_budget_eur_year: int = 0
@export var tv_revenue_eur_year: int = 0


static func from_dict(d: Dictionary) -> FinancesInfo:
	var f := FinancesInfo.new()
	f.budget_transfers_eur = int(d.get("budget_transfers_eur", 0))
	f.wage_budget_eur_year = int(d.get("wage_budget_eur_year", 0))
	f.tv_revenue_eur_year = int(d.get("tv_revenue_eur_year", 0))
	return f
