"""Test rápido del parser de plantilla — vemos qué saca para Real Madrid."""
import requests
from bs4 import BeautifulSoup
import sys

URL = "https://es.wikipedia.org/wiki/Real_Madrid_Club_de_F%C3%BAtbol"


def main():
    r = requests.get(URL, headers={"User-Agent": "OCFS-personal-use/0.1 (educational)"})
    r.raise_for_status()
    r.encoding = "utf-8"
    soup = BeautifulSoup(r.text, "html.parser")

    # Localizar heading con texto "Plantilla"
    heading = None
    for h in soup.find_all(["h2", "h3"]):
        if h.get_text(strip=True).startswith("Plantilla"):
            heading = h
            break
    if heading is None:
        print("No heading 'Plantilla' encontrado")
        sys.exit(1)
    print(f"Heading: {heading.get_text(strip=True)}")

    table = heading.find_next("table", class_="toccolours")
    if table is None:
        print("No table.toccolours después del heading")
        sys.exit(1)

    # Strategy: each row of the squad has cells like
    #   | dorsal | bandera+pais | (license img) | POR/DEF/MED/DEL | nombre | (img) | edad | proc | contrato | internacional
    # The role string ("Porteros", "Defensas", "Centrocampistas", "Delanteros") aparece como un th/td single-cell.
    current_role_section = None
    rows = table.find_all("tr")
    print(f"Filas en la tabla: {len(rows)}")

    for i, row in enumerate(rows[:50]):
        cells = row.find_all(["th", "td"])
        texts = [c.get_text(" ", strip=True) for c in cells]
        # Si hay solo 1 celda con texto, es un encabezado de sección
        if len(cells) == 1:
            print(f"  [section?] {texts[0][:60]}")
            continue
        if len(cells) < 4:
            print(f"  [skip {len(cells)} celdas]")
            continue
        print(f"  row {i}: ", "|".join(t[:20] for t in texts))


if __name__ == "__main__":
    main()
