# OpenComputerFutbolSimulator

> Simulador de fútbol híbrido (manager + motor de partido 2D) de **La Liga española** hecho en **Godot 4.6.2 / GDScript**. Simula carreras de **20 temporadas** con Primera (20 equipos) y Segunda (22 equipos).

---

## Visión

OpenComputerFutbolSimulator quiere ser un simulador de fútbol con **alma de manager clásico** (PC Fútbol, Football Manager) pero con un **motor de partido visualizable** estilo top-down 2D. La idea es:

- **Tú gestionas un club**: tácticas, alineaciones, mercado de fichajes, cantera.
- **La máquina simula el resto**: partidos por jugadas, decisiones de la IA de los otros 41 clubes, ascensos/descensos, retiros, regens.
- **20 temporadas** desde el presente (2026 → 2046). Los jugadores envejecen, se retiran, y la cantera produce nuevas estrellas. Las ligas tienen vida propia: descensos rotan equipos, los grandes pierden su hegemonía si no se modernizan, los pequeños pueden dar la sorpresa.

El proyecto es **uso personal** — los nombres de equipos y jugadores se introducen manualmente o se editan en JSON, no se distribuyen datos protegidos.

## Estado del proyecto

> **v0.1.0 — primer release jugable end-to-end.**

| Bloque | Estado |
|--------|--------|
| Carga de datos JSON → Resources Godot | ✅ |
| Atributos de jugador con sistema de tiers + curva de edad | ✅ |
| Posiciones reales de jugadores (Transfermarkt 25-26) | ✅ 89% específicas |
| Pool internacional de nombres para canteranos | ✅ 40% ES + 60% mundo |
| Motor de partido por jugadas (3 zonas) | ✅ determinista, calibrado |
| Sistema de tarjetas + sanciones + agresividad | ✅ |
| Liga: calendario round-robin + tabla con tiebreakers | ✅ |
| Mercado de fichajes (valor, retención, lealtad, cláusulas) | ✅ v1 |
| Aging + retiros + cantera automática | ✅ |
| Ascensos/descensos + reputación dinámica | ✅ |
| Multi-temporada (20 años) | ✅ ~10 min |
| **UI completa** (hub con tabs Liga/Plantilla/Mercado/Carrera/Champions) | ✅ |
| Save/Load **multi-slot** con nombres descriptivos | ✅ |
| Visor 2D del partido (jugadores móviles, balón animado, tiros) | ✅ |
| Copa del Rey + Supercopa Final 4 | ✅ |
| 🏆 Champions League (12 europeos + 4 spanish, grupos + KO) | ✅ |
| 📨 Ofertas de cambio de club entre temporadas (estilo FM) | ✅ |
| 🟢 Pre-temporada con 3 amistosos | ✅ |
| Europa League / Conference | ⏳ v2 |
| Camera modes (control directo, highlights) | ⏳ v2 |

Una temporada completa de Primera (380 partidos) tarda ~13 segundos en headless. Las 20 temporadas con Segunda incluida (842 partidos × 20) tardan ~10 minutos.

Para ver los pendientes detallados → [PENDIENTES.md](PENDIENTES.md).

## Decisiones de diseño

- **Híbrido manager + motor visual**: capa de manager + simulación 2D abstracta. La arquitectura está preparada para añadir control directo de jugador y modo highlights más adelante sin reescribir el motor.
- **Atributos data-driven** (8 atributos: ataque, defensa, pase, tiro, físico, portería, mentalidad, velocidad). Almacenados como `Dictionary` para ser extensibles.
- **Sistema de tiers** (S/A/B/C/D/Y) para evitar capturar 8 atributos por jugador. Un jugador se define por `tier + position + age + overrides`, y el motor genera atributos coherentes.
- **Determinismo**: cada partido tiene un `seed`. Mismo seed → mismo resultado exacto. Útil para debugging y reproducibilidad.
- **Datos en JSON editables**: cada equipo es un archivo en `data/teams/{primera,segunda}/`. Editable a mano con cualquier editor.
- **Idempotencia del generador**: el script `generate_team_templates.gd` no sobrescribe archivos existentes (puedes regenerar uno borrándolo primero).

## Arquitectura

```
data/
  teams/{primera,segunda}/    JSON por equipo (uno por club)
  schemas/                    Documentación del formato JSON + sistema de tiers
  name_pools/                 Pools de nombres para regens (a poblar)
  calendar/                   Plantillas de calendario por temporada (futuro)

scripts/
  data/                       Resources tipados: Player, Team, ContractInfo, ...
                              + PlayerFactory (tier → atributos con curva de edad)
  core/                       DataLoader (lee JSON, valida, instancia Resources)
  match/simulation/           Motor de partido:
                                MatchEngine (orquesta), TickResolver (resuelve jugada),
                                MatchState, Lineup, AutoLineup, MatchEvent, MatchResult,
                                PositionContribution (tabla de aporte por posición×zona)
  competitions/               CalendarGenerator (round-robin), LeagueTable (con tiebreakers),
                              SeasonSimulator, PromotionRelegation
  transfers/                  TransferMarket + MarketValue (curva exponencial)
  progression/                Aging (retiros y curvas), Cantera (canteranos automáticos),
                              ReputationUpdate (rep dinámica)
  career/                     CareerSimulator (bucle multi-temporada)
  tools/                      generate_team_templates (script standalone)
  ui/                         GameHub (pantalla principal — MVP)
  main.gd                     Entry point alternativo para tests headless

scenes/
  game_hub.tscn               Escena principal de UI
  main.tscn                   Escena legacy de tests headless
```

### Diagrama de flujo de una carrera

```
DataLoader.load_all_teams()
    └─→ Teams[42] con 1033 jugadores y atributos generados

CareerSimulator.run(N_seasons):
    for year in 1..N:
        ┌─ SeasonSimulator.simulate_season(primera) ─┐
        │   CalendarGenerator → 38 jornadas         │
        │   for each fixture: MatchEngine.simulate  │
        │       └─ TickResolver loop (~100 ticks)   │
        │   acumula LeagueTable + scorers           │
        └────────────────────────────────────────────┘
        ReputationUpdate.apply_after_season()
        PromotionRelegation.apply()  → ascensos/descensos
        Aging.age_all() → retiros + nuevos atributos
        Cantera.fill_squad_if_needed() → canteranos
        TransferMarket.run() → ventana de verano
```

## Cómo ejecutar

### Releases pre-compiladas (recomendado)

Cada release del repo (etiquetas `v*`) trae binarios listos para ejecutar — no necesitas Godot.

- **Windows**: descomprime `OpenComputerFutbolSimulator-windows-x86_64.zip` y ejecuta `OpenComputerFutbolSimulator.exe`.
- **Linux**: `tar -xzf OpenComputerFutbolSimulator-linux-x86_64.tar.gz && ./OpenComputerFutbolSimulator.x86_64`.
- **macOS**: descomprime `OpenComputerFutbolSimulator-macos-universal.zip` y ejecuta `OpenComputerFutbolSimulator.app`. Si macOS bloquea el binario por "desarrollador no identificado", click derecho → Abrir → Confirmar.

Ver [releases](https://github.com/antxiko/OpenComputerFutbolSimulator/releases).

### Cómo se generan las releases

Push de un tag `vX.Y.Z` dispara el workflow `.github/workflows/release.yml` que:
1. Lanza 3 jobs paralelos (Windows / Linux / Mac) en contenedor `barichello/godot-ci:4.6.2`.
2. Cada job exporta usando los presets de `export_presets.cfg`.
3. Empaqueta y crea release de GitHub con los 3 binarios adjuntos.

```bash
# Crear release v0.1.0
git tag -a v0.1.0 -m "Release 0.1.0"
git push origin v0.1.0
# Esperar ~5-10 min para que el workflow termine.
```

### Modo dev (con Godot)

Requisitos: **Godot 4.6.2** stable. Descarga: https://godotengine.org/download

### Modo UI (Iteración actual)

1. Abrir Godot 4.6.2 → **Import** → seleccionar `project.godot` de este directorio.
2. Pulsar **F5** (Play project).
3. Verás la pantalla principal con la tabla de Primera vacía. Pulsa **"Toda la temporada"** y se simulan los 380 partidos.
4. Tras finalizar, pulsa **"Nueva temporada"** para envejecer plantillas y empezar otra (sin asc/desc todavía en UI; eso se integra en próxima iteración).

### Modo headless (validación de simulación + carrera 20 años)

```bash
# Importar (primera vez)
"C:\Users\Antxiko\Downloads\Godot_v4.6.2-stable_win64_console.exe" --path . --headless --import

# Para simulación batch, cambia main_scene en project.godot a "res://scenes/main.tscn"
# y luego:
"C:\Users\Antxiko\Downloads\Godot_v4.6.2-stable_win64_console.exe" --path . --headless --quit-after 900
```

### Generar nuevos esqueletos de equipos

```bash
"C:\Users\Antxiko\Downloads\Godot_v4.6.2-stable_win64_console.exe" --path . --headless --script scripts/tools/generate_team_templates.gd
```

El script no sobrescribe archivos existentes — borra el JSON primero si quieres regenerar.

## Datos de equipos

42 equipos cargables en total:

- **7 equipos con datos reales BORRADOR (2025-26)**: Athletic Club, FC Barcelona, Atlético Madrid, Real Sociedad, Villarreal CF, Real Betis, Sevilla FC.
- **35 equipos con metadatos reales + plantilla placeholder**: el resto de Primera (Real Madrid, Valencia, Girona, Osasuna, etc.) y los 22 equipos de Segunda.

Los archivos están marcados con `_draft_note` cuando son borrador, indicando qué cosas verificar (fichajes recientes, lesionados, nombres de entrenadores no confirmados).

Detalles de captura, convenciones, y cómo añadir/editar plantillas → [data/teams/README.md](data/teams/README.md).

## Roadmap

**v1.0 — fundamentos** (en curso, ~80% completo):
- ✅ Motor de partido y temporada.
- ✅ Mercado de fichajes y aging.
- ✅ Multi-temporada con asc/desc.
- ⚙️ UI básica (tabla + simulación). Pendiente: tabs Primera/Segunda, vista de partido, vista de plantilla.

**v1.1 — UX**:
- Pantalla pre-partido para escoger lineup manual (evitar la `auto_picked` penalty).
- Vista de partido con eventos cronológicos y estadísticas.
- Pantalla de plantilla, calendario, mercado.
- Sistema de save / load.

**v2.0 — competiciones**:
- Copa del Rey, Supercopa de España.
- Champions League / Europa League / Conference League para los top-7 de Primera.
- Mercado de invierno.

**v2.1 — visor 2D de partido**:
- Visualización top-down del partido con jugadores como puntos.
- Modo "ver highlights" que reproduce solo las jugadas clave.

**v3.0 — control directo**:
- Modo PC Fútbol clásico: poder controlar a un jugador en el campo.

## Licencia y atribuciones

- **Código**: licencia abierta a definir (ver [LICENSE](LICENSE)).
- **Datos**: este proyecto incluye nombres de jugadores y equipos de La Liga española. Es **uso personal y no comercial**. Los nombres de clubes, jugadores, estadios, y similares pertenecen a sus respectivos titulares de derechos. Esta repo no incluye logos, escudos, fotografías, ni audio. Los datos se usan únicamente para identificación dentro de la simulación, en el marco de un proyecto educativo y personal.
- **Godot Engine**: MIT License — https://godotengine.org

## Autor

Antxiko — antxiko@gmail.com

Proyecto personal en colaboración con Claude (Anthropic).
