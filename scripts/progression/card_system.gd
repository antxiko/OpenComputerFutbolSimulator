class_name CardSystem extends RefCounted

# Sanciones por tarjetas a lo largo de la temporada.
#
# Reglas v1 (símil La Liga):
#   - Cada 5 amarillas acumuladas en la temporada → 1 partido sancionado.
#   - Roja directa → 1 partido sancionado (acumulable a las amarillas).
#   - Suspensiones se cumplen en el siguiente partido oficial del equipo
#     (Liga o Copa, lo que toque antes).
#   - Reset de amarillas al inicio de cada temporada. Las sanciones pendientes
#     SE ARRASTRAN de una temporada a otra (un sancionado a final de junio
#     cumple en la siguiente jornada que dispute).

const YELLOWS_PER_SUSPENSION: int = 5


# Procesa los eventos de tarjetas tras simular un partido.
# Devuelve los jugadores que han ENTRADO en sanción tras este partido.
static func process_match(result: MatchResult, all_teams: Array) -> Array:
	var newly_suspended: Array = []
	for ev: MatchEvent in result.events:
		if ev.player_id == "":
			continue
		var p: Player = _find_player(all_teams, ev.player_id)
		if p == null:
			continue
		if ev.type == MatchEvent.T_YELLOW:
			p.yellow_cards_season += 1
			if p.yellow_cards_season % YELLOWS_PER_SUSPENSION == 0:
				p.suspended_matches += 1
				newly_suspended.append(p)
		elif ev.type == MatchEvent.T_RED:
			p.suspended_matches += 1
			newly_suspended.append(p)
	return newly_suspended


# Decrementar la sanción de los jugadores de un equipo que está a punto
# de jugar un partido. Llamar ANTES de _simulate_match.
static func decrement_for_team(team: Team) -> void:
	for p: Player in team.players:
		if p.suspended_matches > 0:
			p.suspended_matches -= 1


# Reset de amarillas (NO de sanciones pendientes, esas se arrastran)
# al inicio de una nueva temporada.
static func reset_yellow_cards(all_teams: Array) -> void:
	for t: Team in all_teams:
		for p: Player in t.players:
			p.yellow_cards_season = 0


static func is_suspended(p: Player) -> bool:
	return p.suspended_matches > 0


static func _find_player(all_teams: Array, player_id: String) -> Player:
	for t: Team in all_teams:
		for p: Player in t.players:
			if p.id == player_id:
				return p
	return null
