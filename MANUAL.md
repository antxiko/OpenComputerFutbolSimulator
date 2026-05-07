# Manual de uso

Guía práctica para abrir, ejecutar y modificar OpenComputerFutbolSimulator.

> Para la visión y la arquitectura del proyecto → [README.md](README.md)
> Para los pendientes y bugs conocidos → [PENDIENTES.md](PENDIENTES.md)

---

## Índice

1. [Requisitos](#1-requisitos)
2. [Primera vez: importar y abrir](#2-primera-vez-importar-y-abrir)
3. [Modo UI: jugar la simulación](#3-modo-ui-jugar-la-simulación)
4. [Modo headless: simulaciones batch](#4-modo-headless-simulaciones-batch)
5. [Editar plantillas de equipos](#5-editar-plantillas-de-equipos)
6. [Generar plantillas vacías](#6-generar-plantillas-vacías)
7. [Reglas del simulador](#7-reglas-del-simulador)
8. [Resolución de problemas](#8-resolución-de-problemas)

---

## 1. Requisitos

- **Godot Engine 4.6.2** (Stable, Win64).
  Descargar desde https://godotengine.org/download
  - Para uso normal con UI: `Godot_v4.6.2-stable_win64.exe`.
  - Para simulaciones por consola: `Godot_v4.6.2-stable_win64_console.exe`.
- (Opcional) Editor de texto para los JSON: VS Code, Sublime, Notepad++, etc.

No hace falta instalar ninguna dependencia: GDScript es nativo de Godot.

## 2. Primera vez: importar y abrir

1. Lanza `Godot_v4.6.2-stable_win64.exe`.
2. En el "Project Manager" pulsa **Import**.
3. Selecciona el archivo `project.godot` de este repositorio.
4. Pulsa **Import & Edit**.
5. Godot escaneará los scripts y registrará las clases globales (`Player`, `Team`, `MatchEngine`, etc.). La primera vez tarda 5-10 segundos.

A partir de aquí, el proyecto aparece en tu Project Manager y puedes abrirlo con un click.

## 3. Modo UI: jugar la simulación

### Lanzar

Con el proyecto abierto en Godot, pulsa **F5** (o el botón ▶ Play arriba a la derecha).

Se abre una ventana 1280×720 con:

- **Top bar**: título, año (`Temporada 2026-2027`), jornada (`Jornada 0 / 38`).
- **Tabs**: Primera / Segunda. *(Segunda placeholder en MVP — solo Primera funcional aún.)*
- **Tabla de clasificación** con código de colores:
  - 🟢 Verde claro: top 4 (puestos Champions).
  - 🔵 Azul claro: 5-6 (puestos Europa).
  - 🔴 Rojo: últimos 3 (descenso).
- **Bottom bar**: status + botones.

### Botones

- **Siguiente jornada**: simula los 10 partidos de la próxima jornada y refresca la tabla.
- **Toda la temporada**: simula las 38 jornadas restantes. La UI se actualiza cada 3 jornadas.
- **Nueva temporada**: avanza el año, aplica aging + retiros + canteranos, y empieza la siguiente liga (sin ascensos/descensos vía UI todavía — se integra cuando tengamos `CareerSimulator` enchufado a la pantalla).

### Limitaciones del MVP

- No se ven los partidos individuales todavía (no hay vista detalle).
- No se puede elegir el lineup manual: todos los equipos juegan con `AutoLineup` (penalización 5% incluida).
- No hay save/load de partida.
- La pestaña Segunda no se simula aún en este MVP de UI.

Estas se irán añadiendo en iteraciones posteriores.

## 4. Modo headless: simulaciones batch

Útil para tests de calibración, simular 20 temporadas, o ejecutar el generador de plantillas.

### Carrera completa de 20 años

1. Edita `project.godot` y cambia:
   ```
   run/main_scene="res://scenes/main.tscn"
   ```
2. Asegúrate de que `scripts/main.gd` tiene `const N_SEASONS := 20`.
3. Ejecuta:
   ```
   "C:\Users\Antxiko\Downloads\Godot_v4.6.2-stable_win64_console.exe" --path . --headless --quit-after 900
   ```
4. La consola va escribiendo una línea por temporada (campeón, pichichi, ascensos, descensos, retiros, canteranos, top fichaje).
5. Al final, resumen histórico: títulos por equipo, top goleadores all-time.

Tiempo aproximado: **10 minutos** para 20 temporadas con Primera + Segunda completas.

### Validar carga de datos

Tras editar JSONs, conviene comprobar que se cargan sin colisiones. Cambia `main.gd` a una versión simple que solo cargue, o usa el modo UI que también valida al arrancar.

### Restaurar UI

Vuelve a poner:
```
run/main_scene="res://scenes/game_hub.tscn"
```

## 5. Editar plantillas de equipos

Cada equipo es un archivo JSON en `data/teams/primera/` o `data/teams/segunda/`.

### Estructura

Ver [data/schemas/team_schema_example.jsonc](data/schemas/team_schema_example.jsonc) para el formato completo y comentado, y [data/schemas/catalogos.md](data/schemas/catalogos.md) para los valores válidos (posiciones, formaciones, traits, etc.).

### Sistema de tiers

Cada jugador tiene `tier` (S/A/B/C/D/Y) y `potential_tier`. Esto determina sus atributos automáticamente vía `PlayerFactory.compute()`. Detalles en [data/schemas/tier_system.md](data/schemas/tier_system.md).

### Edición típica

Cambiar el tier de un jugador, su edad, posición, dorsal, etc.: edita el JSON, guarda, y al lanzar otra vez el proyecto los cambios se aplican (los atributos se recalculan al cargar).

### Verificación

Después de editar, lanza el proyecto. La consola de Godot mostrará errores de carga si hay JSON inválido o IDs duplicados.

## 6. Generar plantillas vacías

Para añadir un equipo nuevo o regenerar uno existente con tiers actualizados:

1. Edita `scripts/tools/generate_team_templates.gd` y añade/modifica una entrada en `TEAM_SPECS`.
2. Si quieres regenerar uno existente, **borra primero su archivo JSON** (el script no sobrescribe).
3. Ejecuta:
   ```
   "C:\Users\Antxiko\Downloads\Godot_v4.6.2-stable_win64_console.exe" --path . --headless --script scripts/tools/generate_team_templates.gd
   ```
4. La consola lista los equipos creados (✓) o respetados (⏭).
5. Reemplaza los nombres placeholder (`<SHORT> Player N`) por nombres reales si quieres.

## 7. Reglas del simulador

Resumen de cómo funciona la simulación. Para detalles completos → código en `scripts/match/simulation/`.

### Motor de partido

- **Granularidad**: por jugadas (cada tick = una posesión, ~25-50 segundos).
- **Zonas**: el campo se divide en `def`/`mid`/`atk` desde el POV del equipo en posesión.
- **Resolución por tick**: probabilidades de avance, mantener, perder, tirar, falta, fuera de juego, córner. Modificadas por la fuerza relativa de los dos equipos en la zona y por las tácticas (mentalidad, pressing, tempo).
- **Tiros**: se resuelven en cadena: ¿bloqueado? → ¿a portería? → ¿parada? → gol o no. El goleador y el asistente se eligen por peso (presencia ofensiva en la zona × overall).
- **Eventos registrados**: gol, tiro fuera, tiro a puerta, parada, falta, amarilla, roja, córner, fuera de juego, sustitución.
- **Determinismo**: cada partido tiene un `seed`. Mismo seed → mismo resultado idéntico.

### Lineup

- Si no eliges manualmente, `AutoLineup` escoge los 11 mejores por slot de la formación. Esto **penaliza un 5%** todos los stats del equipo durante el partido (la "vago tax"). En la UI futura podrás escoger lineup para evitar la penalización.
- Familiaridad de posición: jugar fuera de la posición principal penaliza (1.0 / 0.92 / 0.85 / 0.78 según cuán lejos).

### Mercado de fichajes

- Tras cada temporada, ventana de verano. Cada equipo (excepto Athletic con `signing_policy: basque_only` que no ficha en v1) intenta hasta 3 incorporaciones.
- Cada equipo evalúa sus posiciones más débiles vs media de la liga.
- Valor de mercado: curva exponencial sobre overall × edad × contrato × potencial.
- Probabilidad de venta: depende de importancia para el club, edad, años de contrato, y si el jugador es estrella (overall ≥ 80) o fue fichado recientemente (lealtad).

### Aging y retiros

- Cada año, edad +1.
- Retiros probables: 33 años → 5%, 35 → 20%, 38 → 75%, 40+ → 100%.
- Atributos se re-calculan con la nueva edad: la curva de edad reduce físico/velocidad en veteranos, mantiene mentalidad/pase.

### Cantera

- Si una plantilla queda con menos de 20 jugadores tras retiros/ventas, se generan canteranos automáticamente.
- Su tier es `Y` (juvenil); su potencial depende de la reputación del club (clubes grandes generan más prospectos S/A).

### Reputación dinámica

- Tras cada temporada, la reputación se actualiza según la clasificación: campeón +4, top 4 +2, top 7 +1, mitad ±0, descenso −4. Segunda: campeón +3, ascensos +1/+2, etc. Rango clamp [10, 99].

## 8. Resolución de problemas

### "Could not find type X" al ejecutar por consola

Las clases con `class_name` se registran al importar. Si añades una clase nueva, ejecuta primero:
```
"C:\Users\Antxiko\Downloads\Godot_v4.6.2-stable_win64_console.exe" --path . --headless --import
```

### El proyecto no abre o se queja de algo

Borra la carpeta oculta `.godot/` (cachés) y re-importa. Esto fuerza un escaneo limpio.

### "JSON inválido en X"

Algún archivo en `data/teams/` tiene una coma de más, una llave sin cerrar o un valor inesperado. La consola te dice el archivo. Usa un linter de JSON online (https://jsonlint.com) para localizar.

### "ID de jugador duplicado"

Dos jugadores en distintos equipos comparten el mismo `id`. La convención es `<short>_pNNN`. Asegúrate de que cada equipo usa su prefijo `short_name`.

### El partido siempre acaba 0-0 / hay demasiados goles

Calibración del motor. Variables clave:
- `scripts/match/simulation/tick_resolver.gd`: `FOUL_BASE_PROB`, prob de tiro en zona atk, `on_target_p`, `save_p`.
- `scripts/data/player_factory.gd`: `TIER_BASE`, `POSITION_MODIFIERS`.

Cambia con cuidado y usa el modo headless para validar antes/después con muchas simulaciones.
