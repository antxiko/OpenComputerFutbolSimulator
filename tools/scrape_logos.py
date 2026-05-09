"""
Scraper de escudos de los 42 equipos de La Liga + Segunda desde Wikipedia ES.

Para cada equipo, busca el archivo del escudo en la página de Wikipedia
del club (infobox imagen del equipo) y lo descarga a assets/logos/<team_id>.png.

Uso:
    python tools/scrape_logos.py
    python tools/scrape_logos.py real_madrid   # solo uno
"""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote, urljoin

import requests
from bs4 import BeautifulSoup


HEADERS = {
    # Wikimedia exige UA específico con contacto. Ver https://meta.wikimedia.org/wiki/User-Agent_policy
    "User-Agent": "OpenComputerFutbolSimulator/0.2 (https://github.com/antxiko/OpenComputerFutbolSimulator; antxiko@gmail.com) requests/2",
    "Accept": "image/png, image/svg+xml, image/jpeg, */*",
    "Accept-Language": "es-ES,es;q=0.9",
}

# Mapeo team_id -> Wikipedia URL (re-uso del scrape_squads).
WIKI_URLS = {
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


def find_logo_url(team_id: str, page_url: str) -> str | None:
    """Parsea el HTML del artículo de Wikipedia y busca el escudo en el infobox.
    Filtra banderas y otras imágenes irrelevantes."""
    try:
        r = requests.get(page_url, headers=HEADERS, timeout=20)
        r.raise_for_status()
        r.encoding = "utf-8"
    except Exception as e:
        print(f"  [HTML ERR] {e}")
        return None
    soup = BeautifulSoup(r.text, "html.parser")
    # Wikipedia usa <table class="infobox"> o <aside class="infobox">
    infobox = soup.find(["table", "aside"], class_=re.compile("infobox"))
    if infobox is None:
        infobox = soup
    # Iterar imágenes del infobox; filtrar banderas y elegir la primera "buena"
    for img in infobox.find_all("img"):
        src = img.get("src", "")
        alt = img.get("alt", "")
        if not src:
            continue
        if "Flag_of" in src or "Flag of" in alt or "Bandera" in alt:
            continue
        # Filtrar iconos pequeñitos (típicamente <30px)
        try:
            w = int(img.get("width", "0"))
            if w < 50:
                continue
        except ValueError:
            pass
        # ¡Listo! Construir URL absoluta y subir a 256px
        if src.startswith("//"):
            src = "https:" + src
        elif src.startswith("/"):
            src = "https://es.wikipedia.org" + src
        # Cambiar tamaño a 256px si es un thumb
        src = re.sub(r"/(\d+)px-", "/256px-", src)
        return src
    return None


def download_image(url: str, dest: Path) -> bool:
    try:
        r = requests.get(url, headers=HEADERS, timeout=30)
        r.raise_for_status()
        dest.write_bytes(r.content)
        return True
    except Exception as e:
        print(f"  [ERR] download {url}: {e}")
        return False


def scrape_logo(team_id: str, url: str, out_dir: Path) -> bool:
    # Comprobar si ya existe en alguna extensión
    for ext in ("png", "jpg", "jpeg"):
        existing = out_dir / f"{team_id}.{ext}"
        if existing.exists() and existing.stat().st_size > 0:
            print(f"[SKIP] {team_id}: ya existe ({existing.name})")
            return True
    print(f"[FETCH] {team_id}")
    logo_url = find_logo_url(team_id, url)
    if not logo_url:
        print(f"  [WARN] no encontrado escudo para {team_id}")
        return False
    print(f"  -> {logo_url}")
    # SVG → pedir versión PNG via thumb
    if logo_url.endswith(".svg"):
        m = re.match(r"https://upload\.wikimedia\.org/wikipedia/(?:commons|es)/([0-9a-f])/([0-9a-f]{2})/(.+\.svg)$", logo_url)
        if m:
            d1, d2, fname = m.groups()
            logo_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/%s/%s/%s/256px-%s.png" % (d1, d2, fname, fname)
    # Detectar extensión real de la URL final
    ext: str = "png"
    if ".jpg" in logo_url.lower() or ".jpeg" in logo_url.lower():
        # Si la URL es un JPG (originalimage), forzar 256px PNG via thumb
        # https://upload.wikimedia.org/wikipedia/commons/X/YY/file.jpg
        m = re.search(r"upload\.wikimedia\.org/wikipedia/(commons|es)/([0-9a-f])/([0-9a-f]{2})/([^/]+\.jpg)", logo_url, re.I)
        if m:
            d1, d2, fname = m.group(2), m.group(3), m.group(4)
            ns: str = m.group(1)
            logo_url = "https://upload.wikimedia.org/wikipedia/%s/thumb/%s/%s/%s/256px-%s.png" % (ns, d1, d2, fname, fname)
        else:
            ext = "jpg"
    out_path = out_dir / f"{team_id}.{ext}"
    ok = download_image(logo_url, out_path)
    if ok:
        print(f"  [OK] {out_path.name} ({out_path.stat().st_size} bytes)")
    return ok


def main():
    repo_root = Path(__file__).resolve().parent.parent
    out_dir = repo_root / "assets" / "logos"
    out_dir.mkdir(parents=True, exist_ok=True)

    only = sys.argv[1] if len(sys.argv) > 1 else None
    items = list(WIKI_URLS.items())
    if only:
        items = [(k, v) for k, v in items if k == only]

    ok_count = 0
    fail_count = 0
    for team_id, url in items:
        ok = scrape_logo(team_id, url, out_dir)
        if ok: ok_count += 1
        else: fail_count += 1
        time.sleep(0.5)

    print()
    print(f"OK: {ok_count}")
    print(f"FAIL: {fail_count}")


if __name__ == "__main__":
    main()
