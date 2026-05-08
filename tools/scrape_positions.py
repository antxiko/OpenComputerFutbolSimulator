"""
Scraper de POSICIONES desde Transfermarkt (es.transfermarkt.es).

USO:
    python tools/scrape_positions.py
        # Lee URLs de clubes desde las paginas LaLiga / LaLiga 2 (auto-discover)
        # Scrapea cada club y genera data/scraped_positions.json

    python tools/scrape_positions.py --apply
        # Tras scrapear, aplica las posiciones a los JSON de equipo en data/teams/

    python tools/scrape_positions.py --apply-only
        # Salta el scraping y solo aplica el JSON ya existente

OBJETIVO:
    Hoy ~74% de jugadores tienen positions tipo [CB,LB,RB] o [ST,LW,RW]
    porque el scraper viejo de Wikipedia ES solo distinguia POR/DEF/MED/DEL.
    Transfermarkt tiene posicion granular (Defensa central, Lateral izq, Pivote,
    Mediocentro ofensivo, Extremo derecho, etc.) en la tabla de plantilla.

MAPEO:
    Transfermarkt (es)         -> OCFS slots
    Portero                    -> ["GK"]
    Defensa central            -> ["CB"]
    Lateral derecho            -> ["RB"]
    Lateral izquierdo          -> ["LB"]
    Pivote                     -> ["CDM"]
    Mediocentro defensivo      -> ["CDM"]
    Mediocentro                -> ["CM"]
    Interior derecho           -> ["CM"]
    Interior izquierdo         -> ["CM"]
    Mediocentro ofensivo       -> ["CAM"]
    Mediapunta                 -> ["CAM"]
    Extremo derecho            -> ["RW"]
    Extremo izquierdo          -> ["LW"]
    Delantero centro           -> ["ST"]
    Segundo delantero          -> ["ST", "CAM"]

NOTAS:
    - El matching nombre -> jugador es por normalizacion (sin acentos, lowercase).
    - Si Transfermarkt y Wikipedia tienen ortografias distintas (Inaki vs Iñaki),
      el normalizado coincide. Si hay duda, se intenta substring de apellido.
    - Solo se modifica el campo "positions" del player. Tier, contrato, etc se preservan.
"""
from __future__ import annotations

import json
import re
import sys
import time
import unicodedata
from pathlib import Path

import requests
from bs4 import BeautifulSoup, Tag


HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "es-ES,es;q=0.9",
}

LIGA_URLS = {
    "primera": "https://www.transfermarkt.es/laliga/startseite/wettbewerb/ES1",
    "segunda": "https://www.transfermarkt.es/laliga2/startseite/wettbewerb/ES2",
}

# Mapeo Transfermarkt -> OCFS slots.
POSITION_MAP = {
    "portero": ["GK"],
    "defensa central": ["CB"],
    "lateral derecho": ["RB"],
    "lateral izquierdo": ["LB"],
    "pivote": ["CDM"],
    "mediocentro defensivo": ["CDM"],
    "mediocentro": ["CM"],
    "interior derecho": ["CM"],
    "interior izquierdo": ["CM"],
    "mediocentro ofensivo": ["CAM"],
    "mediapunta": ["CAM"],
    "extremo derecho": ["RW"],
    "extremo izquierdo": ["LW"],
    "delantero centro": ["ST"],
    "segundo delantero": ["ST", "CAM"],
}

# Mapeo nombre normalizado de club en TM -> team_id local.
# Lo construye main() resolviendo por aproximacion sobre data/teams/.
# Aqui solo lista alias conocidos donde el nombre TM != nombre local.
CLUB_ALIASES = {
    "fc barcelona": "fc_barcelona",
    "real madrid": "real_madrid",
    "real madrid cf": "real_madrid",
    "atletico de madrid": "atletico_madrid",
    "club atletico de madrid": "atletico_madrid",
    "athletic club": "athletic_club",
    "athletic de bilbao": "athletic_club",
    "real sociedad": "real_sociedad",
    "real sociedad de futbol": "real_sociedad",
    "villarreal cf": "villarreal_cf",
    "real betis balompie": "real_betis",
    "real betis": "real_betis",
    "sevilla fc": "sevilla_fc",
    "valencia cf": "valencia_cf",
    "girona fc": "girona_fc",
    "ca osasuna": "ca_osasuna",
    "club atletico osasuna": "ca_osasuna",
    "rayo vallecano": "rayo_vallecano",
    "rayo vallecano de madrid": "rayo_vallecano",
    "rc celta de vigo": "celta_vigo",
    "celta de vigo": "celta_vigo",
    "rcd mallorca": "rcd_mallorca",
    "real club deportivo mallorca": "rcd_mallorca",
    "getafe cf": "getafe_cf",
    "deportivo alaves": "deportivo_alaves",
    "rcd espanyol barcelona": "rcd_espanyol",
    "rcd espanyol": "rcd_espanyol",
    "espanyol de barcelona": "rcd_espanyol",
    "levante ud": "levante_ud",
    "elche cf": "elche_cf",
    "real oviedo": "real_oviedo",
    # Segunda
    "real valladolid cf": "real_valladolid",
    "real valladolid": "real_valladolid",
    "ud las palmas": "ud_las_palmas",
    "cd leganes": "cd_leganes",
    "real sporting de gijon": "real_sporting",
    "sporting de gijon": "real_sporting",
    "real zaragoza": "real_zaragoza",
    "granada cf": "granada_cf",
    "ud almeria": "ud_almeria",
    "sd eibar": "sd_eibar",
    "burgos cf": "burgos_cf",
    "fc cartagena": "fc_cartagena",
    "cadiz cf": "cadiz_cf",
    "cd tenerife": "cd_tenerife",
    "albacete balompie": "albacete_balompie",
    "cd mirandes": "cd_mirandes",
    "cd castellon": "cd_castellon",
    "cd eldense": "cd_eldense",
    "malaga cf": "malaga_cf",
    "sd huesca": "sd_huesca",
    "cordoba cf": "cordoba_cf",
    "real racing club": "racing_santander",
    "racing de santander": "racing_santander",
    "racing club de santander": "racing_santander",
    "ad ceuta fc": "ad_ceuta",
    "ad ceuta": "ad_ceuta",
    "fc andorra": "fc_andorra",
}


def normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return s.lower().strip()


def fetch(url: str) -> BeautifulSoup:
    r = requests.get(url, headers=HEADERS, timeout=30)
    r.raise_for_status()
    r.encoding = "utf-8"
    return BeautifulSoup(r.text, "html.parser")


def discover_clubs() -> list[tuple[str, str, str]]:
    """Descubre las URLs de plantilla de cada club desde la pagina de la liga.
    Devuelve lista de (division, club_name_tm, club_squad_url)."""
    out: list[tuple[str, str, str]] = []
    for division, url in LIGA_URLS.items():
        print(f"[DISCOVER] {division}: {url}")
        soup = fetch(url)
        # Las filas de equipos en la tabla principal tienen <td class='hauptlink'><a href='/club-slug/startseite/verein/<id>'>Nombre</a></td>
        for a in soup.select("td.hauptlink a"):
            href = a.get("href", "")
            if "/startseite/verein/" not in href:
                continue
            name = a.get_text(strip=True)
            if not name:
                continue
            full_url = "https://www.transfermarkt.es" + href if href.startswith("/") else href
            # Forzar saison_id 2025 (temporada 25-26)
            if "saison_id" not in full_url:
                sep = "&" if "?" in full_url else "?"
                full_url = f"{full_url}{sep}saison_id=2025"
            if (division, name, full_url) not in out:
                out.append((division, name, full_url))
        time.sleep(0.5)
    return out


EXCLUDE_NAMES = {
    # Filiales que TM lista en Segunda pero que no nos interesan
    "real sociedad b",
    "fc barcelona b",
    "real madrid castilla",
    "atletico de madrid b",
    "athletic club b",
    "bilbao athletic",
}


def map_to_local_team_id(tm_name: str, available_ids: set[str]) -> str | None:
    """Resuelve nombre de club TM a team_id local. Devuelve None si filial o no match."""
    norm = normalize(tm_name)
    if norm in EXCLUDE_NAMES:
        return None
    if norm in CLUB_ALIASES:
        cand = CLUB_ALIASES[norm]
        if cand in available_ids:
            return cand
    # Slug directo (sin acentos, espacios -> guion bajo)
    slug = re.sub(r"\s+", "_", norm)
    slug = re.sub(r"[^a-z0-9_]", "", slug)
    if slug in available_ids:
        return slug
    # No usar fallback de substring: demasiado permisivo (Real Sociedad B
    # matcheaba con real_sociedad). Mejor que el equipo se ignore y se
    # reporte como [SKIP] para que sepamos que falta el alias.
    return None


def parse_squad(url: str) -> list[dict]:
    """Devuelve [{dorsal, name, position_tm, age}] de la plantilla en url."""
    soup = fetch(url)
    table = soup.find("table", class_="items")
    if table is None:
        return []
    players: list[dict] = []
    for row in table.find_all("tr"):
        cells = row.find_all(["th", "td"])
        if len(cells) != 8:
            continue
        texts = [c.get_text(" ", strip=True) for c in cells]
        if texts[0] == "#":
            continue
        # Estructura: [dorsal, "<Nombre> <Pos>" o foto+nombre, '', nombre, posicion, fecha (edad), nac, valor]
        dorsal = texts[0]
        name = texts[3]
        pos_tm = texts[4]
        age_match = re.search(r"\((\d{2})\)", texts[5])
        age = int(age_match.group(1)) if age_match else None
        if not name or not pos_tm:
            continue
        players.append({
            "dorsal": dorsal,
            "name": name,
            "position_tm": pos_tm,
            "age": age,
        })
    return players


def map_position(pos_tm: str) -> list[str]:
    norm = normalize(pos_tm)
    return POSITION_MAP.get(norm, ["CM"])


# ---------------------------------------------------------------------------
# SCRAPE
# ---------------------------------------------------------------------------

def scrape_all(out_path: Path) -> dict:
    available_ids: set[str] = set()
    for sub in ("primera", "segunda"):
        for fp in (Path("data/teams") / sub).glob("*.json"):
            available_ids.add(fp.stem)

    clubs = discover_clubs()
    print(f"[INFO] Descubiertos {len(clubs)} clubs en TM.")
    result: dict = {"_source": "transfermarkt.es 2025-26", "teams": {}}
    failed_clubs: list[str] = []
    for division, tm_name, url in clubs:
        local_id = map_to_local_team_id(tm_name, available_ids)
        if not local_id:
            print(f"  [SKIP] {tm_name}: no encontrado en data/teams/ (alias necesario?)")
            failed_clubs.append(tm_name)
            continue
        print(f"  [FETCH] {division}/{local_id} <- {tm_name}")
        try:
            squad = parse_squad(url)
            if not squad:
                print(f"    [WARN] tabla vacia: {url}")
                failed_clubs.append(local_id)
                continue
            result["teams"][local_id] = {
                "tm_name": tm_name,
                "tm_url": url,
                "division": division,
                "players": [
                    {
                        "name": p["name"],
                        "name_norm": normalize(p["name"]),
                        "dorsal": p["dorsal"],
                        "age": p["age"],
                        "position_tm": p["position_tm"],
                        "positions": map_position(p["position_tm"]),
                    }
                    for p in squad
                ],
            }
            print(f"    -> {len(squad)} jugadores")
            time.sleep(0.6)
        except Exception as e:
            print(f"    [ERROR] {e}")
            failed_clubs.append(local_id)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print()
    print(f"[OK] Escrito {out_path}: {len(result['teams'])} equipos.")
    if failed_clubs:
        print(f"[WARN] Fallaron: {failed_clubs}")
    return result


# ---------------------------------------------------------------------------
# APPLY
# ---------------------------------------------------------------------------

def safe_print(s: str) -> None:
    """Print con fallback ascii — la consola Windows no traga algunos unicode."""
    try:
        print(s)
    except UnicodeEncodeError:
        print(s.encode("ascii", errors="replace").decode("ascii"))


def _token_eq(a: str, b: str) -> bool:
    """Iguales o uno es prefijo del otro (para Dani/Daniel, Vini/Vinicius)."""
    if a == b:
        return True
    if len(a) >= 4 and len(b) >= 4:
        if a.startswith(b) or b.startswith(a):
            return True
    return False


def _has_match(token: str, candidates: set[str]) -> bool:
    return any(_token_eq(token, c) for c in candidates)


def fuzzy_player_match(local_name_norm: str, tm_index: dict) -> dict | None:
    """Match con tolerancia a prefijos (apodos como Dani/Daniel, Vini/Vinicius)
    y a omisiones de nombres compuestos (Reinildo Mandava <-> Reinildo).

    1) Match exacto por normalizacion completa.
    2) "Cobertura" del set pequeño: cada token significativo del nombre corto
       (>=3 chars) tiene equivalente exacto o por prefijo en el largo, y
       al menos un token tiene 5+ chars (descarta apodos de 3-4 letras
       genéricos como "Jose", "Juan").
    3) Jaccard ajustado >= 0.6.
    """
    if local_name_norm in tm_index:
        return tm_index[local_name_norm]
    a_tokens = set(t for t in local_name_norm.split() if len(t) >= 3)
    if not a_tokens:
        return None

    best: dict | None = None
    best_score: float = 0.0
    for tm_norm, tm_player in tm_index.items():
        b_tokens = set(t for t in tm_norm.split() if len(t) >= 3)
        if not b_tokens:
            continue
        a_in_b = sum(1 for t in a_tokens if _has_match(t, b_tokens))
        b_in_a = sum(1 for t in b_tokens if _has_match(t, a_tokens))
        # Cobertura del set pequeno
        small, big = (a_tokens, b_tokens) if len(a_tokens) <= len(b_tokens) else (b_tokens, a_tokens)
        small_in_big = a_in_b if small is a_tokens else b_in_a
        coverage = small_in_big / len(small)
        score = 0.0
        if coverage >= 1.0 and any(len(t) >= 5 for t in small):
            # Cobertura total + apellido distintivo
            score = 1.0 + (1.0 / max(1, len(big)))
        elif coverage >= 0.66 and any(len(t) >= 5 for t in small):
            # Cobertura parcial alta (uno o dos tokens fuera)
            score = coverage * 0.8
        else:
            # Jaccard ajustado por matching con prefijos
            ajusted = (a_in_b + b_in_a) / (len(a_tokens) + len(b_tokens))
            if ajusted >= 0.6:
                score = ajusted * 0.7
        if score > best_score:
            best_score = score
            best = tm_player
    return best


ESSENTIAL_SLOTS = ["GK", "LB", "CB", "RB", "CDM", "CM", "CAM", "LW", "RW", "ST"]


def ensure_slot_coverage(team: dict) -> int:
    """Garantiza que el equipo tenga al menos 1 jugador disponible por slot
    esencial. Si falta, añade un slot secundario al CM mas adecuado.
    Devuelve cuantas asignaciones secundarias hizo."""
    slot_count: dict[str, int] = {s: 0 for s in ESSENTIAL_SLOTS}
    cm_players: list[dict] = []
    for p in team.get("players", []):
        for s in p.get("positions", []):
            if s in slot_count:
                slot_count[s] += 1
        if "CM" in p.get("positions", []):
            cm_players.append(p)

    fixes = 0
    # CDM: si falta, hacer que el CM mayor sea tambien CDM
    if slot_count["CDM"] == 0 and cm_players:
        target = cm_players[0]
        if "CDM" not in target["positions"]:
            target["positions"].append("CDM")
            fixes += 1
    # CAM: si falta, hacer que un CM (otro distinto si es posible) sea tambien CAM
    if slot_count["CAM"] == 0 and cm_players:
        target = cm_players[-1] if len(cm_players) > 1 else cm_players[0]
        if "CAM" not in target["positions"]:
            target["positions"].append("CAM")
            fixes += 1
    return fixes


def apply_positions(scraped_path: Path) -> None:
    if not scraped_path.exists():
        safe_print(f"[ERR] No existe {scraped_path}. Ejecuta el scraping primero.")
        return
    with open(scraped_path, "r", encoding="utf-8") as f:
        scraped = json.load(f)
    teams_data = scraped.get("teams", {})

    teams_dir = Path("data/teams")
    summary = {"updated_players": 0, "no_match": 0, "teams_updated": 0,
               "missing_per_team": {}}

    for sub in ("primera", "segunda"):
        for fp in (teams_dir / sub).glob("*.json"):
            tid = fp.stem
            if tid not in teams_data:
                continue
            with open(fp, "r", encoding="utf-8") as f:
                team = json.load(f)
            tm_index = {pp["name_norm"]: pp for pp in teams_data[tid]["players"]}

            updated = 0
            missing: list[str] = []
            used_tm_keys: set[str] = set()
            for pl in team.get("players", []):
                nm = normalize(pl.get("name", ""))
                hit = fuzzy_player_match(nm, tm_index)
                if hit is None or hit["name_norm"] in used_tm_keys:
                    missing.append(pl.get("name", "?"))
                    continue
                pl["positions"] = list(hit["positions"])
                used_tm_keys.add(hit["name_norm"])
                updated += 1

            fixes = ensure_slot_coverage(team)
            with open(fp, "w", encoding="utf-8") as f:
                json.dump(team, f, ensure_ascii=False, indent=2)

            summary["updated_players"] += updated
            summary["no_match"] += len(missing)
            summary["teams_updated"] += 1
            if missing:
                summary["missing_per_team"][tid] = missing
            extra = f" (+{fixes} fix de cobertura)" if fixes else ""
            safe_print(f"  [{tid}] actualizado: {updated} / sin match: {len(missing)}{extra}")

    safe_print("")
    safe_print(f"[OK] Equipos procesados: {summary['teams_updated']}")
    safe_print(f"     Jugadores actualizados: {summary['updated_players']}")
    safe_print(f"     Jugadores sin match: {summary['no_match']}")
    if summary["missing_per_team"]:
        safe_print("")
        safe_print("Jugadores sin match (revisar a mano si es relevante):")
        for tid, names in summary["missing_per_team"].items():
            preview = ", ".join(names[:5]) + ("..." if len(names) > 5 else "")
            safe_print(f"  {tid}: {preview}")


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def regenerate_team_from_tm(scraped_path: Path, team_id: str, season_year: int = 2026) -> None:
    """Reemplaza players completos de un team JSON con datos TM. Tier C default,
    salary/clausula heuristica. Para usar cuando el JSON esta corrupto."""
    if not scraped_path.exists():
        safe_print(f"[ERR] No existe {scraped_path}.")
        return
    with open(scraped_path, "r", encoding="utf-8") as f:
        scraped = json.load(f)
    if team_id not in scraped.get("teams", {}):
        safe_print(f"[ERR] {team_id} no esta en datos scrapeados.")
        return

    teams_dir = Path("data/teams")
    fp = None
    for sub in ("primera", "segunda"):
        cand = teams_dir / sub / f"{team_id}.json"
        if cand.exists():
            fp = cand
            break
    if fp is None:
        safe_print(f"[ERR] team JSON no encontrado para {team_id}")
        return

    with open(fp, "r", encoding="utf-8") as f:
        team = json.load(f)
    short = team.get("short_name", team_id[:3].upper())

    new_players = []
    for i, raw in enumerate(scraped["teams"][team_id]["players"]):
        try:
            dorsal = int(raw["dorsal"]) if raw.get("dorsal") and str(raw["dorsal"]).strip().isdigit() else 30 + i
        except (ValueError, TypeError):
            dorsal = 30 + i
        age = raw.get("age") or 25
        birth_year = season_year - int(age)
        # Tier C por defecto (jovenes Y), salario y clausula tipicos Segunda
        tier = "Y" if age < 19 else "C"
        potential_tier = "B" if age < 23 else "C"
        pid = "%s_p%03d" % (short.lower(), i + 1)
        new_players.append({
            "id": pid,
            "name": raw["name"],
            "birth_date": {"year": birth_year, "month": 6, "day": 15},
            "nationality": "ES",  # asumir ES por defecto, refinar manualmente si hace falta
            "positions": list(raw["positions"]),
            "preferred_foot": "R",
            "tier": tier,
            "potential_tier": potential_tier,
            "shirt_number": dorsal,
            "captain": False,
            "traits": [],
            "overrides": {},
            "joined_year": max(season_year - 3, 2020),
            "contract": {
                "until_year": season_year + 2,
                "salary_eur_year": 1_000_000 if tier == "C" else 300_000,
                "release_clause_eur": 15_000_000 if tier == "C" else 7_000_000,
            },
        })
    team["players"] = new_players
    team["_draft_note"] = f"Plantilla regenerada desde Transfermarkt 25-26 ({len(new_players)} jugadores). Tiers asignados por defecto C/Y — refinar manualmente si hace falta."

    with open(fp, "w", encoding="utf-8") as f:
        json.dump(team, f, ensure_ascii=False, indent=2)
    safe_print(f"[OK] {team_id}: regenerados {len(new_players)} jugadores.")


def main():
    out_path = Path("data/scraped_positions.json")
    args = sys.argv[1:]
    do_scrape = True
    do_apply = False
    regen_team: str | None = None
    if "--apply-only" in args:
        do_scrape = False
        do_apply = True
    elif "--apply" in args:
        do_scrape = True
        do_apply = True
    if "--regenerate" in args:
        idx = args.index("--regenerate")
        if idx + 1 < len(args):
            regen_team = args[idx + 1]
        do_scrape = False
        do_apply = False

    if regen_team:
        regenerate_team_from_tm(out_path, regen_team)
        return
    if do_scrape:
        scrape_all(out_path)
    if do_apply:
        print()
        print("=" * 60)
        print("APLICANDO POSITIONS A LOS JSON DE EQUIPO")
        print("=" * 60)
        apply_positions(out_path)


if __name__ == "__main__":
    main()
