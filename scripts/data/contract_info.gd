class_name ContractInfo extends Resource

@export var until_year: int = 0
@export var salary_eur_year: int = 0
@export var release_clause_eur: int = 0


static func from_dict(d: Dictionary) -> ContractInfo:
	var c := ContractInfo.new()
	c.until_year = int(d.get("until_year", 0))
	c.salary_eur_year = int(d.get("salary_eur_year", 0))
	c.release_clause_eur = int(d.get("release_clause_eur", 0))
	return c
