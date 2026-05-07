# Catálogos de valores válidos

Referencia rápida de strings válidos para los JSON.

## `positions`

| Sigla | Posición | Notas |
|-------|----------|-------|
| `GK`  | Portero | |
| `CB`  | Central | |
| `LB`  | Lateral izquierdo | |
| `RB`  | Lateral derecho | |
| `LWB` | Carrilero izquierdo | Defensa muy ofensivo, en formaciones con 3 atrás |
| `RWB` | Carrilero derecho | |
| `CDM` | Mediocentro defensivo | "5" |
| `CM`  | Mediocentro | "8" |
| `CAM` | Mediapunta | "10" |
| `LM`  | Mediocampista izquierdo | |
| `RM`  | Mediocampista derecho | |
| `LW`  | Extremo izquierdo | |
| `RW`  | Extremo derecho | |
| `CF`  | Segundo delantero / falso 9 | |
| `ST`  | Delantero centro | "9" |

## `preferred_foot`

`L` | `R` | `B` (ambidiestro)

## `nationality`

ISO 3166 alpha-2. Casos especiales del fútbol:
- `GB-ENG` Inglaterra
- `GB-SCT` Escocia
- `GB-WLS` Gales
- `GB-NIR` Irlanda del Norte

## `tier` y `potential_tier`

`S` | `A` | `B` | `C` | `D` | `Y` (ver `tier_system.md`)

## `formation`

Strings reconocidos por el motor (catálogo inicial; ampliable):
`4-3-3` | `4-2-3-1` | `4-4-2` | `4-3-1-2` | `3-5-2` | `3-4-3` | `5-3-2` | `5-4-1` | `4-1-4-1`

## `mentality`

`muy_defensivo` | `defensivo` | `equilibrado` | `ofensivo` | `muy_ofensivo`

## `tempo`

`lento` | `normal` | `rapido`

## `pressing`

`bajo` | `medio` | `alto`

## `width`

`estrecho` | `normal` | `ancho`

## `preferred_style` (manager)

`posesion` | `directo` | `contraataque` | `presion` | `equilibrado`

## `signing_policy` (equipo)

| Valor | Significado |
|-------|-------------|
| `open` | (Default) Puede fichar a cualquier jugador. |
| `basque_only` | Solo jugadores nacidos o formados en el País Vasco/Navarra/Iparralde. Athletic Club. La lógica concreta (qué cuenta como "vasco") se define en el módulo de fichajes; en datos basta con que los jugadores tengan trait `basque` o nacionalidad `ES` con `region_origin` vasca cuando llegue el momento de implementarlo. |

## `traits` (catálogo inicial; ampliable)

Categorías y ejemplos. Lista no exhaustiva — se irá ampliando según hagan falta:

**Físico**
- `pace` — explosividad
- `aerial_strong` — gran juego aéreo
- `stamina` — resistencia superior

**Técnico**
- `dribbling` — regate por encima de la media
- `passing_accurate` — precisión de pase superior
- `long_passes` — gran pase largo
- `long_shots` — disparo lejano
- `finishing` — definición clínica
- `set_pieces` — especialista a balón parado
- `long_throw` — saque de banda largo
- `skill_moves` — filigranas / 1v1 ofensivo

**Mental**
- `leader` — capitán natural / vestuario
- `aggressive` — combativo
- `big_game_player` — rinde en partidos grandes
- `late_runs` — llegadas desde segunda línea
- `tackling` — gran entrada limpia
