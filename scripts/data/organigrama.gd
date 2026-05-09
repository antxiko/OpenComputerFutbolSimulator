class_name Organigrama extends Resource

# Lista detallada de empleados del club agrupada por sección.
# Reemplaza la abstracción simple de StaffInfo (que se deriva de aquí).

@export var employees: Array = []  # Array[Employee]


# Empleados por sección
func by_section(section: String) -> Array:
	return employees.filter(func(e: Employee) -> bool: return e.section == section)


func total_salary() -> int:
	var t: int = 0
	for e: Employee in employees:
		t += e.total_salary()
	return t


func total_headcount() -> int:
	var n: int = 0
	for e: Employee in employees:
		n += e.count
	return n


# Calidad media de una sección (jefe pesa más)
func section_avg_quality(section: String) -> float:
	var section_employees: Array = by_section(section)
	if section_employees.is_empty():
		return 0.0
	var total: float = 0.0
	for e: Employee in section_employees:
		# El jefe pesa el doble
		var weight: float = 2.0 if e.role.contains("jefe") or e.role.contains("director") else 1.0
		total += float(e.quality) * weight
	# normalizar por suma de pesos
	var weights: float = 0.0
	for e in section_employees:
		weights += 2.0 if e.role.contains("jefe") or e.role.contains("director") else 1.0
	return total / weights


static func from_dict(d: Dictionary) -> Organigrama:
	var o := Organigrama.new()
	var arr: Array = d.get("employees", [])
	o.employees = []
	for emp_d in arr:
		o.employees.append(Employee.from_dict(emp_d))
	return o


func to_dict() -> Dictionary:
	var arr: Array = []
	for e: Employee in employees:
		arr.append(e.to_dict())
	return { "employees": arr }
