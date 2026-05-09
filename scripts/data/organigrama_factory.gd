class_name OrganigramaFactory extends RefCounted

# Genera la plantilla de empleados de un club según su tamaño.
# Plantillas escalonadas con representación realista del organigrama:
#   - GRANDE   (rep ≥85 + cap ≥50k):   ~95 empleados, ~12-15M€/año
#   - MEDIANO  (rep 70-84 + cap 25k+): ~50 empleados, ~5M€/año
#   - PEQUEÑO  (rep <70 o cap <25k):   ~22 empleados, ~1.5M€/año
#
# Cada entrada del template es:
#   [role_id, role_label, section, base_salary_factor, count]
# count > 1 genera "count" empleados con role_id_NN para distinguirlos.
# Salario individual = base_salary_factor × quality² × 10_000.

# Secciones: direccion / tecnico / ojeo / medico / cantera / mantenimiento / estadio

# Cada entrada: [role_id, role_label, section, base_salary_factor, count, individual_names]
# - count: número de personas con este rol
# - individual_names: si true, cada uno tiene Employee individual con nombre.
#   Si false, un solo Employee representa a todos (acomodadores ×80, etc.).
const TEMPLATE_GRANDE := [
	# ── DIRECCIÓN (~25) — todos con nombre individual ──
	["presidente", "Presidente", "direccion", 40, 1, true],
	["vicepresidente", "Vicepresidente", "direccion", 28, 2, true],
	["director_general", "Director general", "direccion", 30, 1, true],
	["director_deportivo", "Director deportivo", "direccion", 25, 1, true],
	["director_financiero", "Director financiero", "direccion", 18, 1, true],
	["director_comunicacion", "Director de comunicación", "direccion", 14, 1, true],
	["director_marketing", "Director de marketing", "direccion", 14, 1, true],
	["director_legal", "Director departamento legal", "direccion", 14, 1, true],
	["director_rrhh", "Director de RRHH", "direccion", 12, 1, true],
	["director_internacional", "Director relaciones internacionales", "direccion", 12, 1, true],
	["secretario_tecnico", "Secretario técnico", "direccion", 9, 1, true],
	["jefe_prensa", "Jefe de prensa", "direccion", 8, 1, true],
	["staff_prensa", "Oficiales de prensa", "direccion", 4, 4, false],
	["community_manager", "Community managers", "direccion", 4, 3, false],
	["staff_marketing", "Staff de marketing", "direccion", 4, 6, false],
	["staff_legal", "Abogados", "direccion", 6, 3, false],
	["asistente_direccion", "Asistentes de dirección", "direccion", 4, 4, false],
	# ── CUERPO TÉCNICO (~16) ──
	["segundo_entrenador", "Segundo entrenador", "tecnico", 18, 1, true],
	["preparador_fisico_jefe", "Jefe preparación física", "tecnico", 14, 1, true],
	["preparador_fisico", "Preparadores físicos", "tecnico", 7, 4, false],
	["entrenador_porteros", "Entrenador de porteros", "tecnico", 10, 1, true],
	["entrenador_individual", "Entrenadores individualizados", "tecnico", 6, 3, false],
	["analista_video_jefe", "Jefe análisis vídeo", "tecnico", 9, 1, true],
	["analista_video", "Analistas de vídeo", "tecnico", 6, 3, false],
	["analista_set_pieces", "Analista de balón parado", "tecnico", 7, 1, true],
	["delegado_equipo", "Delegado del equipo", "tecnico", 5, 1, true],
	# ── OJEO (~20) ──
	["jefe_ojeadores", "Jefe de ojeadores", "ojeo", 16, 1, true],
	["ojeador_internacional", "Ojeadores internacionales", "ojeo", 9, 8, false],
	["ojeador_nacional", "Ojeadores nacionales", "ojeo", 6, 6, false],
	["ojeador_juveniles", "Ojeadores juveniles", "ojeo", 6, 5, false],
	# ── MÉDICO (~22) ──
	["medico_jefe", "Jefe servicios médicos", "medico", 18, 1, true],
	["medico_equipo", "Médicos del primer equipo", "medico", 10, 3, false],
	["fisio_jefe", "Jefe fisioterapeutas", "medico", 9, 1, true],
	["fisio", "Fisioterapeutas", "medico", 6, 8, false],
	["readaptador", "Readaptadores físicos", "medico", 7, 2, false],
	["nutricionista", "Nutricionistas", "medico", 6, 2, false],
	["psicologo", "Psicólogos deportivos", "medico", 7, 2, false],
	["osteopata", "Osteópatas", "medico", 6, 2, false],
	["enfermero", "Enfermeros", "medico", 4, 2, false],
	# ── CANTERA (~30) ──
	["director_cantera", "Director de cantera", "cantera", 16, 1, true],
	["coordinador_cantera", "Coordinador deportivo cantera", "cantera", 10, 1, true],
	["coach_filial", "Entrenadores filial", "cantera", 9, 3, false],
	["coach_juvenil_a", "Entrenador juvenil A", "cantera", 7, 1, true],
	["coach_juvenil_b", "Entrenador juvenil B", "cantera", 6, 1, true],
	["coach_juvenil_c", "Entrenador juvenil C", "cantera", 5, 1, true],
	["coach_cadete_a", "Entrenador cadete A", "cantera", 5, 1, true],
	["coach_cadete_b", "Entrenador cadete B", "cantera", 5, 1, true],
	["coach_infantil_a", "Entrenador infantil A", "cantera", 4, 1, true],
	["coach_infantil_b", "Entrenador infantil B", "cantera", 4, 1, true],
	["coach_alevin", "Entrenadores alevín", "cantera", 4, 2, false],
	["coach_benjamin", "Entrenadores benjamín", "cantera", 4, 2, false],
	["psicologo_cantera", "Psicólogos de cantera", "cantera", 5, 2, false],
	["medico_cantera", "Médicos de cantera", "cantera", 6, 2, false],
	["fisio_cantera", "Fisios de cantera", "cantera", 4, 4, false],
	["preparador_fisico_cantera", "Preparadores físicos cantera", "cantera", 4, 3, false],
	["staff_residencia", "Staff residencia jugadores", "cantera", 3, 4, false],
	# ── MANTENIMIENTO + INSTALACIONES (~150) ──
	["jefe_mantenimiento", "Jefe de mantenimiento", "mantenimiento", 8, 1, true],
	["jefe_jardineria", "Jefe de jardinería", "mantenimiento", 6, 1, true],
	["jardinero_campo_principal", "Jardineros campo principal", "mantenimiento", 4, 12, false],
	["jardinero_campos_entreno", "Jardineros campos entrenamiento", "mantenimiento", 3, 30, false],
	["tecnico_riego", "Técnicos de riego", "mantenimiento", 4, 4, false],
	["electricista", "Electricistas", "mantenimiento", 4, 8, false],
	["fontanero", "Fontaneros", "mantenimiento", 4, 4, false],
	["pintor", "Pintores", "mantenimiento", 3, 4, false],
	["albañil", "Albañiles", "mantenimiento", 3, 4, false],
	["lavanderia", "Personal lavandería", "mantenimiento", 3, 10, false],
	["utillero", "Utilleros", "mantenimiento", 3, 8, false],
	["mecanico", "Mecánicos", "mantenimiento", 4, 4, false],
	["personal_limpieza", "Personal de limpieza", "mantenimiento", 2, 50, false],
	["choferes", "Chóferes", "mantenimiento", 3, 8, false],
	["recepcion", "Personal recepción", "mantenimiento", 3, 8, false],
	# ── ESTADIO + EVENTOS (~600 — gran masa de personal a tiempo parcial) ──
	["jefe_seguridad", "Jefe de seguridad", "estadio", 9, 1, true],
	["seguridad", "Personal de seguridad", "estadio", 3, 80, false],
	["coordinador_eventos", "Coordinador de eventos", "estadio", 7, 1, true],
	["jefe_taquillas", "Jefe de taquillas", "estadio", 5, 1, true],
	["taquillero", "Taquilleros", "estadio", 3, 20, false],
	["jefe_acomodadores", "Jefe de acomodadores", "estadio", 4, 1, true],
	["acomodador", "Acomodadores", "estadio", 2, 280, false],
	["responsable_tienda", "Responsable de tienda oficial", "estadio", 5, 1, true],
	["dependiente_tienda", "Dependientes tienda oficial", "estadio", 2, 30, false],
	["responsable_restauracion", "Responsable restauración", "estadio", 4, 1, true],
	["personal_restauracion", "Personal restauración estadio", "estadio", 2, 90, false],
	["personal_museo", "Personal del museo", "estadio", 3, 25, false],
	["guia_visitas", "Guías de visitas", "estadio", 3, 12, false],
	["personal_limpieza_estadio", "Limpieza días de partido", "estadio", 2, 60, false],
	["staff_atencion_socio", "Atención al socio", "estadio", 3, 15, false],
]

# MEDIANO ~165 empleados (Sevilla, Athletic, Real Sociedad)
const TEMPLATE_MEDIANO := [
	# Dirección (~12)
	["presidente", "Presidente", "direccion", 22, 1, true],
	["director_general", "Director general", "direccion", 18, 1, true],
	["director_deportivo", "Director deportivo", "direccion", 16, 1, true],
	["director_financiero", "Director financiero", "direccion", 12, 1, true],
	["director_comunicacion", "Director comunicación", "direccion", 10, 1, true],
	["jefe_marketing", "Jefe marketing", "direccion", 8, 1, true],
	["jefe_prensa", "Jefe prensa", "direccion", 6, 1, true],
	["staff_prensa", "Oficiales de prensa", "direccion", 3, 2, false],
	["staff_marketing", "Staff marketing", "direccion", 3, 2, false],
	["staff_legal", "Staff legal", "direccion", 5, 1, true],
	["asistente_direccion", "Asistentes dirección", "direccion", 3, 2, false],
	# Técnico (~12)
	["segundo_entrenador", "Segundo entrenador", "tecnico", 12, 1, true],
	["preparador_fisico_jefe", "Jefe preparación física", "tecnico", 10, 1, true],
	["preparador_fisico", "Preparadores físicos", "tecnico", 5, 2, false],
	["entrenador_porteros", "Entrenador porteros", "tecnico", 7, 1, true],
	["entrenador_individual", "Entrenadores individuales", "tecnico", 4, 2, false],
	["analista_video_jefe", "Jefe análisis vídeo", "tecnico", 6, 1, true],
	["analista_video", "Analistas vídeo", "tecnico", 4, 2, false],
	["analista_set_pieces", "Analista balón parado", "tecnico", 5, 1, true],
	["delegado_equipo", "Delegado equipo", "tecnico", 4, 1, true],
	# Ojeo (~10)
	["jefe_ojeadores", "Jefe de ojeadores", "ojeo", 10, 1, true],
	["ojeador_internacional", "Ojeadores internacionales", "ojeo", 6, 3, false],
	["ojeador_nacional", "Ojeadores nacionales", "ojeo", 4, 4, false],
	["ojeador_juveniles", "Ojeadores juveniles", "ojeo", 4, 2, false],
	# Médico (~12)
	["medico_jefe", "Jefe servicios médicos", "medico", 11, 1, true],
	["medico_equipo", "Médicos equipo", "medico", 7, 2, false],
	["fisio", "Fisioterapeutas", "medico", 5, 5, false],
	["readaptador", "Readaptador físico", "medico", 5, 1, true],
	["nutricionista", "Nutricionista", "medico", 4, 1, true],
	["psicologo", "Psicólogo", "medico", 4, 1, true],
	["enfermero", "Enfermero", "medico", 3, 1, true],
	# Cantera (~16)
	["director_cantera", "Director de cantera", "cantera", 10, 1, true],
	["coach_filial", "Entrenador filial", "cantera", 7, 1, true],
	["coach_juvenil", "Entrenadores juveniles", "cantera", 5, 3, false],
	["coach_cadete", "Entrenadores cadete", "cantera", 4, 2, false],
	["coach_infantil", "Entrenadores infantil", "cantera", 3, 2, false],
	["coach_alevin", "Entrenadores alevín", "cantera", 3, 2, false],
	["fisio_cantera", "Fisios cantera", "cantera", 3, 2, false],
	["medico_cantera", "Médico cantera", "cantera", 4, 1, true],
	["psicologo_cantera", "Psicólogo cantera", "cantera", 3, 1, true],
	# Mantenimiento (~80)
	["jefe_mantenimiento", "Jefe mantenimiento", "mantenimiento", 6, 1, true],
	["jardinero_principal", "Jardineros campo principal", "mantenimiento", 3, 8, false],
	["jardinero_entreno", "Jardineros campos entreno", "mantenimiento", 3, 16, false],
	["electricista", "Electricistas", "mantenimiento", 3, 4, false],
	["fontanero", "Fontanero", "mantenimiento", 3, 2, false],
	["pintor", "Pintor", "mantenimiento", 3, 2, false],
	["lavanderia", "Personal lavandería", "mantenimiento", 2, 6, false],
	["utillero", "Utilleros", "mantenimiento", 3, 5, false],
	["mecanico", "Mecánico", "mantenimiento", 3, 2, false],
	["personal_limpieza", "Personal limpieza", "mantenimiento", 2, 25, false],
	["choferes", "Chóferes", "mantenimiento", 3, 4, false],
	["recepcion", "Personal recepción", "mantenimiento", 3, 5, false],
	# Estadio (~330)
	["jefe_seguridad", "Jefe seguridad", "estadio", 6, 1, true],
	["seguridad", "Personal seguridad", "estadio", 2, 50, false],
	["coordinador_eventos", "Coordinador eventos", "estadio", 5, 1, true],
	["jefe_taquillas", "Jefe taquillas", "estadio", 4, 1, true],
	["taquillero", "Taquilleros", "estadio", 2, 12, false],
	["jefe_acomodadores", "Jefe acomodadores", "estadio", 3, 1, true],
	["acomodador", "Acomodadores", "estadio", 2, 150, false],
	["responsable_tienda", "Responsable tienda", "estadio", 4, 1, true],
	["dependiente_tienda", "Dependientes tienda", "estadio", 2, 18, false],
	["personal_restauracion", "Personal restauración", "estadio", 2, 50, false],
	["personal_museo", "Personal museo", "estadio", 3, 12, false],
	["personal_limpieza_estadio", "Limpieza días partido", "estadio", 2, 30, false],
	["staff_atencion_socio", "Atención al socio", "estadio", 3, 8, false],
]


# PEQUEÑO ~200 empleados (Elche, Mirandés, Eldense)
const TEMPLATE_PEQUENO := [
	# Dirección (~7)
	["presidente", "Presidente", "direccion", 12, 1, true],
	["director_general", "Director general", "direccion", 10, 1, true],
	["director_deportivo", "Director deportivo", "direccion", 9, 1, true],
	["director_financiero", "Director financiero", "direccion", 7, 1, true],
	["jefe_prensa", "Jefe prensa", "direccion", 5, 1, true],
	["asistente_direccion", "Asistentes dirección", "direccion", 3, 2, false],
	# Técnico (~8)
	["segundo_entrenador", "Segundo entrenador", "tecnico", 7, 1, true],
	["preparador_fisico", "Preparadores físicos", "tecnico", 4, 2, false],
	["entrenador_porteros", "Entrenador porteros", "tecnico", 4, 1, true],
	["analista_video", "Analista vídeo", "tecnico", 3, 1, true],
	["analista_set_pieces", "Analista balón parado", "tecnico", 3, 1, true],
	["delegado_equipo", "Delegado equipo", "tecnico", 3, 1, true],
	["entrenador_individual", "Entrenador individualizado", "tecnico", 3, 1, true],
	# Ojeo (~5)
	["jefe_ojeadores", "Jefe de ojeadores", "ojeo", 6, 1, true],
	["ojeador", "Ojeadores", "ojeo", 4, 3, false],
	["ojeador_juveniles", "Ojeador juveniles", "ojeo", 3, 1, true],
	# Médico (~7)
	["medico_jefe", "Jefe servicios médicos", "medico", 6, 1, true],
	["medico_equipo", "Médico equipo", "medico", 4, 1, true],
	["fisio", "Fisioterapeutas", "medico", 3, 3, false],
	["nutricionista", "Nutricionista", "medico", 3, 1, true],
	["psicologo", "Psicólogo", "medico", 3, 1, true],
	# Cantera (~10)
	["director_cantera", "Coordinador cantera", "cantera", 5, 1, true],
	["coach_filial", "Entrenador filial", "cantera", 4, 1, true],
	["coach_juvenil", "Entrenadores juveniles", "cantera", 3, 2, false],
	["coach_cadete", "Entrenadores cadete", "cantera", 3, 2, false],
	["coach_infantil", "Entrenadores infantil", "cantera", 2, 2, false],
	["fisio_cantera", "Fisio cantera", "cantera", 2, 1, true],
	["preparador_cantera", "Preparador físico cantera", "cantera", 2, 1, true],
	# Mantenimiento (~35)
	["jefe_mantenimiento", "Jefe mantenimiento", "mantenimiento", 5, 1, true],
	["jardinero", "Jardineros", "mantenimiento", 2, 10, false],
	["electricista", "Electricista", "mantenimiento", 3, 2, false],
	["fontanero", "Fontanero", "mantenimiento", 3, 1, true],
	["lavanderia", "Personal lavandería", "mantenimiento", 2, 3, false],
	["utillero", "Utilleros", "mantenimiento", 2, 3, false],
	["personal_limpieza", "Personal limpieza", "mantenimiento", 2, 12, false],
	["choferes", "Chóferes", "mantenimiento", 2, 2, false],
	# Estadio (~115)
	["jefe_seguridad", "Jefe seguridad", "estadio", 5, 1, true],
	["seguridad", "Personal seguridad", "estadio", 2, 25, false],
	["taquillero", "Taquilleros", "estadio", 2, 6, false],
	["acomodador", "Acomodadores", "estadio", 2, 60, false],
	["responsable_tienda", "Responsable tienda", "estadio", 3, 1, true],
	["dependiente_tienda", "Dependientes tienda", "estadio", 2, 6, false],
	["personal_restauracion", "Personal restauración", "estadio", 2, 12, false],
	["personal_limpieza_estadio", "Limpieza días partido", "estadio", 2, 8, false],
]


static func size_for(team: Team) -> String:
	var capacity: int = team.stadium.capacity if team.stadium else 0
	if team.reputation >= 85 and capacity >= 50_000:
		return "grande"
	if team.reputation >= 70 and capacity >= 25_000:
		return "mediano"
	return "pequeno"


# Calidad inicial recomendada según tamaño del club + nivel del rol.
static func _initial_quality(template_size: String, role: String) -> int:
	var is_chief: bool = role.contains("jefe") or role.contains("director") \
			or role == "presidente" or role == "vicepresidente" \
			or role == "director_general" or role == "secretario_tecnico" \
			or role == "coordinador_cantera"
	match template_size:
		"grande":
			return 4 if is_chief else 3
		"mediano":
			return 3 if is_chief else 2
		_:
			return 2 if is_chief else 2


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
	var emp_idx: int = 0
	for entry in template:
		var role_base: String = String(entry[0])
		var label: String = String(entry[1])
		var section: String = String(entry[2])
		var salary_factor: int = int(entry[3])
		var count: int = int(entry[4])
		# entry[5] = individual_names (true = un Employee por persona, false = uno solo agrupado)
		var individual: bool = bool(entry[5]) if entry.size() > 5 else (count == 1)
		var quality: int = _initial_quality(size, role_base)
		var salary: int = salary_factor * quality * quality * 10_000
		# Roles agrupados de gran cantidad (acomodadores, seguridad, restauración,
		# etc.) son mayoritariamente trabajo de día de partido / tiempo parcial,
		# así que su salario nominal se reduce significativamente.
		if not individual:
			if count >= 30:
				salary = int(salary * 0.20)  # ~días de partido, 16-19 partidos al año
			elif count >= 10:
				salary = int(salary * 0.50)  # medio tiempo
			else:
				salary = int(salary * 0.85)  # tiempo casi completo
		if individual:
			# Un Employee por persona, con nombre propio
			for k in count:
				var role: String = role_base if count == 1 else "%s_%02d" % [role_base, k + 1]
				var name_data: Dictionary = NamePool.generate(rng)
				var emp := Employee.new()
				emp_idx += 1
				emp.id = "%s_emp_%03d" % [team.id, emp_idx]
				emp.name = String(name_data["name"])
				emp.role = role
				emp.role_label = label
				emp.section = section
				emp.quality = quality
				emp.salary_eur_year = salary
				emp.since_year = current_year
				emp.count = 1
				org.employees.append(emp)
		else:
			# Un solo Employee agrupado representando los N
			emp_idx += 1
			var emp := Employee.new()
			emp.id = "%s_emp_%03d" % [team.id, emp_idx]
			emp.name = "Equipo %s" % label.to_lower()
			emp.role = role_base
			emp.role_label = label
			emp.section = section
			emp.quality = quality
			emp.salary_eur_year = salary
			emp.since_year = current_year
			emp.count = count
			org.employees.append(emp)
	return org


# Sincroniza StaffInfo con el organigrama: extrae las calidades de los jefes
# de cada sección para los 4 roles clave (compatibilidad con buffs antiguos).
static func sync_staff_info(team: Team) -> void:
	if team.organigrama == null or team.staff == null:
		return
	team.staff.fitness_coach = _max_quality_in_section(team.organigrama, "tecnico", ["preparador_fisico", "fitness"])
	team.staff.scout_chief = _max_quality_in_section(team.organigrama, "ojeo", ["jefe", "ojeador"])
	team.staff.youth_coach = _max_quality_in_section(team.organigrama, "cantera", ["director", "coordinador", "coach"])
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
