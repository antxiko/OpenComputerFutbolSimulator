class_name OrganigramaFactory extends RefCounted

# Genera la plantilla de empleados de un club según su tamaño:
#   - GRANDE   (rep ≥ 85, capacity ≥ 50000): organigrama completo, ~30 empleados.
#   - MEDIANO  (rep 70-84,  capacity 25000-49999): organigrama medio, ~13 empleados.
#   - PEQUEÑO  (rep < 70 o capacity < 25000): organigrama básico, ~6 empleados.
#
# Cada empleado tiene rol específico, calidad inicial según tamaño del club, y
# salario calculado a partir de calidad × tipo de rol.

# Plantilla: Array de [role, role_label, section, base_salary_factor]
# Salario final = base_salary_factor × quality² × 100_000
const TEMPLATE_GRANDE := [
	# Dirección
	["director_deportivo", "Director deportivo", "direccion", 25],
	["director_financiero", "Director financiero", "direccion", 18],
	["director_comunicacion", "Director comunicación", "direccion", 14],
	["staff_comunicacion_1", "Jefe prensa", "direccion", 8],
	["staff_comunicacion_2", "Community manager", "direccion", 4],
	# Cuerpo técnico
	["segundo_entrenador", "Segundo entrenador", "tecnico", 18],
	["preparador_fisico_jefe", "Jefe preparación física", "tecnico", 14],
	["preparador_fisico_2", "Preparador físico asistente", "tecnico", 7],
	["preparador_fisico_3", "Preparador físico asistente", "tecnico", 7],
	["entrenador_porteros", "Entrenador de porteros", "tecnico", 10],
	["analista_video", "Analista de vídeo", "tecnico", 8],
	["analista_set_pieces", "Analista de balón parado", "tecnico", 7],
	# Ojeo
	["jefe_ojeadores", "Jefe de ojeadores", "ojeo", 16],
	["ojeador_norte", "Ojeador zona norte", "ojeo", 7],
	["ojeador_sur", "Ojeador zona sur", "ojeo", 7],
	["ojeador_internacional_1", "Ojeador internacional", "ojeo", 9],
	["ojeador_internacional_2", "Ojeador internacional", "ojeo", 9],
	["ojeador_juveniles", "Ojeador juveniles", "ojeo", 6],
	# Médico
	["medico_jefe", "Jefe servicios médicos", "medico", 18],
	["fisio_1", "Fisioterapeuta", "medico", 7],
	["fisio_2", "Fisioterapeuta", "medico", 7],
	["fisio_3", "Fisioterapeuta", "medico", 7],
	["nutricionista", "Nutricionista", "medico", 6],
	["psicologo", "Psicólogo deportivo", "medico", 7],
	# Cantera
	["director_cantera", "Director de cantera", "cantera", 16],
	["coach_cantera_1", "Entrenador filial", "cantera", 8],
	["coach_cantera_2", "Entrenador juvenil A", "cantera", 6],
	["coach_cantera_3", "Entrenador juvenil B", "cantera", 5],
]

const TEMPLATE_MEDIANO := [
	["director_deportivo", "Director deportivo", "direccion", 16],
	["director_financiero", "Director financiero", "direccion", 12],
	["staff_comunicacion", "Jefe prensa", "direccion", 6],
	["segundo_entrenador", "Segundo entrenador", "tecnico", 12],
	["preparador_fisico_jefe", "Jefe preparación física", "tecnico", 10],
	["entrenador_porteros", "Entrenador de porteros", "tecnico", 7],
	["analista_video", "Analista de vídeo", "tecnico", 5],
	["jefe_ojeadores", "Jefe de ojeadores", "ojeo", 10],
	["ojeador_1", "Ojeador", "ojeo", 5],
	["ojeador_2", "Ojeador", "ojeo", 5],
	["medico_jefe", "Jefe servicios médicos", "medico", 11],
	["fisio_1", "Fisioterapeuta", "medico", 5],
	["fisio_2", "Fisioterapeuta", "medico", 5],
	["director_cantera", "Director de cantera", "cantera", 10],
	["coach_cantera", "Entrenador cantera", "cantera", 5],
]

const TEMPLATE_PEQUENO := [
	["segundo_entrenador", "Segundo entrenador", "tecnico", 7],
	["preparador_fisico", "Preparador físico", "tecnico", 5],
	["entrenador_porteros", "Entrenador porteros", "tecnico", 4],
	["ojeador", "Ojeador", "ojeo", 4],
	["fisio", "Fisioterapeuta", "medico", 4],
	["coach_cantera", "Entrenador cantera", "cantera", 4],
	["staff_admin", "Staff administrativo", "direccion", 4],
]


static func size_for(team: Team) -> String:
	var capacity: int = team.stadium.capacity if team.stadium else 0
	if team.reputation >= 85 and capacity >= 50_000:
		return "grande"
	if team.reputation >= 70 and capacity >= 25_000:
		return "mediano"
	return "pequeno"


# Calidad inicial recomendada según tamaño del club:
#   grande:   3-5 (jefes 4, asistentes 3, ojeadores 4)
#   mediano:  2-4 (jefes 3, resto 3)
#   pequeno:  1-3 (todos 2)
static func _initial_quality(template_size: String, role: String) -> int:
	var is_chief: bool = role.contains("jefe") or role.contains("director")
	match template_size:
		"grande":
			return 4 if is_chief else 3
		"mediano":
			return 3 if is_chief else 3
		_:
			return 2


static func generate(team: Team, current_year: int) -> Organigrama:
	var size: String = size_for(team)
	var template: Array
	match size:
		"grande": template = TEMPLATE_GRANDE
		"mediano": template = TEMPLATE_MEDIANO
		_: template = TEMPLATE_PEQUENO

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(team.id) ^ current_year

	var org := Organigrama.new()
	for i in template.size():
		var entry: Array = template[i]
		var role: String = String(entry[0])
		var label: String = String(entry[1])
		var section: String = String(entry[2])
		var salary_factor: int = int(entry[3])
		var quality: int = _initial_quality(size, role)
		var name_data: Dictionary = NamePool.generate(rng)
		var emp := Employee.new()
		emp.id = "%s_emp_%03d" % [team.id, i + 1]
		emp.name = String(name_data["name"])
		emp.role = role
		emp.role_label = label
		emp.section = section
		emp.quality = quality
		# Salario: factor × calidad² × 100K
		emp.salary_eur_year = salary_factor * quality * quality * 10_000
		emp.since_year = current_year
		org.employees.append(emp)
	return org


# Sincroniza StaffInfo con el organigrama: extrae las calidades de los jefes
# de cada sección para los 4 roles clave de StaffInfo (compatibilidad).
static func sync_staff_info(team: Team) -> void:
	if team.organigrama == null or team.staff == null:
		return
	# fitness_coach: jefe preparación física o preparador físico (pequeño)
	# scout_chief: jefe de ojeadores
	# youth_coach: director de cantera
	# physio: jefe servicios médicos o fisio jefe
	team.staff.fitness_coach = _max_quality_in_section(team.organigrama, "tecnico", ["fitness", "fisico"])
	team.staff.scout_chief = _max_quality_in_section(team.organigrama, "ojeo", ["jefe", "ojeador"])
	team.staff.youth_coach = _max_quality_in_section(team.organigrama, "cantera", ["director", "coach"])
	team.staff.physio = _max_quality_in_section(team.organigrama, "medico", ["medico", "fisio"])


static func _max_quality_in_section(org: Organigrama, section: String, role_keywords: Array) -> int:
	var best: int = 1
	for e: Employee in org.by_section(section):
		var matches_keyword: bool = false
		for kw in role_keywords:
			if e.role.contains(String(kw)):
				matches_keyword = true
				break
		if matches_keyword and e.quality > best:
			best = e.quality
	return best
