class_name BasqueHeuristic extends RefCounted

# Heurística para detectar si un nombre es típicamente vasco / euskaldun.
#
# El criterio de Athletic Club para fichar (signing_policy = basque_only) es
# básicamente "vasco-formado" — incluye jugadores nacidos en País Vasco /
# Navarra y formados en cantera de la zona. No tenemos un campo de origen ni
# club formador, así que aproximamos por apellido + nombre.
#
# Los apellidos vascos son distintivos (terminan en -ena, -aga, -aldea, -ondo,
# -mendi, -etxe, -arte, etc.) y tienen prefijos / componentes característicos
# (etx, txu, txi, eus, gar, urru, ola, gor, men, izp).
#
# Esto se usa para:
#   - data_loader: marca basque_eligible al cargar JSONs.
#   - NamePool: detecta si un nombre generado podría ser vasco para sesgar
#     canteranos del Athletic.
#   - transfer_market: Athletic solo puede fichar players con basque_eligible=true.

# Apellidos / componentes inequívocamente vascos (insensitive sin acentos).
const BASQUE_TOKENS := [
	# Apellidos vascos comunes que aparecen en La Liga
	"agirre", "aguirre", "aitana", "aizpuru", "alegria", "alkorta", "andueza",
	"arana", "aramburu", "aranzabal", "aranzubia", "areitio", "areso",
	"arratibel", "arrasate", "arregui", "arrieta", "arrizabalaga",
	"artazcoz", "arteta", "artola", "astiazaran", "atxa", "aurtenetxe",
	"azkarate", "azkonobieta", "azpilicueta", "azpiroz",
	"badiola", "baena", "balda", "baleriola", "balenziaga", "barreneche",
	"barrenetxea", "basozabal", "beitia", "belaustegui", "bengoetxea",
	"berchiche", "berenguer", "berrueta", "bilbao", "biurrun", "boiro",
	"calleja", "cardenas", "celarain", "cembranos", "cendoya",
	"chiquidemor", "cigaran", "cuello", "cumbre",
	"echeverria", "etxebarria", "etxeberria", "egia", "egiluz",
	"egiraun", "eguren", "elizalde", "elorza", "elustondo", "endika",
	"eneko", "erviti", "etura", "etxebarria", "etxegoien", "etxeita",
	"galarreta", "garagarza", "garcia de la torre", "garikoitz",
	"garin", "garmendia", "garralaga", "gomez de segura", "gorka",
	"goiz", "gorosabel", "gorostiza", "guruzeta",
	"hierro", "imanol", "iparragirre", "iraola", "iribas", "iribar",
	"iturraspe", "iturriaga", "iturricha", "izaguirre",
	"jaureguizar", "jauregizar", "joseba", "juaristi",
	"kortajarena", "lakabeg", "lacasa", "lapetra", "laporte", "larrazabal",
	"larrinaga", "lekue", "leon", "lizarralde", "llorente",
	"madariaga", "mardones", "mendia", "merino", "mendiluce", "mendizabal",
	"miramon", "monreal", "muniain", "muñoz",
	"navascues", "nuñez",
	"ochotorena", "olabarria", "olaeta", "olano", "olarra", "olarte",
	"olazabal", "ondarra", "onarteix", "ondo", "orbaiz", "ormaetxea",
	"oroz", "orozco", "ortuzar", "otaegui", "otamendi", "oyarzabal",
	"padilla", "padron", "pampliega", "paredes", "pena", "pino",
	"prados",
	"raposo", "regula", "remiro",
	"sagarna", "sancet", "sannadi", "sarabia", "sarriegi",
	"sololuze", "sololuze", "sorondo", "soriano",
	"telleria", "tinto",
	"unai", "unzue", "urreaga", "urrutia", "urzaiz", "inaki",
	"valverde", "vesga", "vicandi", "villalibre", "vivian",
	"yeray", "yarza", "ynsa", "yuri",
	"zabaleta", "zaldua", "zarate", "zarautz", "zubeldia", "zubikarai",
	"zubizarreta", "zumeta",
]

# Sufijos/componentes que casi siempre indican apellido vasco
const BASQUE_SUFFIXES := ["txebarria", "etxeberri", "endia", "izaga",
		"goitia", "gorri", "mendi", "tegui", "ondo", "iaga", "aldea"]


static func is_basque_name(full_name: String) -> bool:
	"""Devuelve true si el nombre completo (nombre + apellidos) tiene
	componentes típicamente vascos."""
	var norm: String = _normalize(full_name)
	# 1) Token directo
	for token in BASQUE_TOKENS:
		if token in norm:
			return true
	# 2) Sufijos
	for suf in BASQUE_SUFFIXES:
		if norm.ends_with(suf) or (suf + " ") in norm:
			return true
	# 3) Combinación: comienza con apellido típico
	if norm.begins_with("etxe") or norm.contains(" etxe") or norm.contains(" txu"):
		return true
	return false


static func _normalize(s: String) -> String:
	# Lowercase + quita acentos comunes
	var out: String = s.to_lower()
	out = out.replace("á", "a").replace("é", "e").replace("í", "i")
	out = out.replace("ó", "o").replace("ú", "u").replace("ñ", "n")
	out = out.replace("à", "a").replace("è", "e").replace("ì", "i")
	return out
