class_name Team extends Resource

@export var id: String = ""
@export var name: String = ""
@export var short_name: String = ""
@export var city: String = ""
@export var founded: int = 0
@export var stadium: StadiumInfo = null
@export var colors: Dictionary = { "primary": "#FFFFFF", "secondary": "#000000" }
@export var division: String = "primera"
@export var reputation: int = 50
@export var signing_policy: String = "open"
@export var manager: ManagerInfo = null
@export var tactics_default: Tactics = null
@export var finances: FinancesInfo = null
@export var staff: StaffInfo = null
@export var players: Array[Player] = []


func find_player(player_id: String) -> Player:
	for p in players:
		if p.id == player_id:
			return p
	return null


static func from_dict(d: Dictionary) -> Team:
	var t := Team.new()
	t.id = String(d.get("id", ""))
	t.name = String(d.get("name", ""))
	t.short_name = String(d.get("short_name", ""))
	t.city = String(d.get("city", ""))
	t.founded = int(d.get("founded", 0))
	t.stadium = StadiumInfo.from_dict(d.get("stadium", {}))
	t.colors = d.get("colors", { "primary": "#FFFFFF", "secondary": "#000000" }).duplicate()
	t.division = String(d.get("division", "primera"))
	t.reputation = int(d.get("reputation", 50))
	t.signing_policy = String(d.get("signing_policy", "open"))
	t.manager = ManagerInfo.from_dict(d.get("manager", {}))
	t.tactics_default = Tactics.from_dict(d.get("tactics_default", {}))
	t.finances = FinancesInfo.from_dict(d.get("finances", {}))
	t.staff = StaffInfo.from_dict(d.get("staff", {}))
	t.players = []
	var players_in: Array = d.get("players", [])
	for pd in players_in:
		t.players.append(Player.from_dict(pd))
	return t
