extends SceneTree

func _init() -> void:
	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		quit(1)
		return
	# Tomar 3 equipos representativos: Barça (grande), Real Sociedad (mediano), Mirandés (pequeño)
	for tid in ["fc_barcelona", "real_sociedad", "cd_mirandes", "real_madrid", "athletic_club"]:
		var t: Team = null
		for tt: Team in loaded.teams.values():
			if tt.id == tid:
				t = tt
				break
		if t == null: continue
		var size: String = OrganigramaFactory.size_for(t)
		var org: Organigrama = OrganigramaFactory.generate(t, 2026)
		print("[%s] %s — tamaño %s — %d empleados (%d entradas) — %s €/año" % [
			tid, t.name, size,
			org.total_headcount(),
			org.employees.size(),
			str(org.total_salary()),
		])
		# Por sección
		for sec in ["direccion", "tecnico", "ojeo", "medico", "cantera", "mantenimiento", "estadio"]:
			var sec_emps: Array = org.by_section(sec)
			var sec_head: int = 0
			for e in sec_emps: sec_head += e.count
			print("  %-15s : %d empleados" % [sec, sec_head])
	quit(0)
