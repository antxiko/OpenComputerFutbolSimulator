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
	for t: Team in teams:
		var base_budget: int = t.finances.budget_transfers_eur if t.finances != null else 0
		budgets[t.id] = int(float(base_budget) * window.budget_factor)
		counts_in[t.id] = 0
		counts_out[t.id] = 0
		result.team_summary[t.id] = {
			"name": t.name,
			"signings_count": 0,
			"departures_count": 0,
			"spend": 0,
			"income": 0,
			"net": 0,
		}

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

	# Hacemos varias pasadas: en cada pasada cada equipo intenta UN fichaje.
	# Eso simula que el mercado se mueve en oleadas.
	for round_idx in window.rounds:
		for buyer: Team in team_order:
			if counts_in[buyer.id] >= window.max_signings:
				continue
			# Athletic (basque_only) puede fichar pero solo jugadores basque_eligible.
			# El filtrado lo aplica _find_best_candidate; aquí no hacemos continue.
			if budgets[buyer.id] < 500_000:
				continue
			var transfer := _attempt_signing(buyer, teams, league_avg, budgets, counts_in, counts_out, transferred_this_window, season_year, rng, window)
			if transfer != null:
				result.transfers.append(transfer)
				_apply_transfer(transfer, teams, budgets, counts_in, counts_out, result)
				transferred_this_window[transfer.player_id] = true

	return result


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
	result: MarketResult
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
	counts_in[buyer.id] += 1
	counts_out[seller.id] += 1
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
