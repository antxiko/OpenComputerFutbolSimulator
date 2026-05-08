"""
Scrape datos de tarjetas de la API de Marca (Unidad Editorial) para La Liga
2025-26 y derivar un valor de "aggression" 0-100 por jugador.

Salida: data/aggression_overrides.json

Estructura:
{
    "_meta": { "source": "...", "scraped_at": "...", "season": "2025-26" },
    "players": {
        "alejandro catena": { "aggression": 86, "yellow_cards": 10, "red_cards": 1, "games": 31, "team": "Osasuna" },
        ...
    }
}

Uso desde GDScript: AggressionSystem.init_player(p) lee el JSON al cargar.
"""
import json
import re
import unicodedata
from pathlib import Path

import requests


SOURCES = [
    {
        "name": "Primera (LALIGA EA Sports)",
        "url": "https://api.unidadeditorial.es/sports/v1/player-total-rank/sport/01/tournament/0101/season/2025/sort/cards?site=2&mn=50",
    },
    {
        "name": "Segunda (LALIGA Hypermotion)",
        "url": "https://api.unidadeditorial.es/sports/v1/player-total-rank/sport/01/tournament/0102/season/2025/sort/cards?site=2&mn=50",
    },
]


def normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return s.lower().strip()


def cards_to_aggression(yellow: int, red: int, games: int) -> int:
    """Mapea cards/game ratio a aggression 25-95 lineal, +5 si tiene roja(s)."""
    if games <= 0:
        return 50
    ratio = (yellow + red * 2) / games  # roja cuenta doble
    base = 25.0 + ratio * 175.0
    if red > 0:
        base += 5.0
    return max(25, min(95, round(base)))


def main():
    out: dict = {
        "_meta": {
            "source": "api.unidadeditorial.es (Marca)",
            "season": "2025-26",
            "sources": [s["name"] for s in SOURCES],
        },
        "players": {},
    }
    total_scraped = 0
    for src in SOURCES:
        print(f"[FETCH] {src['name']}: {src['url']}")
        r = requests.get(src["url"], headers={"User-Agent": "Mozilla/5.0 OCFS-personal"})
        r.raise_for_status()
        data = r.json()
        if data.get("status") != "success":
            print(f"  Error: status {data.get('status')}")
            continue
        rank = data["data"].get("rank", [])
        for entry in rank:
            name = str(entry.get("knownName", "")).strip()
            if not name:
                continue
            yellow = int(entry.get("yellowCards", 0))
            red = int(entry.get("redCards", 0))
            games = int(entry.get("games", 0))
            agg = cards_to_aggression(yellow, red, games)
            key = normalize(name)
            out["players"][key] = {
                "name": name,
                "team": entry.get("teamName", ""),
                "yellow_cards": yellow,
                "red_cards": red,
                "games": games,
                "aggression": agg,
            }
            total_scraped += 1
        print(f"  -> {len(rank)} jugadores")

    # Asegurar dir y escribir
    repo_root = Path(__file__).resolve().parent.parent
    out_path = repo_root / "data" / "aggression_overrides.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\nGuardado {total_scraped} jugadores en {out_path}")
    # Estadisticas
    aggs = [p["aggression"] for p in out["players"].values()]
    if aggs:
        print(f"  aggression min/avg/max: {min(aggs)} / {sum(aggs)/len(aggs):.1f} / {max(aggs)}")
        # Top 10 mas agresivos
        top = sorted(out["players"].items(), key=lambda kv: kv[1]["aggression"], reverse=True)[:10]
        print("  Top 10 mas agresivos:")
        for k, v in top:
            try:
                print(f"    {v['aggression']:3d}  {v['name']:30s} {v['team']:20s} ({v['yellow_cards']}TA + {v['red_cards']}TR en {v['games']}PJ)")
            except Exception:
                # Fallback ASCII
                print(f"    {v['aggression']:3d}  {k:30s}")


if __name__ == "__main__":
    main()
