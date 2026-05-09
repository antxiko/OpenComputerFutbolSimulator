class_name TransferMarket extends RefCounted

# Mercado de fichajes v1.
# Cada equipo evalúa sus posiciones débiles, busca un fichaje que mejore claramente
# su mejor opción actual y hace una oferta a valor de mercado. El equipo vendedor
# acepta o rechaza según importancia del jugador, contrato, etc.
#
# Limitaciones v1:
#   - No regateo: precio = market_value (sin negociación).
#   - Sin agentes libres / fin de contrato.
#   - Sin cesiones.
#   - Athletic no ficha (no tenemos datos de elegibilidad vasca de jugadores rivales).
#   - Sin reemplazos automáticos (si un equipo vende, no compra después uno nuevo).


const MAX_SIGNINGS_PER_TEAM: int = 3
const MAX_DEPARTURES_PER_TEAM: int = 4
const SLOTS_TO_EVALUATE: Array[String] = ["GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LW", "RW", "ST"]

# Configuración de la ventana de mercado.
# Verano: 4 rondas, 3 fichajes max, presupuesto completo.
# Invierno: 2 rondas, 1 fichaje max, presupuesto reducido al 30%.
class WindowConfig:
	var rounds: int = 4
	var max_signings: int = 3
	var max_departures: int = 4
	var budget_factor: float = 1.0
	var label: String = "verano"


static func summer_window() -> WindowConfig:
	var w := WindowConfig.new()
	return w


static func winter_window() -> WindowConfig:
	var w := WindowConfig.new()
	w.rounds = 2
	w.max_signings = 1
	w.max_departures = 2
	w.budget_factor = 0.30
	w.label = "invierno"
	return w


class Transfer:
	var player_id: String
	var player_name: String
	var from_team_id: String
	var from_team_name: String
	var to_team_id: String
	var to_team_name: String
	var fee_eur: int
	var slot: String
	var overall: int
	var age: int


class MarketResult:
	var year: int = 0
	var transfers: Array = []  # Array[Transfer]
	var team_summary: Dictionary = {}  # team_id -> { signings_count, departures_count, spend, income, net }
	# Movimiento de contratos vencidos:
	#   renewals: Array[{ player_name, team_name, new_until_year }]
	#   released: Array[{ player_name, team_name, age, ovr }]
	#   free_agent_signings: Array[{ player_name, signing_team_name, prev_team_name, salary }]
	var renewals: Array = []
	var released: Array = []
	var free_agent_signings: Array = []
	# Cesiones: prestamos temporales 1 año
	#   loans_out: Array[{ player_name, origin_team_name, dest_team_name, until_year }]
	#   loan_returns: Array[{ player_name, origin_team_name, prev_loan_team_name }]
	var loans_out: Array = []
	var loan_returns: Array = []


static func run(teams: Array, season_year: int, seed_value: int, window: WindowConfig = null) -> MarketResult:
	if window == null:
		window = summer_window()

	var result := MarketResult.new()
	result.year = season_year

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Inicializar resumen por equipo y presupuestos working
	var budgets: Dictionary = {}  # team_id -> int (presupuesto disponible)
	var counts_in: Dictionary = {}
	var counts_out: Dictionary = {}
	# Jugadores ya transferidos en esta ventana — no se pueden re-vender
	var transferred_this_window: Dictionary = {}
	# Bonus de fichaje al vender titular: si un equipo pierde un core, gana
	# un slot extra de fichaje (replacement). Se rellena en _apply_transfer.
	var extra_signings_allowed: Dictionary = {}
	for t: Team in teams:
		# El budget disponible es min(budget_transfers configurado, cash_balance real)
		# multiplicado por el factor de la ventana (verano 1.0, invierno 0.30).
		var base_budget: int = t.finances.budget_transfers_eur if t.finances != null else 0
		var cash: int = t.finances.cash_balance if t.finances != null else 0
		var effective: int = mini(base_budget, maxi(0, cash))
		budgets[t.id] = int(float(effective) * window.budget_factor)
		counts_in[t.id] = 0
		counts_out[t.id] = 0
		extra_signings_allowed[t.id] = 0
		result.team_summary[t.id] = {
			"name": t.name,
			"signings_count": 0,
			"departures_count": 0,
			"spend": 0,
			"income": 0,
			"net": 0,
		}

	# Procesar cesiones que terminan: jugadores cuyo loan_until_year <= season_year
	# vuelven a su club de origen.
	if window.label == "verano":
		_process_loan_returns(teams, season_year, result)

	# Procesar contratos vencidos antes de las rondas (solo en verano).
	# En invierno los contratos no se procesan — eso es exclusivo del verano.
	var free_agents: Array = []
	if window.label == "verano":
		free_agents = _process_expired_contracts(teams, season_year, result, rng)

	# Calcular media por slot en la liga (para detectar debilidad relativa)
	var league_avg: Dictionary = _compute_league_average_by_slot(teams)

	# Orden de equipos: shuffle determinista + bias por reputación (los grandes mueven primero)
	# Pre-computamos un score estable por equipo para evitar comparator no-determinista.
	var team_scores: Dictionary = {}
	for t in teams:
		team_scores[t.id] = float(t.reputation) + rng.randf_range(-5.0, 5.0)
	var team_order: Array = teams.duplicate()
	team_order.sort_custom(func(a: Team, b: Team) -> bool:
		return float(team_scores[a.id]) > float(team_scores[b.id]))

	# Hacemos varias pasadas: en cada pasada cada equipo intenta UN fichaje
	# (mezclamos free agents y transferencias normales). Eso simula que el
	# mercado se mueve en oleadas.
	for round_idx in window.rounds:
		for buyer: Team in team_order:
			if counts_in[buyer.id] >= window.max_signings + int(extra_signings_allowed[buyer.id]):
				continue
			# Antes de intentar un fichaje pagado, intenta firmar un free agent
			# si el equipo tiene un slot débil que un agente libre cubre.
			# Esto es preferente al fichaje normal (es gratis).
			if free_agents.size() > 0:
				var fa_signing := _attempt_free_agent_signing(buyer, free_agents, league_avg, season_year, result)
				if fa_signing:
					counts_in[buyer.id] += 1
					continue
			# Athletic (basque_only) puede fichar pero solo jugadores basque_eligible.
			# El filtrado lo aplica _find_best_candidate; aquí no hacemos continue.
			if budgets[buyer.id] < 500_000:
				continue
			var transfer := _attempt_signing(buyer, teams, league_avg, budgets, counts_in, counts_out, transferred_this_window, season_year, rng, window)
			if transfer != null:
				result.transfers.append(transfer)
				_apply_transfer(transfer, teams, budgets, counts_in, counts_out, result, extra_signings_allowed)
				transferred_this_window[transfer.player_id] = true

	# Cesiones: pasada extra al final solo en verano. Equipos grandes con
	# canterabos excedentes los ceden a equipos pequeños para que tengan
	# minutos.
	if window.label == "verano":
		var lenders: Array = teams.duplicate()
		lenders.sort_custom(func(a: Team, b: Team) -> bool:
			return a.reputation > b.reputation)
		for lender: Team in lenders:
			if lender.reputation < 75:
				break  # solo equipos de cierta entidad ceden
			# Cada equipo grande puede ceder hasta 2 canteranos
			for k in 2:
				if not _attempt_loan_offering(lender, teams, league_avg, season_year, result, rng):
					break

	# Free agents que no fichó nadie — se desvinculan del simulador
	# (representa que se retiran o se van a otra liga). Quedan registrados
	# en result.released pero ya no aparecen en ningún team.
	# (Ya están fuera de teams porque _process_expired_contracts los sacó.)

	return result


# ----------------------------------------------------------------------
# Contratos vencidos: renovación automática o release
# ----------------------------------------------------------------------
static func _process_expired_contracts(teams: Array, season_year: int, result: MarketResult, rng: RandomNumberGenerator) -> Array:
	var free_agents: Array = []  # Array[{player, prev_team}]
	for t: Team in teams:
		var to_release: Array[Player] = []
		for p: Player in t.players:
			if p.contract == null:
				continue
			if p.contract.until_year > season_year:
				continue  # contrato vigente
			# Contrato expirado: decidir renovar vs liberar.
			var ovr: int = PlayerFactory.compute_overall(p, p.primary_position())
			var age: int = p.age_at(season_year, 7, 1)
			var renew_prob: float = 0.55
			# Estrellas: el club siempre intenta retener
			if p.tier in ["S", "A"]: renew_prob += 0.25
			elif p.tier == "B": renew_prob += 0.10
			# Edad alta: menos prob de renovar
			if age >= 33: renew_prob -= 0.30
			elif age >= 30: renew_prob -= 0.10
			# Overall bajo: menos prob de renovar
			if ovr < 65: renew_prob -= 0.20
			renew_prob = clampf(renew_prob, 0.05, 0.95)

			if rng.randf() < renew_prob:
				# Renueva: extiende 2-3 años, ajusta salario al alza si es estrella
				var extra_years: int = 3 if p.tier in ["S", "A"] else 2
				p.contract.until_year = season_year + extra_years
				if p.tier in ["S", "A"]:
					p.contract.salary_eur_year = int(p.contract.salary_eur_year * 1.15)
				result.renewals.append({
					"player_name": p.name,
					"team_name": t.short_name,
					"new_until_year": p.contract.until_year,
				})
			else:
				# Liberar: se va al pool de free agents
				to_release.append(p)
				result.released.append({
					"player_name": p.name,
					"team_name": t.short_name,
					"age": age,
					"ovr": ovr,
					"tier": p.tier,
				})
		# Aplicar releases (sacarlos del team)
		for p in to_release:
			t.players.erase(p)
			free_agents.append({ "player": p, "prev_team": t })
	return free_agents


# Intenta firmar un free agent. Si encuentra uno apto, lo añade al equipo y lo
# elimina del pool. Devuelve true si fichó.
static func _attempt_free_agent_signing(buyer: Team, free_agents: Array, league_avg: Dictionary, season_year: int, result: MarketResult) -> bool:
	# 1) ¿Qué slot tiene débil el comprador?
	var weak_slots: Array = _weakest_slots(buyer, league_avg, 3)
	if weak_slots.is_empty():
		return false

	# 2) Buscar el mejor free agent que cubra alguno de esos slots
	for slot_data: Dictionary in weak_slots:
		var slot: String = slot_data["slot"]
		var current_best_ovr: int = slot_data["best_overall"]
		var min_target: int = current_best_ovr + 1  # un free agent puede ser solo marginalmente mejor

		var best_idx: int = -1
		var best_ovr: int = 0
		for i in free_agents.size():
			var fa: Dictionary = free_agents[i]
			var p: Player = fa["player"]
			var prev_team: Team = fa["prev_team"]
			if not (slot in p.positions):
				continue
			# No fichar a tu propio jugador recién liberado (raro pero posible
			# si su contrato venció y no le renovaste — implicaría cambio
			# de mente extraño).
			if prev_team.id == buyer.id:
				continue
			# Filtrar por política
			if buyer.signing_policy == "basque_only" and not p.basque_eligible:
				continue
			var ovr: int = PlayerFactory.compute_overall(p, slot)
			if ovr < min_target:
				continue
			if ovr > best_ovr:
				best_ovr = ovr
				best_idx = i
		if best_idx < 0:
			continue

		# 3) Fichar al free agent: añadir a buyer, sacar del pool, nuevo contrato
		var fa: Dictionary = free_agents[best_idx]
		var p: Player = fa["player"]
		var prev_team: Team = fa["prev_team"]
		# Nuevo contrato: 3 años, salario reajustado a su MarketValue / 6 (heurística para libre)
		var new_salary: int = max(150_000, int(MarketValue.compute(p, season_year, slot) / 6))
		p.contract.until_year = season_year + 3
		p.contract.salary_eur_year = new_salary
		p.joined_year = season_year
		buyer.players.append(p)
		free_agents.remove_at(best_idx)
		result.free_agent_signings.append({
			"player_name": p.name,
			"signing_team_id": buyer.id,
			"signing_team_name": buyer.short_name,
			"prev_team_name": prev_team.short_name,
			"salary": new_salary,
			"slot": slot,
			"overall": best_ovr,
		})
		return true
	return false


# Intenta una operación: el comprador escoge su slot más débil, busca un mejor jugador en otro equipo.
static func _attempt_signing(
	buyer: Team,
	all_teams: Array,
	league_avg: Dictionary,
	budgets: Dictionary,
	counts_in: Dictionary,
	counts_out: Dictionary,
	transferred_this_window: Dictionary,
	season_year: int,
	rng: RandomNumberGenerator,
	window: WindowConfig = null
) -> Transfer:
	# 1) Encontrar el slot más débil del comprador
	var weak_slots: Array = _weakest_slots(buyer, league_avg, 3)
	if weak_slots.is_empty():
		return null

	# 2) Por cada slot débil, buscar candidato y hacer oferta
	for slot_data: Dictionary in weak_slots:
		var slot: String = slot_data["slot"]
		var current_best_ovr: int = slot_data["best_overall"]
		var candidate_data: Dictionary = _find_best_candidate(buyer, slot, current_best_ovr, all_teams, counts_out, budgets, transferred_this_window, season_year, rng)
		if candidate_data.is_empty():
			continue

		var candidate: Player = candidate_data["player"]
		var seller: Team = candidate_data["seller"]
		var fee: int = candidate_data["fee"]
		# En invierno los clubes no quieren soltar a sus titulares en mid-season:
		# añade penalización al probability de aceptar.
		if window != null and window.label == "invierno":
			# Aumenta la lealtad efectiva: el vendedor es más reticente.
			# Lo hacemos pidiendo +30% sobre el fee acordado (el comprador paga premium o falla).
			fee = int(float(fee) * 1.30)
			if fee > budgets[buyer.id]:
				continue

		# 3) Probabilidad de venta
		var accept_prob: float = _seller_acceptance_prob(candidate, seller, fee, season_year, buyer)
		if window != null and window.label == "invierno":
			accept_prob -= 0.20  # mid-season los clubes se aferran a sus jugadores
		if rng.randf() > accept_prob:
			continue

		# Crear el Transfer record
		var t := Transfer.new()
		t.player_id = candidate.id
		t.player_name = candidate.name
		t.from_team_id = seller.id
		t.from_team_name = seller.short_name
		t.to_team_id = buyer.id
		t.to_team_name = buyer.short_name
		t.fee_eur = fee
		t.slot = slot
		t.overall = PlayerFactory.compute_overall(candidate, slot)
		t.age = candidate.age_at(season_year, 7, 1)
		return t

	return null


# Aplica el fichaje a las estructuras: mueve player entre teams, actualiza presupuestos.
static func _apply_transfer(
	transfer: Transfer,
	all_teams: Array,
	budgets: Dictionary,
	counts_in: Dictionary,
	counts_out: Dictionary,
	result: MarketResult,
	extra_signings_allowed: Dictionary = {}
) -> void:
	var buyer: Team = _find_team_by_id(all_teams, transfer.to_team_id)
	var seller: Team = _find_team_by_id(all_teams, transfer.from_team_id)
	if buyer == null or seller == null:
		return
	var player: Player = seller.find_player(transfer.player_id)
	if player == null:
		return
	# Mueve el jugador
	seller.players.erase(player)
	buyer.players.append(player)
	player.joined_year = result.year
	# Actualiza presupuestos
	budgets[buyer.id] -= transfer.fee_eur
	budgets[seller.id] += transfer.fee_eur
	# También aplicar al cash_balance real para coherencia
	if buyer.finances != null:
		buyer.finances.cash_balance -= transfer.fee_eur
	if seller.finances != null:
		seller.finances.cash_balance += transfer.fee_eur
	counts_in[buyer.id] += 1
	counts_out[seller.id] += 1
	# Si el vendedor pierde un titular core (overall ≥75 o sin alternativas),
	# gana 1 slot extra de fichaje para reemplazarlo en rondas posteriores.
	if extra_signings_allowed.has(seller.id) and player.primary_position() != "":
		var primary: String = player.primary_position()
		var ovr: int = PlayerFactory.compute_overall(player, primary)
		var alts: int = 0
		for p2: Player in seller.players:
			if primary in p2.positions and PlayerFactory.compute_overall(p2, primary) >= 70:
				alts += 1
		if ovr >= 75 or alts < 2:
			extra_signings_allowed[seller.id] = int(extra_signings_allowed[seller.id]) + 1
	# Actualiza summary
	result.team_summary[buyer.id]["signings_count"] += 1
	result.team_summary[buyer.id]["spend"] += transfer.fee_eur
	result.team_summary[buyer.id]["net"] -= transfer.fee_eur
	result.team_summary[seller.id]["departures_count"] += 1
	result.team_summary[seller.id]["income"] += transfer.fee_eur
	result.team_summary[seller.id]["net"] += transfer.fee_eur


# ============================================================================
# Detección de debilidades
# ============================================================================
static func _compute_league_average_by_slot(teams: Array) -> Dictionary:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for slot in SLOTS_TO_EVALUATE:
		sums[slot] = 0
		counts[slot] = 0
	for t: Team in teams:
		for p: Player in t.players:
			for slot in SLOTS_TO_EVALUATE:
				if slot in p.positions:
					var ovr: int = PlayerFactory.compute_overall(p, slot)
					sums[slot] += ovr
					counts[slot] += 1
	var avg: Dictionary = {}
	for slot in SLOTS_TO_EVALUATE:
		avg[slot] = float(sums[slot]) / float(maxi(counts[slot], 1))
	return avg


# Devuelve los `n` slots más débiles del equipo, comparados con la media de la liga.
# Cada elemento: { slot, best_overall, league_avg, gap }
static func _weakest_slots(team: Team, league_avg: Dictionary, n: int) -> Array:
	var rows: Array = []
	for slot in SLOTS_TO_EVALUATE:
		var best_ovr: int = _best_overall_in_slot(team, slot)
		var avg: float = league_avg[slot]
		var gap: float = avg - float(best_ovr)
		rows.append({ "slot": slot, "best_overall": best_ovr, "league_avg": avg, "gap": gap })
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["gap"] > b["gap"])
	return rows.slice(0, n)


static func _best_overall_in_slot(team: Team, slot: String) -> int:
	var best: int = 0
	for p: Player in team.players:
		if not (slot in p.positions):
			continue
		var ovr: int = PlayerFactory.compute_overall(p, slot)
		if ovr > best:
			best = ovr
	return best


# ============================================================================
# Búsqueda de candidato y oferta
# ============================================================================
static func _find_best_candidate(
	buyer: Team,
	slot: String,
	current_best_ovr: int,
	all_teams: Array,
	counts_out: Dictionary,
	budgets: Dictionary,
	transferred_this_window: Dictionary,
	season_year: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var min_target_ovr: int = current_best_ovr + 3  # tiene que ser mejorable
	var candidates: Array = []
	for seller: Team in all_teams:
		if seller.id == buyer.id:
			continue
		if counts_out[seller.id] >= MAX_DEPARTURES_PER_TEAM:
			continue
		for p: Player in seller.players:
			if transferred_this_window.has(p.id):
				continue  # ya cambió de equipo este verano, no se re-vende
			if not (slot in p.positions):
				continue
			# Excluir lesionados / muy jóvenes irrelevantes
			if p.tier == "Y" and p.age_at(season_year, 7, 1) < 18:
				continue
			# Filtrar por política de fichajes del comprador
			if buyer.signing_policy == "basque_only" and not p.basque_eligible:
				continue
			var ovr: int = PlayerFactory.compute_overall(p, slot)
			if ovr < min_target_ovr:
				continue
			var value: int = MarketValue.compute(p, season_year, slot)
			if value > budgets[buyer.id]:
				continue
			# Ruido para que no sea siempre el mismo top
			var fit: float = float(ovr) + rng.randf_range(-2.0, 2.0)
			candidates.append({ "player": p, "seller": seller, "fee": value, "ovr": ovr, "fit": fit })
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["fit"]) > float(b["fit"]))
	return candidates[0]


# ============================================================================
# Aceptación del vendedor
# ============================================================================
static func _seller_acceptance_prob(player: Player, seller: Team, fee: int, season_year: int, buyer: Team = null) -> float:
	# Base: 50%
	var p: float = 0.50

	# Atractivo del comprador: si la reputación del comprador es claramente
	# mayor que la del vendedor, el jugador "quiere irse" → la prob sube. Si
	# es menor, baja (ningún jugador top quiere bajar a un equipo peor).
	if buyer != null:
		var rep_diff: int = buyer.reputation - seller.reputation
		# +0.20 si rep_diff = +20 (gran upgrade), -0.15 si rep_diff = -15
		p += clampf(float(rep_diff) * 0.012, -0.20, 0.30)

	# Lealtad: jugador recién incorporado (últimos 2 años) muy difícil de vender
	var seasons_at_club: int = season_year - player.joined_year
	if seasons_at_club < 1:
		p -= 0.45  # llegó este verano, casi imposible que se vaya
	elif seasons_at_club < 3:
		p -= 0.25

	# Importancia del jugador para el equipo: si es top-2 en su slot, baja
	var is_core: bool = false
	for slot in player.positions:
		var ranks: Array = _player_overall_ranks_in_team(seller, slot)
		var idx: int = ranks.find(player.id)
		if idx >= 0 and idx < 2:
			is_core = true
			break
	if is_core:
		p -= 0.30

	# Estrella: overall general alto = el club no quiere venderlo
	var ovr_general: int = PlayerFactory.compute_overall(player, "")
	if ovr_general >= 85:
		p -= 0.35
	elif ovr_general >= 80:
		p -= 0.18
	elif ovr_general >= 75:
		p -= 0.05

	# Contrato: 0 años → vende fácil; muchos años → vende mal
	var years_left: int = 0
	if player.contract != null:
		years_left = maxi(0, player.contract.until_year - season_year)
	if years_left <= 1:
		p += 0.30
	elif years_left >= 4:
		p -= 0.10

	# Edad: 30+ → vende fácil; jóvenes retienen
	var age: int = player.age_at(season_year, 7, 1)
	if age >= 32:
		p += 0.20
	elif age <= 22:
		p -= 0.10

	# Cláusula activada: venta forzada
	if player.contract != null and player.contract.release_clause_eur > 0:
		if fee >= player.contract.release_clause_eur:
			p = 1.0

	return clampf(p, 0.03, 1.0)


static func _player_overall_ranks_in_team(team: Team, slot: String) -> Array:
	var rows: Array = []
	for p: Player in team.players:
		if not (slot in p.positions):
			continue
		rows.append({ "id": p.id, "ovr": PlayerFactory.compute_overall(p, slot) })
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["ovr"]) > int(b["ovr"]))
	return rows.map(func(r: Dictionary) -> String: return String(r["id"]))


# ============================================================================
# Cesiones (loans)
# ============================================================================
# Devuelve los jugadores cedidos cuyo loan terminó al club de origen.
static func _process_loan_returns(teams: Array, season_year: int, result: MarketResult) -> void:
	var team_idx: Dictionary = {}
	for t: Team in teams:
		team_idx[t.id] = t
	for t: Team in teams:
		var to_remove: Array[Player] = []
		for p: Player in t.players:
			if p.loan_origin_team_id == "":
				continue
			if p.loan_until_year > season_year:
				continue  # cesión sigue vigente
			# La cesión terminó: vuelve al club de origen
			var origin: Team = team_idx.get(p.loan_origin_team_id, null)
			if origin == null:
				# Si el club de origen ha desaparecido, el jugador se queda
				p.loan_origin_team_id = ""
				p.loan_until_year = 0
				continue
			to_remove.append(p)
			origin.players.append(p)
			result.loan_returns.append({
				"player_name": p.name,
				"origin_team_name": origin.short_name,
				"prev_loan_team_name": t.short_name,
			})
			# Limpiar marca de cesión
			p.loan_origin_team_id = ""
			p.loan_until_year = 0
		for p in to_remove:
			t.players.erase(p)


# Intenta ceder un canterano del comprador a un equipo más débil que necesite
# cubrir slot.
# Llamado durante las rondas como alternativa a fichaje pagado/free agent.
# Returns true si hizo una cesión.
static func _attempt_loan_offering(seller: Team, all_teams: Array, league_avg: Dictionary, season_year: int, result: MarketResult, rng: RandomNumberGenerator) -> bool:
	# Solo equipos con plantilla amplia ceden (no quitarse cantera necesaria)
	if seller.players.size() < 22:
		return false
	# Buscar canteranos cedibles (tier Y, < 22 años, no titulares)
	var candidates: Array[Player] = []
	for p: Player in seller.players:
		if p.tier != "Y":
			continue
		if p.loan_origin_team_id != "":
			continue  # ya cedido (no puede cederse otra vez)
		var age: int = p.age_at(season_year, 7, 1)
		if age >= 22:
			continue
		candidates.append(p)
	if candidates.is_empty():
		return false
	candidates.shuffle()  # determinista por rng del shuffler interno
	# Buscar destino: equipo de menor reputación con un slot débil
	var dest_candidates: Array = all_teams.duplicate()
	dest_candidates.sort_custom(func(a: Team, b: Team) -> bool:
		return a.reputation < b.reputation)
	for cantereano: Player in candidates:
		var primary: String = cantereano.primary_position()
		if primary == "":
			continue
		for dest: Team in dest_candidates:
			if dest.id == seller.id:
				continue
			if dest.reputation >= seller.reputation:
				continue  # solo cesiones a clubes inferiores
			if dest.players.size() >= 26:
				continue  # plantilla llena
			# ¿El destino tiene este slot débil?
			var weak_slots: Array = _weakest_slots(dest, league_avg, 5)
			var slot_match: bool = false
			for s: Dictionary in weak_slots:
				if String(s["slot"]) == primary:
					slot_match = true
					break
			if not slot_match:
				continue
			# 30% prob (no todas las opciones se concretan)
			if rng.randf() > 0.30:
				continue
			# Hacer la cesión
			seller.players.erase(cantereano)
			cantereano.loan_origin_team_id = seller.id
			cantereano.loan_until_year = season_year + 1
			dest.players.append(cantereano)
			result.loans_out.append({
				"player_name": cantereano.name,
				"origin_team_name": seller.short_name,
				"dest_team_name": dest.short_name,
				"until_year": season_year + 1,
				"slot": primary,
			})
			return true
	return false


static func _find_team_by_id(teams: Array, team_id: String) -> Team:
	for t: Team in teams:
		if t.id == team_id:
			return t
	return null


# ============================================================================
# Helpers de impresión
# ============================================================================
static func print_top_transfers(result: MarketResult, n: int = 15) -> void:
	var sorted: Array = result.transfers.duplicate()
	sorted.sort_custom(func(a: Transfer, b: Transfer) -> bool:
		return a.fee_eur > b.fee_eur)
	print("\n  Top %d fichajes (verano %d):" % [n, result.year])
	print("    Pos  Jugador                          Edad   Pos  Ovr   De   →   A    Coste")
	print("    ───  ───────────────────────────────  ────   ───  ───  ───  ─   ───  ─────────")
	for i in mini(n, sorted.size()):
		var t: Transfer = sorted[i]
		print("    %3d  %-31s  %3d   %-3s   %2d   %-3s  →   %-3s  %s" % [
			i + 1, t.player_name.left(31), t.age, t.slot, t.overall,
			t.from_team_name, t.to_team_name, _fmt_eur(t.fee_eur)
		])


static func print_team_summary(result: MarketResult, teams: Array) -> void:
	print("\n  Resumen por equipo:")
	print("    Equipo                         Altas   Bajas   Gasto         Ingresos      Neto")
	print("    ──────────────────────────────  ─────   ─────   ───────────   ───────────   ──────────")
	# Ordenar por mayor gasto
	var sorted: Array = teams.duplicate()
	sorted.sort_custom(func(a: Team, b: Team) -> bool:
		return int(result.team_summary[a.id]["spend"]) > int(result.team_summary[b.id]["spend"]))
	for t: Team in sorted:
		var s: Dictionary = result.team_summary[t.id]
		if s["signings_count"] == 0 and s["departures_count"] == 0:
			continue
		print("    %-30s   %3d     %3d     %12s  %12s  %s" % [
			t.name.left(30),
			int(s["signings_count"]),
			int(s["departures_count"]),
			_fmt_eur(int(s["spend"])),
			_fmt_eur(int(s["income"])),
			_fmt_eur_signed(int(s["net"])),
		])


static func _fmt_eur(amount: int) -> String:
	if amount >= 1_000_000:
		return "%6.1fM €" % (amount / 1_000_000.0)
	elif amount >= 1_000:
		return "%6.0fk €" % (amount / 1_000.0)
	return "%d €" % amount


static func _fmt_eur_signed(amount: int) -> String:
	if amount >= 0:
		return "+" + _fmt_eur(amount)
	return "-" + _fmt_eur(-amount)
