class_name AgentFactory extends RefCounted

# Genera un pool de agentes y los reparte entre los jugadores de la liga.
# Distribución no uniforme:
#   - 5 super-agentes (5★): cogen ~30% de los jugadores top-tier
#   - 15 medianos  (3-4★): cogen ~50% (mid-tier)
#   - 25 pequeños  (1-2★): cogen ~20% (canteranos / reservas)
#
# Algunos nombres son cosméticos basados en agentes reales del fútbol moderno
# (Mendes, Zahavi, Barnett, Raiola, Bahia...) — solo el nombre, sin pretensión
# de modelar los datos reales.

const SUPER_AGENT_NAMES: Array[String] = [
	"Jorge Mendes",
	"Pini Zahavi",
	"Jonathan Barnett",
	"Rafaela Pimenta",  # heredera Raiola
	"Mino Sosa",
]

const MEDIUM_AGENT_NAMES: Array[String] = [
	"Iván de la Peña",
	"Andrea D'Amico",
	"Jonathan Harris",
	"Carlos Bucero",
	"Marcelo Simonian",
	"Federico Pastorello",
	"Volker Struth",
	"Kia Joorabchian",
	"Wanda Nara",
	"Mike Manasseh",
	"Roger Wittmann",
	"Tom Greatrex",
	"Kazuto Iwasaki",
	"Stefan Reuter",
	"Ricardo Calleri",
]

const SMALL_AGENT_FIRST: Array[String] = [
	"Carlos", "Pablo", "Miguel", "Andrés", "David", "Javier", "Luis",
	"Antonio", "Roberto", "Sergio", "Manuel", "Daniel", "Iván", "Rubén",
	"Joaquín", "Vicente", "Ramón", "Tomás", "Adrián",
]
const SMALL_AGENT_LAST: Array[String] = [
	"García", "Fernández", "Martín", "López", "Sánchez", "Pérez",
	"González", "Rodríguez", "Hernández", "Jiménez", "Díaz", "Ruiz",
	"Moreno", "Álvarez", "Romero", "Gutiérrez", "Navarro", "Torres",
]

const PERSONALITIES: Array[String] = ["tough", "flexible", "greedy", "balanced"]


# Genera el pool de agentes y los asigna a los jugadores de las dos divisiones.
# Devuelve la lista de Agent generados (al caller le toca persistir).
static func generate_and_assign(all_teams: Array, seed_value: int = 42) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var agents: Array = []
	var agent_id_counter: int = 1

	# 5 super-agentes (rep 5)
	for i in SUPER_AGENT_NAMES.size():
		var a := Agent.new()
		a.id = "ag_super_%d" % agent_id_counter
		a.name = SUPER_AGENT_NAMES[i]
		a.country = "PT" if i == 0 else "IL" if i == 1 else "GB" if i == 2 else "IT"
		a.personality = _weighted_personality(rng, "super")
		a.reputation = 5
		agents.append(a)
		agent_id_counter += 1

	# 15 medianos (rep 3-4)
	for i in MEDIUM_AGENT_NAMES.size():
		var a := Agent.new()
		a.id = "ag_med_%d" % agent_id_counter
		a.name = MEDIUM_AGENT_NAMES[i]
		a.country = ["ES", "IT", "GB", "DE", "AR", "BR"][i % 6]
		a.personality = _weighted_personality(rng, "medium")
		a.reputation = 4 if i < 8 else 3
		agents.append(a)
		agent_id_counter += 1

	# 25 pequeños (rep 1-2) con nombre random
	for i in 25:
		var a := Agent.new()
		a.id = "ag_small_%d" % agent_id_counter
		var first: String = SMALL_AGENT_FIRST[rng.randi() % SMALL_AGENT_FIRST.size()]
		var last: String = SMALL_AGENT_LAST[rng.randi() % SMALL_AGENT_LAST.size()]
		a.name = "%s %s" % [first, last]
		a.country = "ES"
		a.personality = _weighted_personality(rng, "small")
		a.reputation = 2 if rng.randf() < 0.5 else 1
		agents.append(a)
		agent_id_counter += 1

	# Recoger todos los players + ordenarlos por overall desc (para asignar tops a super)
	var all_players: Array = []
	for t: Team in all_teams:
		for p: Player in t.players:
			all_players.append(p)
	all_players.sort_custom(func(a: Player, b: Player) -> bool:
		return PlayerFactory.compute_overall(a, "") > PlayerFactory.compute_overall(b, ""))

	var n_total: int = all_players.size()
	if n_total == 0:
		return agents

	# Distribución de jugadores entre tipos de agentes:
	#   top 30% -> super-agentes (5 agentes)
	#   middle 50% -> medianos (15 agentes)
	#   bottom 20% -> pequeños (25 agentes)
	var n_top: int = int(n_total * 0.30)
	var n_mid: int = int(n_total * 0.50)
	# El resto al pool pequeño

	# Top → super: cada super coge entre 8 y 25 (randomizado dentro)
	# Hago bias: super 1-2 cogen más (Mendes/Zahavi ~20 cada uno)
	var super_agents: Array = agents.slice(0, 5)
	var super_target: Array = [
		int(n_top * 0.27),  # Mendes ~27% del top
		int(n_top * 0.23),  # Zahavi ~23%
		int(n_top * 0.20),  # Barnett ~20%
		int(n_top * 0.16),
		int(n_top * 0.14),
	]
	var top_idx: int = 0
	for s_idx in super_agents.size():
		var n_for_this: int = super_target[s_idx]
		for _i in n_for_this:
			if top_idx >= n_top:
				break
			var p: Player = all_players[top_idx]
			(super_agents[s_idx] as Agent).add_client(p.id)
			p.agent_id = (super_agents[s_idx] as Agent).id
			top_idx += 1
		if top_idx >= n_top:
			break

	# Middle → medianos: distribución más uniforme con leve bias
	var medium_agents: Array = agents.slice(5, 20)
	var mid_idx: int = top_idx
	var mid_end: int = top_idx + n_mid
	while mid_idx < mid_end and mid_idx < n_total:
		# Cada mediano coge el siguiente jugador, round-robin con bias por reputación
		# Más probable que un agente rep 4 coja > rep 3
		var picked: Agent = null
		var roll: float = rng.randf()
		if roll < 0.65:
			# 65% de las veces, agente rep 4 (primeros 8)
			picked = medium_agents[rng.randi() % 8]
		else:
			picked = medium_agents[8 + (rng.randi() % 7)]
		var p: Player = all_players[mid_idx]
		picked.add_client(p.id)
		p.agent_id = picked.id
		mid_idx += 1

	# Bottom → pequeños
	var small_agents: Array = agents.slice(20, 45)
	var small_idx: int = mid_end
	while small_idx < n_total:
		var picked2: Agent = small_agents[rng.randi() % small_agents.size()]
		var p2: Player = all_players[small_idx]
		picked2.add_client(p2.id)
		p2.agent_id = picked2.id
		small_idx += 1

	return agents


# Ajusta la distribución de personalidades según el "tier" del agente.
# Los super-agentes son más "tough"/"greedy" (negocian duro).
# Los pequeños son más "balanced"/"flexible".
static func _weighted_personality(rng: RandomNumberGenerator, tier: String) -> String:
	var weights: Dictionary
	match tier:
		"super":
			weights = {"tough": 0.40, "greedy": 0.30, "balanced": 0.20, "flexible": 0.10}
		"medium":
			weights = {"tough": 0.25, "greedy": 0.20, "balanced": 0.35, "flexible": 0.20}
		_:  # small
			weights = {"tough": 0.10, "greedy": 0.10, "balanced": 0.45, "flexible": 0.35}
	var total: float = 0.0
	for k in weights:
		total += float(weights[k])
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k in weights:
		acc += float(weights[k])
		if roll <= acc:
			return String(k)
	return "balanced"


# Lookup helper: encuentra un agente por id en una lista
static func find_by_id(agents: Array, agent_id: String) -> Agent:
	for a: Agent in agents:
		if a.id == agent_id:
			return a
	return null


# Lookup helper: encuentra el agente de un jugador
static func find_by_player(agents: Array, player: Player) -> Agent:
	if player.agent_id == "":
		return null
	return find_by_id(agents, player.agent_id)
