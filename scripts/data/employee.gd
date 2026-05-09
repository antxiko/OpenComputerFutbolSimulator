class_name Employee extends Resource

# Empleado del club: cuerpo técnico, ojeo, médico, cantera, dirección, etc.

@export var id: String = ""
@export var name: String = ""
@export var role: String = ""           # ej "fitness_coach_jefe", "jardineros"
@export var role_label: String = ""     # ej "Jefe preparación física"
@export var section: String = ""        # "tecnico" / "ojeo" / "medico" / "cantera" / "direccion" / "mantenimiento" / "estadio"
@export var quality: int = 3            # 1..5
@export var salary_eur_year: int = 0    # salario INDIVIDUAL
@export var since_year: int = 0
# Para roles repetitivos (acomodadores, jardineros, taquilleros) un solo
# Employee representa a N personas con misma calidad/salario individual.
# El nombre aparece como "Equipo de jardineros (×8)" cuando count > 1.
@export var count: int = 1


static func from_dict(d: Dictionary) -> Employee:
	var e := Employee.new()
	e.id = String(d.get("id", ""))
	e.name = String(d.get("name", ""))
	e.role = String(d.get("role", ""))
	e.role_label = String(d.get("role_label", ""))
	e.section = String(d.get("section", ""))
	e.quality = int(d.get("quality", 3))
	e.salary_eur_year = int(d.get("salary_eur_year", 0))
	e.since_year = int(d.get("since_year", 0))
	e.count = int(d.get("count", 1))
	return e


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "role": role, "role_label": role_label,
		"section": section, "quality": quality,
		"salary_eur_year": salary_eur_year, "since_year": since_year,
		"count": count,
	}


func total_salary() -> int:
	return salary_eur_year * count
