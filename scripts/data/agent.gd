class_name Agent extends Resource

# Agente / representante de jugadores. Una entidad puede tener varios clientes
# (algunos super-agentes llegan a 15-20 jugadores en una misma liga).
#
# Personalidad determina cómo negocia con TODOS sus clientes:
#   - "tough":    pide más años + salario, rechaza ofertas bajas (-0.15 accept_prob)
#   - "flexible": acepta ofertas razonables (+0.10 accept_prob)
#   - "greedy":   pide siempre +15% sobre el salario justo (multiplicador alto)
#   - "balanced": comportamiento estándar
#
# Reputación 1-5★ afecta:
#   - Frecuencia con la que sus clientes reciben ofertas (5★ = mucho más rumor)
#   - Comisión que pide en fichajes (5% del fee si 5★, 2% si 1★)
#
# Si el usuario "ofende" a un agente (rechaza muchas ofertas o cancela un fichaje
# muy avanzado), su `relations[user_team_id]` baja → todos sus clientes pasan a
# ser más caros / difíciles de fichar para el usuario.

@export var id: String = ""
@export var name: String = ""
@export var personality: String = "balanced"  # tough / flexible / greedy / balanced
@export var country: String = "ES"
@export var reputation: int = 3  # 1-5 estrellas
# Lista de player_ids representados por este agente
@export var client_ids: Array[String] = []
# Relaciones con clubes: team_id -> int (-100 furioso, 0 neutro, +100 amistoso)
@export var relations: Dictionary = {}


func add_client(player_id: String) -> void:
	if not client_ids.has(player_id):
		client_ids.append(player_id)


func remove_client(player_id: String) -> void:
	client_ids.erase(player_id)


# Devuelve un modificador a aplicar a accept_prob de ContractNegotiation
# según la personalidad del agente y la relación con el club ofertante.
func accept_prob_modifier(team_id: String = "") -> float:
	var base: float = 0.0
	match personality:
		"tough": base = -0.15
		"flexible": base = 0.10
		"greedy": base = -0.05  # no es tan rígido como tough pero pide más
		_: base = 0.0
	# Relación con el club: cada -25 de relación = -0.05 al modifier
	var rel: int = int(relations.get(team_id, 0))
	if rel < 0:
		base += float(rel) / 500.0  # rel=-50 → -0.10 extra
	elif rel > 0:
		base += float(rel) / 1000.0  # rel=+50 → +0.05
	return clampf(base, -0.40, 0.30)


# Multiplicador del salario "justo" que el agente pide. Greedy pide +15%, tough +8%.
func salary_demand_multiplier() -> float:
	match personality:
		"tough": return 1.08
		"greedy": return 1.15
		"flexible": return 0.97
		_: return 1.00


# Comisión que el agente pide al cerrar un fichaje (% del fee_eur).
func commission_percentage() -> float:
	match reputation:
		5: return 0.05
		4: return 0.04
		3: return 0.03
		2: return 0.025
		_: return 0.02


# Ajusta la relación con un club. Limita rango ±100.
func adjust_relation(team_id: String, delta: int) -> void:
	if team_id == "":
		return
	var current: int = int(relations.get(team_id, 0))
	relations[team_id] = clampi(current + delta, -100, 100)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"personality": personality,
		"country": country,
		"reputation": reputation,
		"client_ids": client_ids.duplicate(),
		"relations": relations.duplicate(),
	}


static func from_dict(d: Dictionary) -> Agent:
	var a := Agent.new()
	a.id = String(d.get("id", ""))
	a.name = String(d.get("name", ""))
	a.personality = String(d.get("personality", "balanced"))
	a.country = String(d.get("country", "ES"))
	a.reputation = int(d.get("reputation", 3))
	var raw_clients: Array = d.get("client_ids", [])
	a.client_ids = []
	for cid in raw_clients:
		a.client_ids.append(String(cid))
	a.relations = d.get("relations", {}).duplicate() if d.get("relations") != null else {}
	return a
