"""
Refina jugadores con posiciones genéricas heredadas del scraper viejo de
Wikipedia ([CB,LB,RB] / [CM,CDM,CAM] / [ST,LW,RW]) asignándoles UNA posición
específica por hash determinista de su id.

Distribución por categoría:
  DEF: 50% CB, 25% LB, 25% RB
  MED: 50% CM, 25% CDM, 25% CAM
  ATQ: 40% ST, 30% LW, 30% RW

Algunos casos especiales:
  - Si dorsal en {2, 22}: forzar RB (es el slot tradicional del lateral derecho).
  - Si dorsal en {3, 23}: forzar LB.
  - Si dorsal == 9: forzar ST (delantero centro clásico).
  - Si dorsal en {7, 11}: forzar RW/LW respectivamente.

Uso:
    python tools/refine_generic_positions.py
"""
import json
import glob
import os
import hashlib

GENERIC_DEF = {"CB", "LB", "RB"}
GENERIC_MED = {"CM", "CDM", "CAM"}
GENERIC_ATQ = {"ST", "LW", "RW"}


def stable_hash(s: str) -> int:
    return int(hashlib.md5(s.encode("utf-8")).hexdigest()[:8], 16)


def pick_def(dorsal: int, h: int) -> str:
    if dorsal in (2, 22):
        return "RB"
    if dorsal in (3, 23):
        return "LB"
    r = h % 100
    if r < 50: return "CB"
    if r < 75: return "LB"
    return "RB"


def pick_med(dorsal: int, h: int) -> str:
    if dorsal in (10, 20):
        return "CAM"
    if dorsal in (6, 16):
        return "CDM"
    r = h % 100
    if r < 50: return "CM"
    if r < 75: return "CDM"
    return "CAM"


def pick_atq(dorsal: int, h: int) -> str:
    if dorsal == 9:
        return "ST"
    if dorsal in (7, 17):
        return "RW"
    if dorsal in (11, 21):
        return "LW"
    r = h % 100
    if r < 40: return "ST"
    if r < 70: return "LW"
    return "RW"


def main():
    files = glob.glob("data/teams/primera/*.json") + glob.glob("data/teams/segunda/*.json")
    total_refined = 0
    per_team = {}
    for fp in files:
        with open(fp, "r", encoding="utf-8") as f:
            team = json.load(f)
        team_refined = 0
        for p in team.get("players", []):
            poss = set(p.get("positions", []))
            if poss not in (GENERIC_DEF, GENERIC_MED, GENERIC_ATQ):
                continue
            dorsal = int(p.get("shirt_number", 0))
            h = stable_hash(p.get("id", "") + p.get("name", ""))
            if poss == GENERIC_DEF:
                slot = pick_def(dorsal, h)
            elif poss == GENERIC_MED:
                slot = pick_med(dorsal, h)
            else:
                slot = pick_atq(dorsal, h)
            p["positions"] = [slot]
            team_refined += 1
        if team_refined > 0:
            per_team[team["short_name"]] = team_refined
            total_refined += team_refined
            with open(fp, "w", encoding="utf-8") as f:
                json.dump(team, f, ensure_ascii=False, indent=2)
    print(f"Refinados: {total_refined} jugadores")
    for short, n in sorted(per_team.items()):
        print(f"  [{short}] {n}")


if __name__ == "__main__":
    main()
