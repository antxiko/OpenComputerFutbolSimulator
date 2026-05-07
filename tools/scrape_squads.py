"""
Scraper de plantillas de La Liga desde Wikipedia (es.wikipedia.org).

USO:
    python tools/scrape_squads.py            # scrapea todos los equipos
    python tools/scrape_squads.py real_madrid  # solo uno (para test)

ENTRADA:
    Hardcoded mapping team_id -> Wikipedia URL al final del fichero.

SALIDA:
    - Sobrescribe data/teams/<division>/<team_id>.json para equipos esqueleto.
    - Para los 7 equipos con datos reales pre-existentes (athletic_club,
      fc_barcelona, atletico_madrid, real_sociedad, villarreal_cf, real_betis,
      sevilla_fc), escribe a data/teams/_scraped/<team_id>.json para revisión
      manual sin destruir el trabajo previo.

NOTAS:
    - Datos: se extraen nombre, dorsal, nacionalidad, posición (genérica),
      edad, contrato y procedencia. Wikipedia NO tiene tiers/ratings, así que:
      - Tier por defecto "C".
      - Diccionario STARS para subir tier de ~30 jugadores obvios.
      - Heurística por dorsal para refinar posición específica
        (DEF + dorsal 2 ->RB, etc.).
    - Cesiones: se incluyen pero marcadas con tier "C" y joined_year reciente.
    - Uso PERSONAL — Wikipedia es CC-BY-SA, atribución implícita.
"""

import json
import re
import sys
import time
import unicodedata
from pathlib import Path

import requests
from bs4 import BeautifulSoup, Tag


# ---------------------------------------------------------------------------
# Configuración de equipos
# ---------------------------------------------------------------------------

# Equipos con datos reales pre-capturados manualmente — no sobrescribir,
# en su lugar generar fichero "_scraped" para comparación.
PROTECTED_TEAMS = {
    "athletic_club",
    "fc_barcelona",
    "atletico_madrid",
    "real_sociedad",
    "villarreal_cf",
    "real_betis",
    "sevilla_fc",
}

# Mapeo team_id -> Wikipedia URL (es.wikipedia.org).
# Algunos equipos pueden tener su plantilla en un artículo separado de "Anexo:Plantilla...".
WIKI_URLS = {
    # Primera (20)
    "real_madrid":      "https://es.wikipedia.org/wiki/Real_Madrid_Club_de_F%C3%BAtbol",
    "fc_barcelona":     "https://es.wikipedia.org/wiki/F%C3%BAtbol_Club_Barcelona",
    "atletico_madrid":  "https://es.wikipedia.org/wiki/Club_Atl%C3%A9tico_de_Madrid",
    "athletic_club":    "https://es.wikipedia.org/wiki/Athletic_Club",
    "real_sociedad":    "https://es.wikipedia.org/wiki/Real_Sociedad_de_F%C3%BAtbol",
    "villarreal_cf":    "https://es.wikipedia.org/wiki/Villarreal_Club_de_F%C3%BAtbol",
    "real_betis":       "https://es.wikipedia.org/wiki/Real_Betis_Balompi%C3%A9",
    "sevilla_fc":       "https://es.wikipedia.org/wiki/Sevilla_F%C3%BAtbol_Club",
    "valencia_cf":      "https://es.wikipedia.org/wiki/Valencia_Club_de_F%C3%BAtbol",
    "girona_fc":        "https://es.wikipedia.org/wiki/Girona_F%C3%BAtbol_Club",
    "ca_osasuna":       "https://es.wikipedia.org/wiki/Club_Atl%C3%A9tico_Osasuna",
    "rayo_vallecano":   "https://es.wikipedia.org/wiki/Rayo_Vallecano_de_Madrid",
    "celta_vigo":       "https://es.wikipedia.org/wiki/Real_Club_Celta_de_Vigo",
    "rcd_mallorca":     "https://es.wikipedia.org/wiki/Real_Club_Deportivo_Mallorca",
    "getafe_cf":        "https://es.wikipedia.org/wiki/Getafe_Club_de_F%C3%BAtbol",
    "deportivo_alaves": "https://es.wikipedia.org/wiki/Deportivo_Alav%C3%A9s",
    "rcd_espanyol":     "https://es.wikipedia.org/wiki/Reial_Club_Deportiu_Espanyol_de_Barcelona",
    "levante_ud":       "https://es.wikipedia.org/wiki/Levante_Uni%C3%B3n_Deportiva",
    "elche_cf":         "https://es.wikipedia.org/wiki/Elche_Club_de_F%C3%BAtbol",
    "real_oviedo":      "https://es.wikipedia.org/wiki/Real_Oviedo",
    # Segunda (22)
    "real_valladolid":  "https://es.wikipedia.org/wiki/Real_Valladolid_Club_de_F%C3%BAtbol",
    "ud_las_palmas":    "https://es.wikipedia.org/wiki/Uni%C3%B3n_Deportiva_Las_Palmas",
    "cd_leganes":       "https://es.wikipedia.org/wiki/Club_Deportivo_Legan%C3%A9s",
    "real_sporting":    "https://es.wikipedia.org/wiki/Real_Sporting_de_Gij%C3%B3n",
    "real_zaragoza":    "https://es.wikipedia.org/wiki/Real_Zaragoza",
    "granada_cf":       "https://es.wikipedia.org/wiki/Granada_Club_de_F%C3%BAtbol",
    "ud_almeria":       "https://es.wikipedia.org/wiki/Uni%C3%B3n_Deportiva_Almer%C3%ADa",
    "sd_eibar":         "https://es.wikipedia.org/wiki/Sociedad_Deportiva_Eibar",
    "burgos_cf":        "https://es.wikipedia.org/wiki/Burgos_Club_de_F%C3%BAtbol",
    "fc_cartagena":     "https://es.wikipedia.org/wiki/F%C3%BAtbol_Club_Cartagena",
    "cadiz_cf":         "https://es.wikipedia.org/wiki/C%C3%A1diz_Club_de_F%C3%BAtbol",
    "cd_tenerife":      "https://es.wikipedia.org/wiki/Club_Deportivo_Tenerife",
    "albacete_balompie":"https://es.wikipedia.org/wiki/Albacete_Balompi%C3%A9",
    "cd_mirandes":      "https://es.wikipedia.org/wiki/Club_Deportivo_Mirand%C3%A9s",
    "cd_castellon":     "https://es.wikipedia.org/wiki/Club_Deportivo_Castell%C3%B3n",
    "cd_eldense":       "https://es.wikipedia.org/wiki/Club_Deportivo_Eldense",
    "malaga_cf":        "https://es.wikipedia.org/wiki/M%C3%A1laga_Club_de_F%C3%BAtbol",
    "sd_huesca":        "https://es.wikipedia.org/wiki/Sociedad_Deportiva_Huesca",
    "cordoba_cf":       "https://es.wikipedia.org/wiki/C%C3%B3rdoba_Club_de_F%C3%BAtbol",
    "racing_santander": "https://es.wikipedia.org/wiki/Real_Racing_Club_de_Santander",
    "ad_ceuta":         "https://es.wikipedia.org/wiki/AD_Ceuta_FC",
    "fc_andorra":       "https://es.wikipedia.org/wiki/F%C3%BAtbol_Club_Andorra",
}


# Estrellas: substring del nombre normalizado -> (tier_actual, tier_potencial).
# Búsqueda case-insensitive sin acentos. Primer match gana.
# Wonderkids ponen tier_actual bajo y tier_potencial alto.
STARS = {
    # S tier (élite mundial)
    "mbappe": ("S", "S"),
    "bellingham": ("S", "S"),
    "vinicius": ("S", "S"), "vini junior": ("S", "S"), "vini j": ("S", "S"),
    "lamine yamal": ("S", "S"),
    "pedri": ("S", "S"),
    "oblak": ("S", "S"),
    "ter stegen": ("S", "S"),
    "courtois": ("S", "S"),
    "griezmann": ("S", "S"),

    # A tier (top La Liga)
    "rodrygo": ("A", "S"),
    "valverde": ("A", "S"), "fede valverde": ("A", "S"),
    "tchouameni": ("A", "S"), "tchouam": ("A", "S"),
    "camavinga": ("A", "S"),
    "rudiger": ("A", "A"),
    "militao": ("A", "S"),
    "mendy": ("A", "A"), "ferland mendy": ("A", "A"),
    "carvajal": ("A", "A"),
    "alexander-arnold": ("A", "S"),
    "huijsen": ("A", "S"),
    "raphinha": ("A", "S"),
    "lewandowski": ("A", "S"),
    "cubarsi": ("A", "S"),
    "araujo": ("A", "S"),
    "kounde": ("A", "A"),
    "balde": ("A", "S"),
    "gavi": ("A", "S"),
    "fermin": ("A", "S"),
    "olmo": ("A", "A"), "dani olmo": ("A", "A"),
    "rashford": ("A", "A"), "marcus rashford": ("A", "A"),
    "frenkie de jong": ("A", "S"),
    "julian alvarez": ("A", "S"),
    "koke": ("A", "A"),
    "le normand": ("A", "A"),
    "de paul": ("A", "A"),
    "marcos llorente": ("A", "A"),
    "gallagher": ("A", "A"), "conor gallagher": ("A", "A"),
    "barrios": ("A", "A"), "pablo barrios": ("A", "A"),
    "nico williams": ("A", "S"),
    "inaki williams": ("A", "A"), "iñaki williams": ("A", "A"),
    "sancet": ("A", "S"), "oihan sancet": ("A", "S"),
    "unai simon": ("A", "A"),
    "laporte": ("A", "A"), "aymeric laporte": ("A", "A"),
    "kubo": ("A", "S"), "takefusa kubo": ("A", "S"),
    "oyarzabal": ("A", "A"), "mikel oyarzabal": ("A", "A"),
    "remiro": ("A", "A"), "alex remiro": ("A", "A"),
    "isco": ("A", "S"),
    "fekir": ("A", "A"), "nabil fekir": ("A", "A"),
    "antony": ("A", "A"),
    "baena": ("A", "S"), "alex baena": ("A", "S"),
    "yeremy pino": ("A", "A"),
    "foyth": ("A", "A"), "juan foyth": ("A", "A"),
    "parejo": ("A", "A"), "dani parejo": ("A", "A"),
    "lukebakio": ("A", "A"), "dodi lukebakio": ("A", "A"),
    "guler": ("A", "S"), "arda guler": ("A", "S"),
    "ceballos": ("A", "A"), "dani ceballos": ("A", "A"),
    "rodri": ("A", "A"),

    # Wonderkids (tier actual bajo, potencial S)
    "mastantuono": ("B", "S"),
    "endrick": ("B", "S"),
    "bernal": ("Y", "S"), "marc bernal": ("Y", "S"),
    "casado": ("B", "A"), "marc casado": ("B", "A"),
    "yamal": ("S", "S"),
    "ansu fati": ("B", "A"),
    "vitor roque": ("B", "A"),
    "abde": ("B", "A"), "ezzalzouli": ("B", "A"),
    "akhomach": ("B", "A"),
    "thierno barry": ("B", "A"),
    "orri oskarsson": ("B", "A"), "oskarsson": ("B", "A"),
    "sucic": ("B", "A"), "luka sucic": ("B", "A"),
    "asencio": ("B", "A"), "raul asencio": ("B", "A"),
    "fort": ("Y", "A"), "hector fort": ("Y", "A"),
    "padilla": ("Y", "B"), "alex padilla": ("Y", "B"),
}


# Mapping de país en español ->ISO 3166 alpha-2 (con extensiones para UK)
COUNTRY_TO_ISO = {
    "españa": "ES", "espana": "ES",
    "francia": "FR", "alemania": "DE", "italia": "IT", "portugal": "PT",
    "inglaterra": "GB-ENG", "escocia": "GB-SCT", "gales": "GB-WLS", "irlanda del norte": "GB-NIR",
    "reino unido": "GB",
    "brasil": "BR", "argentina": "AR", "uruguay": "UY", "chile": "CL", "colombia": "CO",
    "peru": "PE", "ecuador": "EC", "venezuela": "VE", "paraguay": "PY", "bolivia": "BO",
    "mexico": "MX", "estados unidos": "US",
    "marruecos": "MA", "argelia": "DZ", "tunez": "TN", "egipto": "EG",
    "senegal": "SN", "nigeria": "NG", "ghana": "GH", "costa de marfil": "CI",
    "camerun": "CM", "mali": "ML", "republica democratica del congo": "CD",
    "mozambique": "MZ", "guinea": "GN", "guinea-bisau": "GW", "guinea ecuatorial": "GQ",
    "cabo verde": "CV", "sudafrica": "ZA",
    "japon": "JP", "corea del sur": "KR", "china": "CN",
    "noruega": "NO", "suecia": "SE", "dinamarca": "DK", "finlandia": "FI", "islandia": "IS",
    "paises bajos": "NL", "belgica": "BE", "luxemburgo": "LU", "suiza": "CH",
    "austria": "AT", "polonia": "PL", "republica checa": "CZ", "eslovaquia": "SK",
    "eslovenia": "SI", "croacia": "HR", "serbia": "RS", "bosnia y herzegovina": "BA",
    "macedonia del norte": "MK", "montenegro": "ME", "albania": "AL",
    "rumania": "RO", "bulgaria": "BG", "hungria": "HU",
    "ucrania": "UA", "rusia": "RU", "bielorrusia": "BY", "moldavia": "MD",
    "turquia": "TR", "grecia": "GR", "chipre": "CY",
    "armenia": "AM", "georgia": "GE", "azerbaiyan": "AZ", "kazajistan": "KZ",
    "irlanda": "IE",
    "australia": "AU", "nueva zelanda": "NZ",
    "canada": "CA",
    "suriname": "SR",
    "haiti": "HT", "republica dominicana": "DO", "jamaica": "JM",
    "honduras": "HN", "guatemala": "GT", "el salvador": "SV", "costa rica": "CR", "panama": "PA",
    "irak": "IQ", "iran": "IR", "siria": "SY", "libano": "LB", "israel": "IL", "palestina": "PS",
    "arabia saudita": "SA", "emiratos arabes unidos": "AE", "qatar": "QA", "kuwait": "KW",
    "jordania": "JO", "yemen": "YE",
}


# Posiciones específicas por nombre conocido (substring, normalizado).
# Usado como override sobre la categoría genérica de Wikipedia.
SPECIFIC_POSITIONS = {
    # Real Madrid
    "courtois": ["GK"], "lunin": ["GK"],
    "carvajal": ["RB"], "alexander-arnold": ["RB"],
    "rudiger": ["CB"], "militao": ["CB", "RB"], "alaba": ["CB", "LB"],
    "huijsen": ["CB"], "asencio": ["CB"],
    "mendy": ["LB"], "fran garcia": ["LB"], "carreras": ["LB"],
    "tchouameni": ["CDM", "CB"], "camavinga": ["CM", "CDM", "LB"],
    "bellingham": ["CM", "CAM"], "valverde": ["CM", "RM"],
    "guler": ["CAM", "CM"], "ceballos": ["CM", "CAM"],
    "mastantuono": ["CAM", "RW"],
    "vinicius": ["LW"], "rodrygo": ["RW", "LW", "CF"],
    "mbappe": ["ST", "LW"], "endrick": ["ST"],
    "brahim": ["CAM", "RW", "LW"], "gonzalo garcia": ["ST"],
    # FC Barcelona
    "ter stegen": ["GK"], "iñaki peña": ["GK"], "inaki pena": ["GK"], "szczesny": ["GK"],
    "kounde": ["RB", "CB"], "araujo": ["CB"], "cubarsi": ["CB"],
    "christensen": ["CB", "CDM"], "eric garcia": ["CB", "CDM"],
    "balde": ["LB"], "gerard martin": ["LB"], "fort": ["RB"],
    "frenkie de jong": ["CM", "CDM"], "pedri": ["CM", "CAM"],
    "gavi": ["CM"], "casado": ["CDM"], "bernal": ["CDM"],
    "fermin": ["CM", "CAM"], "olmo": ["CAM", "LW"],
    "yamal": ["RW", "LW"], "raphinha": ["LW", "RW"],
    "lewandowski": ["ST"], "ferran torres": ["LW", "ST", "RW"],
    "rashford": ["LW", "ST"], "ansu fati": ["LW"],
    # Atlético
    "oblak": ["GK"], "musso": ["GK"],
    "gimenez": ["CB"], "le normand": ["CB"], "azpilicueta": ["RB", "CB"],
    "molina": ["RB"], "reinildo": ["LB"], "galan": ["LB"],
    "koke": ["CM", "CDM"], "de paul": ["CM"], "barrios": ["CM", "CDM"],
    "marcos llorente": ["CM", "CDM", "RB"], "gallagher": ["CM"],
    "saul": ["CM", "CDM"],
    "griezmann": ["CAM", "ST"], "julian alvarez": ["ST", "CAM"],
    "sorloth": ["ST"], "correa": ["CAM", "RW", "ST"],
    "samuel lino": ["LW"], "riquelme": ["RW", "LW"],
    "giuliano": ["RW"],
    # Athletic
    "unai simon": ["GK"], "agirrezabala": ["GK"],
    "yeray": ["CB"], "vivian": ["CB"], "paredes": ["CB"], "laporte": ["CB"],
    "yuri berchiche": ["LB"], "gorosabel": ["RB"], "lekue": ["RB", "LB"],
    "vesga": ["CDM", "CM"], "ruiz de galarreta": ["CM", "CDM"],
    "prados": ["CM"], "jauregizar": ["CDM", "CM"],
    "sancet": ["CAM", "CM"],
    "nico williams": ["LW", "RW"], "berenguer": ["LW", "RW"],
    "iñaki williams": ["RW", "ST"], "inaki williams": ["RW", "ST"],
    "guruzeta": ["ST"], "sannadi": ["ST"], "villalibre": ["ST"],
}


# Posición desde Wikipedia + nombre conocido -> posición específica.
# Si el nombre está en SPECIFIC_POSITIONS, usa ese mapeo.
# Si no, usa la categoría genérica con multi-posición (más flexible para AutoLineup).
def map_position(name: str, wiki_pos: str, dorsal: int | None) -> list[str]:
    norm = normalize(name)
    for key, poss in SPECIFIC_POSITIONS.items():
        if key in norm:
            return list(poss)
    p = wiki_pos.upper()
    if "POR" in p:
        return ["GK"]
    if "DEF" in p:
        return ["CB", "LB", "RB"]
    if "MED" in p:
        return ["CM", "CDM", "CAM"]
    if "DEL" in p:
        return ["ST", "LW", "RW"]
    return ["CM"]


# ---------------------------------------------------------------------------
# Scraper
# ---------------------------------------------------------------------------

USER_AGENT = "OCFS-personal-use/0.1 (educational)"


def normalize(s: str) -> str:
    """Quita acentos, baja a minúsculas. Para comparar nombres en STARS."""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return s.lower().strip()


def country_to_iso(country: str) -> str:
    norm = normalize(country)
    return COUNTRY_TO_ISO.get(norm, "ES")  # default ES si no se reconoce


def fetch_squad_table(url: str) -> Tag | None:
    r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=20)
    r.raise_for_status()
    r.encoding = "utf-8"
    soup = BeautifulSoup(r.text, "html.parser")
    # Headings que pueden contener la plantilla
    keywords = ("Plantilla", "Jugadores", "Plantilla actual", "Plantel")
    for h in soup.find_all(["h2", "h3"]):
        text = h.get_text(strip=True)
        if any(text.startswith(k) for k in keywords):
            # Probar primero toccolours (formato más estructurado)
            table = h.find_next("table", class_="toccolours")
            if table is not None:
                return table
            # Fallback: cualquier tabla siguiente con muchas filas (>10)
            for t in h.find_all_next("table"):
                rows = t.find_all("tr")
                if len(rows) > 10:
                    return t
                # Limitar la búsqueda
                # (parar si ya hemos pasado al siguiente heading h2)
                if t.find_previous(["h2"]) is not h.find_previous(["h2"]) and not h.name == "h2":
                    break
            break
    return None


def parse_age(s: str) -> int | None:
    m = re.search(r"(\d+)\s*a", s)
    return int(m.group(1)) if m else None


def parse_dorsal(s: str) -> int | None:
    s = s.strip()
    if s.isdigit():
        return int(s)
    return None


def parse_squad(table: Tag, season_year: int = 2026) -> list[dict]:
    """Devuelve lista de dicts con datos crudos de cada jugador."""
    players = []
    current_section = None  # "Porteros" | "Defensas" | "Centrocampistas" | "Delanteros" | "Cesiones"

    for row in table.find_all("tr"):
        cells = row.find_all(["th", "td"])
        # Section header: 1 sola celda con texto de sección.
        # Algunos artículos prefijan con "0-POR-00 Porteros" etc. — buscamos por substring.
        if len(cells) == 1:
            txt = cells[0].get_text(strip=True)
            for label in ("Porteros", "Defensas", "Centrocampistas", "Delanteros", "Cesiones"):
                if label in txt:
                    current_section = label
                    break
            else:
                if any(k in txt for k in ("Entrenador", "Incorporaciones", "Debuts", "Cupo")):
                    break
            continue

        # Filas de cabecera de tabla
        cell_texts = [c.get_text(" ", strip=True) for c in cells]
        if cell_texts and cell_texts[0] in ("N.º", "N.°"):
            continue
        if not current_section or current_section == "Cesiones":
            # v1: skip cesiones — el jugador aún pertenece al equipo origen pero está cedido
            # Lo mantenemos en el equipo origen sin incluirlo aquí.
            continue

        # Soporta tablas con 9 o 10 columnas. Buscamos los campos por patrón.
        if len(cell_texts) < 7:
            continue

        # 1) Dorsal: primera celda numérica (0 a 99)
        dorsal = parse_dorsal(cell_texts[0])

        # 2) País: primera celda con texto largo no numérico (suele ser índice 1)
        country = cell_texts[1].replace("!", "").strip() if len(cell_texts) > 1 else ""

        # 3) Posición: buscar POR|DEF|MED|DEL en cualquier celda
        wiki_pos = "MED"
        pos_idx = -1
        for i, ct in enumerate(cell_texts):
            m = re.search(r"\b(POR|DEF|MED|DEL)\b", ct)
            if m:
                wiki_pos = m.group(1)
                pos_idx = i
                break

        # 4) Nombre: la celda inmediatamente después de la posición
        name = ""
        if pos_idx >= 0 and pos_idx + 1 < len(cell_texts):
            name = cell_texts[pos_idx + 1].strip()

        # 5) Edad: buscar patrón "X años" en cualquier celda
        age = None
        for ct in cell_texts:
            m = re.search(r"(\d{1,2})\s*a", ct)
            if m:
                age = int(m.group(1))
                break

        # 6) Año de contrato: buscar año 20XX en últimas celdas
        contract_year = season_year + 2
        for ct in reversed(cell_texts):
            m2 = re.search(r"\b(20\d{2})\b", ct)
            if m2:
                y = int(m2.group(1))
                if 2024 <= y <= 2035:
                    contract_year = y
                    break

        # 7) Procedencia: celda entre edad y contrato (heurística simple)
        procedencia = cell_texts[pos_idx + 3] if pos_idx + 3 < len(cell_texts) else ""

        if not name or len(name) < 3:
            continue
        # Filtrar nombres que sean encabezados ("Nombre", "Cont.", etc)
        if name.lower() in ("nombre", "cont.", "edad", "nac.", "pos.", "n.º", "n.°"):
            continue

        players.append({
            "dorsal": dorsal,
            "name": name,
            "wiki_pos": wiki_pos,
            "country": country,
            "age": age,
            "procedencia": procedencia,
            "contract_year": contract_year,
        })

    return players


def assign_tier(name: str, age: int | None, wiki_pos: str) -> tuple[str, str]:
    """Devuelve (tier_actual, tier_potencial). STARS contiene tuplas; default por edad."""
    norm = normalize(name)
    for star_key, tiers in STARS.items():
        if star_key in norm:
            return tiers  # tuple (current, potential)
    # Default por edad: jóvenes Y, adultos C
    if age is None:
        return ("C", "B")
    if age < 19:
        return ("Y", "B")
    return ("C", "B")


def to_player_json(team_short: str, idx: int, raw: dict, season_year: int) -> dict:
    dorsal = raw["dorsal"] if raw["dorsal"] is not None else 30 + idx
    nationality = country_to_iso(raw["country"])
    positions = map_position(raw["name"], raw["wiki_pos"], dorsal)
    age = raw["age"] if raw["age"] is not None else 25
    birth_year = season_year - age
    tier, potential_tier = assign_tier(raw["name"], age, raw["wiki_pos"])
    pid = "%s_p%03d" % (team_short.lower(), idx + 1)
    return {
        "id": pid,
        "name": raw["name"],
        "birth_date": {"year": birth_year, "month": 6, "day": 15},
        "nationality": nationality,
        "positions": positions,
        "preferred_foot": "R",
        "tier": tier,
        "potential_tier": potential_tier,
        "shirt_number": dorsal,
        "captain": False,
        "traits": [],
        "overrides": {},
        "joined_year": max(season_year - 4, 2018),
        "contract": {
            "until_year": raw["contract_year"],
            "salary_eur_year": _salary_estimate(tier),
            "release_clause_eur": _clause_estimate(tier),
        },
    }


def _salary_estimate(tier: str) -> int:
    return {"S": 12_000_000, "A": 6_000_000, "B": 2_500_000,
            "C": 1_000_000, "D": 500_000, "Y": 300_000}.get(tier, 1_000_000)


def _clause_estimate(tier: str) -> int:
    return {"S": 200_000_000, "A": 80_000_000, "B": 35_000_000,
            "C": 15_000_000, "D": 7_000_000, "Y": 20_000_000}.get(tier, 15_000_000)


# ---------------------------------------------------------------------------
# Merge con archivo existente
# ---------------------------------------------------------------------------

def update_team_json(existing_path: Path, scraped_players: list[dict], season_year: int) -> dict:
    """Carga el JSON existente y reemplaza solo los players."""
    with open(existing_path, "r", encoding="utf-8") as f:
        team = json.load(f)
    short = team.get("short_name", "TEM")
    new_players = [to_player_json(short, i, raw, season_year) for i, raw in enumerate(scraped_players)]
    team["players"] = new_players
    team["_draft_note"] = (
        "Plantilla scrapeada de Wikipedia ES (%d-%02d). "
        "Tiers asignados por heurística — verificar y refinar manualmente."
    ) % (season_year, season_year + 1 - 2000)
    return team


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    repo_root = Path(__file__).resolve().parent.parent
    teams_dir = repo_root / "data" / "teams"
    scraped_dir = teams_dir / "_scraped"
    scraped_dir.mkdir(parents=True, exist_ok=True)

    only = sys.argv[1] if len(sys.argv) > 1 else None
    season_year = 2026

    items = list(WIKI_URLS.items())
    if only:
        items = [(k, v) for k, v in items if k == only]

    summary = {"ok": [], "fail": [], "protected": []}

    for team_id, url in items:
        # Encontrar archivo existente
        primera_path = teams_dir / "primera" / f"{team_id}.json"
        segunda_path = teams_dir / "segunda" / f"{team_id}.json"
        if primera_path.exists():
            existing_path = primera_path
        elif segunda_path.exists():
            existing_path = segunda_path
        else:
            print(f"[SKIP] {team_id}: archivo JSON no encontrado")
            summary["fail"].append(team_id)
            continue

        try:
            print(f"[FETCH] {team_id}: {url}")
            table = fetch_squad_table(url)
            if table is None:
                print(f"[FAIL] {team_id}: no encontré tabla de plantilla")
                summary["fail"].append(team_id)
                continue
            raw_players = parse_squad(table, season_year)
            if not raw_players:
                print(f"[FAIL] {team_id}: tabla vacía")
                summary["fail"].append(team_id)
                continue
            new_team = update_team_json(existing_path, raw_players, season_year)

            if team_id in PROTECTED_TEAMS:
                # No sobrescribir el original; escribir copia para review
                out = scraped_dir / f"{team_id}.json"
                with open(out, "w", encoding="utf-8") as f:
                    json.dump(new_team, f, ensure_ascii=False, indent=2)
                print(f"[OK ~] {team_id}: {len(raw_players)} jugadores ->{out.relative_to(repo_root)} (NO sobrescrito por ser PROTECTED)")
                summary["protected"].append(team_id)
            else:
                with open(existing_path, "w", encoding="utf-8") as f:
                    json.dump(new_team, f, ensure_ascii=False, indent=2)
                print(f"[OK *] {team_id}: {len(raw_players)} jugadores ->{existing_path.relative_to(repo_root)} (sobrescrito)")
                summary["ok"].append(team_id)

            time.sleep(0.5)  # cortesía con Wikipedia
        except Exception as e:
            print(f"[ERROR] {team_id}: {e}")
            summary["fail"].append(team_id)

    print()
    print("=" * 60)
    print(f"Sobrescritos:  {len(summary['ok']):2d}  ({', '.join(summary['ok'])})")
    print(f"Protegidos:    {len(summary['protected']):2d}  ({', '.join(summary['protected'])})")
    print(f"Fallidos:      {len(summary['fail']):2d}  ({', '.join(summary['fail'])})")


if __name__ == "__main__":
    main()
