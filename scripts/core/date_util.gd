class_name DateUtil extends RefCounted

# Utilidades de calendario gregoriano.
# Las fechas se representan como Dictionary { "year": int, "month": int, "day": int }.
# Los días de semana son 0=lunes, 1=martes, ..., 6=domingo.

const DOW_LU := 0
const DOW_MA := 1
const DOW_MI := 2
const DOW_JU := 3
const DOW_VI := 4
const DOW_SA := 5
const DOW_DO := 6

const MONTH_NAMES := ["enero", "febrero", "marzo", "abril", "mayo", "junio",
		"julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
const DOW_NAMES := ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
const DOW_NAMES_SHORT := ["Lu", "Ma", "Mi", "Ju", "Vi", "Sá", "Do"]


static func is_leap(year: int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


static func days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12: return 31
		4, 6, 9, 11: return 30
		2: return 29 if is_leap(year) else 28
		_: return 30


# Día de la semana (Zeller's congruence adaptada). 0=lunes, 6=domingo.
static func day_of_week(year: int, month: int, day: int) -> int:
	# Zeller: Q = day, m = month (con ajuste enero/febrero), K = year%100, J = year/100
	var m: int = month
	var Y: int = year
	if m < 3:
		m += 12
		Y -= 1
	var K: int = Y % 100
	var J: int = int(Y / 100)
	# h: 0=sábado, 1=domingo, 2=lunes, ..., 6=viernes
	var h: int = (day + int((13 * (m + 1)) / 5) + K + int(K / 4) + int(J / 4) + 5 * J) % 7
	# Convertir a 0=lunes, 6=domingo
	# h=0(sab), 1(dom), 2(lun), 3(mar), 4(mié), 5(jue), 6(vie)
	# → mapping: sab→5, dom→6, lun→0, mar→1, mié→2, jue→3, vie→4
	var map := [5, 6, 0, 1, 2, 3, 4]
	return map[h]


# Suma days al date dado y devuelve nueva fecha.
static func add_days(date: Dictionary, days: int) -> Dictionary:
	var y: int = int(date.get("year", 2026))
	var m: int = int(date.get("month", 1))
	var d: int = int(date.get("day", 1))
	d += days
	while d > days_in_month(y, m):
		d -= days_in_month(y, m)
		m += 1
		if m > 12:
			m = 1
			y += 1
	while d < 1:
		m -= 1
		if m < 1:
			m = 12
			y -= 1
		d += days_in_month(y, m)
	return { "year": y, "month": m, "day": d }


# Diferencia en días (b - a).
static func diff_days(a: Dictionary, b: Dictionary) -> int:
	# Approximation por día absoluto desde year 0 (no se usa fechas extremas)
	return _absolute_day(b) - _absolute_day(a)


static func _absolute_day(date: Dictionary) -> int:
	var y: int = int(date.get("year", 2026))
	var m: int = int(date.get("month", 1))
	var d: int = int(date.get("day", 1))
	# Días desde año 0 (aproximación: 365.25 × año + days antes mes + day)
	var total: int = y * 365 + int(y / 4) - int(y / 100) + int(y / 400)
	for mm in range(1, m):
		total += days_in_month(y, mm)
	return total + d


# Encuentra el siguiente día de la semana ≥ date dado.
# target_dow es 0=lunes, 6=domingo.
static func next_dow(date: Dictionary, target_dow: int) -> Dictionary:
	var current_dow: int = day_of_week(int(date["year"]), int(date["month"]), int(date["day"]))
	var diff: int = (target_dow - current_dow + 7) % 7
	return add_days(date, diff)


# Formato corto: "Sá 23/08" (día_semana abrev + dd/mm).
static func format_short(date: Dictionary) -> String:
	var dow: int = day_of_week(int(date["year"]), int(date["month"]), int(date["day"]))
	return "%s %02d/%02d" % [DOW_NAMES_SHORT[dow], int(date["day"]), int(date["month"])]


# Formato largo: "sábado 23 de agosto de 2026"
static func format_long(date: Dictionary) -> String:
	var dow: int = day_of_week(int(date["year"]), int(date["month"]), int(date["day"]))
	return "%s %d de %s de %d" % [
		DOW_NAMES[dow], int(date["day"]),
		MONTH_NAMES[int(date["month"]) - 1], int(date["year"])
	]


# Crea fecha
static func make(year: int, month: int, day: int) -> Dictionary:
	return { "year": year, "month": month, "day": day }


# Compara dos fechas: -1 si a<b, 0 si igual, 1 si a>b
static func compare(a: Dictionary, b: Dictionary) -> int:
	var ay: int = int(a.get("year", 0))
	var by: int = int(b.get("year", 0))
	if ay != by: return -1 if ay < by else 1
	var am: int = int(a.get("month", 0))
	var bm: int = int(b.get("month", 0))
	if am != bm: return -1 if am < bm else 1
	var ad: int = int(a.get("day", 0))
	var bd: int = int(b.get("day", 0))
	if ad != bd: return -1 if ad < bd else 1
	return 0
