# Sistema de tiers de jugador

Para no capturar a mano 8 atributos por jugador (×~1050 jugadores), cada jugador tiene un **tier** que un script convierte en los atributos concretos.

## Tiers

| Tier | Significado | Rango overall esperado | Ejemplos típicos |
|------|-------------|------------------------|------------------|
| `S` | Élite mundial, top 20 del fútbol mundial | 88–95 | Mbappé, Bellingham, Lewandowski |
| `A` | Top de La Liga, internacional habitual | 82–87 | Pedri, Vinicius, Griezmann |
| `B` | Titular indiscutible en equipo grande / referencia en equipo medio | 76–81 | Carvajal, Iñaki Williams, Oyarzabal |
| `C` | Titular en equipo modesto / suplente fiable en equipo grande | 70–75 | Mayoría de plantilla |
| `D` | Suplente largo, squad filler, descarte | 62–69 | Tercer portero, juveniles del filial sin minutos |
| `Y` | Cantera / promesa joven (overall actual bajo, **`potential_tier` alto**) | 55–70 actual | Jóvenes 16-19 años con proyección |

## Cómo se traducen a atributos

Pseudocódigo del generador (se implementa en `scripts/data/player_factory.gd`):

```
overall_base = aleatorio_dentro_de_rango_del_tier(tier, seed)

# Bonus posicional: cada posición tiene un perfil de atributos
# (un central potencia defensa/físico/aéreo, un delantero potencia tiro/velocidad...)
perfil = perfiles_por_posicion[posicion_principal]

para cada atributo:
    atributo[i] = overall_base + perfil[i] + ruido_pequeño(seed)
    aplicar_curva_de_edad(atributo[i], edad)

aplicar_overrides(atributo, overrides)  # si hay ajustes manuales, mandan
```

## Curva de edad (resumida)

- **15–17**: muy verde, atributos limitados por techo de "potencial_actual" (regresión hacia el tier joven).
- **18–22**: progresión rápida hacia el potencial.
- **23–28**: pico de carrera, valor cercano al `potential_tier`.
- **29–32**: meseta con ligero declive físico (velocidad y físico bajan más).
- **33+**: declive acelerado en físicos; mentalidad/pase aguantan.
- **35+**: probabilidad creciente de retiro al final de cada temporada.

## Atributos B2 (extensibles)

```
ataque       capacidad ofensiva general (movilidad, finalización situacional)
defensa      capacidad defensiva general (entradas, posicionamiento)
pase         pase corto y largo, visión
tiro         disparo a portería, definición
fisico       fuerza, resistencia, juego aéreo, salto
porteria     reflejos, estiradas, juego con manos (solo relevante en GK)
mentalidad   compostura, liderazgo, decisión, regularidad
velocidad    aceleración + velocidad punta
```

Añadir atributos en el futuro = ampliar el diccionario y los perfiles posicionales. El motor lee atributos por nombre, no por índice.

## `overrides`

Cuando un jugador no encaja limpiamente:
- **Vinicius** podría ser tier A pero con velocidad sobresaliente → `"overrides": { "velocidad": 95 }`.
- **Modrić** veterano podría ser tier A con físico bajado por edad → ya lo aplica la curva de edad, no hace falta override.
- **Courtois** portero, no tiene sentido aplicarle el perfil de jugador de campo → su atributo `porteria` sale del tier directamente; los demás se le ponen bajos por su posición.

Usa `overrides` con moderación, solo cuando el resultado del generador "se vea raro".
