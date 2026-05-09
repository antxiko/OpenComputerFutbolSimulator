class_name StaffInfo extends Resource

# Cuerpo técnico del club. 4 roles con calidad 1-5.
# - fitness_coach: ↓ pérdida de condition durante partido + ↑ recuperación entre jornadas.
# - scout_chief: ↑ tier_band de canteranos generados.
# - youth_coach: ↑ atributos de jugadores tier Y al envejecer.
# - physio: ↓ duración de lesiones.

@export var fitness_coach: int = 2
@export var scout_chief: int = 2
@export var youth_coach: int = 2
@export var physio: int = 2


static func from_dict(d: Dictionary) -> StaffInfo:
	var s := StaffInfo.new()
	s.fitness_coach = int(d.get("fitness_coach", 2))
	s.scout_chief = int(d.get("scout_chief", 2))
	s.youth_coach = int(d.get("youth_coach", 2))
	s.physio = int(d.get("physio", 2))
	return s


# Salario anual de cada miembro: 200K base × calidad²
# (calidad 1=200K, 2=800K, 3=1.8M, 4=3.2M, 5=5M)
static func salary_for_quality(q: int) -> int:
	return 200_000 * q * q


# Coste para subir un nivel (q a q+1): 5x salario nuevo - salario actual
static func upgrade_cost(current_q: int) -> int:
	if current_q >= 5:
		return 0
	var new_q: int = current_q + 1
	return salary_for_quality(new_q) * 4


func total_salary() -> int:
	return salary_for_quality(fitness_coach) + salary_for_quality(scout_chief) \
		+ salary_for_quality(youth_coach) + salary_for_quality(physio)


# Multiplicadores derivados — usados por sistemas externos
func fitness_recovery_factor() -> float:
	# 0.85 (q=1) → 1.30 (q=5)
	return 0.85 + 0.10 * float(fitness_coach - 1)

func scout_potential_bonus() -> float:
	return 0.05 * float(scout_chief - 2)  # q=2 neutro, q=5 → +15%

func youth_dev_factor() -> float:
	return 1.0 + 0.05 * float(youth_coach - 2)

func injury_duration_factor() -> float:
	# q=1 lesiones duran 1.20x; q=5 → 0.65x
	return 1.20 - 0.135 * float(physio - 1)
