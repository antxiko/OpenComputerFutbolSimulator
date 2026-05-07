# Backlog / Pendientes

Cosas que sabemos que están a medias o que hay que volver a mirar más adelante. Cada entrada tiene **contexto**, **síntoma observado** y **idea de fix** cuando la hay.

---

## 🔥 Calibración del simulador

### Atleti (rep 88) y otros rep~80-90 placeholder acaban descendidos
- **Contexto**: tras simular 5-12 temporadas, equipos esqueleto con reputación alta (Atleti, Mallorca, Villarreal, Getafe) terminan en Segunda. En la última simulación de 5 años, Atleti y Mallorca cayeron pese a ser top de la liga.
- **Síntoma**: los placeholders generados están "infravalorados" frente a los equipos con datos reales. La distribución de tiers para reputación 80-90 da plantillas más débiles que sus rivales con 22-25 jugadores reales bien afinados.
- **Causa probable**: el generador `tier_band(rep, role, rng)` da `["A","A","B","B","B"]` para starters de un equipo rep 80-89. Eso deja una plantilla con poca cabeza (ningún S). Comparado con datos reales donde un equipo similar tiene 4-5 jugadores tier A bien definidos + traits + overrides, el placeholder pierde.
- **Posibles fixes**:
  - Subir un escalón los tiers para reputación >= 85 (más S/A en la cabeza).
  - Convertir esqueletos a datos reales para los equipos top (ya iniciado para 7 equipos).
  - O cambiar la fórmula de `compute_overall` para que tier promedio pese más en el rendimiento.

### Equipos de Segunda ganando Primera tras 5-10 años
- **Síntoma**: Mirandés, Eibar, Leganés, Andorra ganan Primera tras varias temporadas multi-año.
- **Causa**: tras retiros masivos en años 5+, los equipos top pierden estrellas reales (Lewandowski, Modric ya retirado por edad, etc). Las plantillas convergen a tiers similares basados en cantera y mercado. Con la varianza del simulador, cualquier equipo puede ganar.
- **Idea**: la reputación debería actualizarse con los resultados (campeón gana rep, descendido pierde) y la reputación debería afectar mejor a la calidad de la cantera y a la atracción de fichajes. Hoy es estática y solo afecta a la cantera.

### Lamine Yamal (y similares) entran en bucle de fichajes anuales
- **Síntoma**: en la simulación 12-año, Lamine cambió de equipo cada año desde 2030 (FCB→RSO→ATM→RSO→RMA→FCB→ATM→RMA→ESP).
- **Causa**: tras ser fichado, en su nuevo equipo no es "core" porque hay otros jugadores top en su slot. Eso hace que la probabilidad de venta sea alta el siguiente año.
- **Mejoras aplicadas (2026-05-07)**:
  - Lealtad: `seasons_at_club < 1` → −0.45; `< 3` → −0.25 a la prob de venta.
  - Estrella: overall ≥ 85 → −0.35; ≥ 80 → −0.18.
- **Validar tras la próxima simulación**: que las estrellas se queden 3+ años en su club.

---

## 🚧 Mercado de fichajes — limitaciones de v1

- **Sin agentes libres**: cuando un jugador termina contrato (`until_year` = año actual), no se puede fichar como libre. Hoy se considera que sigue en su club.
- **Sin reemplazo automático**: cuando un equipo vende a su titular, no compra a un sustituto en otra ronda del mismo verano.
- **Sin negociación**: precio = `MarketValue.compute()` exacto. No hay pujas múltiples ni contraofertas.
- **Sin actualización de contratos**: el comprador hereda el contrato del vendedor (años y salario originales). Habría que generar uno nuevo.
- **Athletic no ficha**: política `basque_only` y no tenemos un campo `basque_eligible` en los jugadores rivales para saber si pueden encajar. Athletic solo VENDE, así que se debilita progresivamente. Necesita el sistema de cantera para sostenerse.
- **Sin mercado de invierno**: solo se ejecuta verano una vez por temporada.
- **Sin cesiones**.

---

## 🎯 Datos de equipos

- **Equipos con datos reales (BORRADOR)**: Athletic, Barcelona, Atlético, Real Sociedad, Villarreal, Real Betis, Sevilla. Todos requieren verificación manual de la plantilla 2025-26 real (ver `_draft_note` en cada JSON).
- **Equipos con esqueleto + metadatos reales**: 35 equipos (13 Primera + 22 Segunda). Nombres de jugadores son placeholders (`<SHORT> Player N`).
- **Managers de Segunda**: muchos con `manager_name: "Por confirmar"` porque mi recall era flojo. Verificar con datos reales.
- **`signing_policy: basque_only` para Athletic**: no se aprovecha porque los demás equipos no tienen un campo `basque_eligible` en sus jugadores.

---

## 📐 Modelo de datos / arquitectura

- **Reputación estática**: nunca cambia. Idealmente debería subir con títulos y participación europea, bajar con descensos.
- **Sin tracking de Champions/Europa**: los equipos que clasifiquen a competiciones europeas no aparecen aún.
- **Player.name no se actualiza tras fichaje**: los placeholder players llamados "RMA Player 12" siguen llamándose así aunque jueguen en RSO. Cosmético en placeholders pero sería raro si tuviéramos datos reales y el ID hiciera referencia al equipo de origen.
- **`condition` se reinicia entre jornadas a 100**: simplificación. Lo realista es recuperar parcialmente según días desde último partido.
- **Aging usa `same seed` por jugador**: las stats fluctúan poco año a año (solo por la curva de edad). No hay variación por forma/lesiones.
- **Sin lesiones de larga duración**: las lesiones del partido (cuando se implementen completas) deberían persistir como `Player.injury` con `dias_restantes`.

---

## 🏆 Competiciones que faltan

- **Copa del Rey**: eliminatoria a partido único o doble, con todos los equipos profesionales. No implementada.
- **Supercopa de España**: torneo Final 4 a inicio de temporada (campeón Liga + finalista Copa + campeón Copa + finalista Liga).
- **Champions League / Europa League / Conference**: para los top 4-7 de Primera, planeado para v2.

---

## 🎮 UI

- ✅ **Hub principal** con tabs Primera/Segunda + Clasificación/Última jornada/Plantilla/Mi alineación.
- ✅ **Pre-partido**: configuración persistente de "Mi club" + alineación manual (sin penalización 5%).
- ✅ **Visor 2D del partido v1**: campo cenital, 22 jugadores estáticos en formación, balón que se mueve entre 3 zonas, log de eventos, marcador, controles play/pausa/velocidad.
- ✅ **Save/Load** (un slot "autosave" via JSON en `user://saves/`).

### Visor 2D — limitaciones v1 (a mejorar en v2)
- Los jugadores son estáticos en su posición de formación. Solo el balón se mueve.
- El balón salta entre 3 zonas (def/mid/atk) en lugar de trazar trayectorias suaves.
- Sin animación de tiro, parada, regate, ni reacciones de jugadores.
- Sin sonido.
- Multi-save con varios slots; ahora solo "autosave".

### UI a futuro
- Pantalla de mercado de fichajes (ahora invisible — el mercado se ejecuta en silencio al pulsar "Nueva temporada").
- Pantalla de finanzas, contratos, salarios.
- Pantalla de calendario completo de la temporada (no solo última jornada).
- Vista de histórico de carrera (campeones por año, pichichi, etc.).
- Pre-partido bloqueante (vs configuración persistente actual): que ANTES de cada partido del usuario aparezca un modal con la alineación.
- Multi-save con varios slots y nombres descriptivos.

---

## 📊 Calibraciones secundarias del motor de partido

- **Córners algo bajos** (~6.5 vs ~10 reales). Subir prob de córner en zona atk o convertir más loses en córners.
- **Tiros bloqueados**: actualmente ~10-15% del total. Real ~20-25%. Subir block_p ligeramente.
- **Asistencias**: 65% de los goles tienen asistencia. Realista pero el algoritmo ignora pases largos (CB→ST por encima de la defensa). El asistente actual prioriza CAM/CM pasadores.

---

## 📝 Notas de sesiones

- **2026-05-07 sesión 1**: pipeline JSON → Resource → atributos → motor partido → temporada → mercado → multi-temporada con asc/desc + aging. 5 temporadas en 161s, 20 temporadas en ~10 min. Bug del comparator no-determinista en TransferMarket arreglado.
- **2026-05-07 sesión 2 — calibración**: aplicadas mejoras a `_seller_acceptance_prob` (loyalty <3 años −0.25, estrella overall ≥85 −0.35), añadida `ReputationUpdate.apply_after_season()` (campeón +4, descenso −4), subido tier_band rep ≥92 a `["S","S","A","A","A"]` y rep ≥80 a `["S","A","A","B","B"]`. Real Madrid placeholder regenerado. Atleti: Oblak y Griezmann subidos a S tier.
  - **Resultado test 5 años**: Real Madrid 4/5 títulos (vs 8/20 = 40% antes), Atleti se queda en Primera (antes descendía), Lamine Yamal solo se movió 1 vez (vs cada año antes).
  - **Sigue pendiente**: Athletic, Mallorca, Betis, Villarreal, Valencia con datos reales descienden tras 5-10 años. Problema estructural: sus jugadores top retiran con edad y la cantera no compensa lo suficiente. Necesita más buff de cantera por reputación o canteranos "estrella" en top clubes con datos reales.
- **2026-05-07 sesión 2 — re-validación 20 temporadas (v2)**: simuladas 20 temporadas con todas las mejoras. Tiempo 616.8s.
  - **Madrid 4 títulos** (vs 8 antes), **Girona 4**, Celta 3, Barça 3, Osasuna 2 — distribución mucho más sana.
  - **Atleti se mantiene en Primera** al final (antes descendía). Mejora confirmada por Oblak/Griezmann S + tier_band rep≥92 reforzado + reputación dinámica.
  - **Athletic sigue descendiendo** — la política `basque_only` sin sistema de cantera vasca robusta condena al club. Pendiente: marcar canteranos como `basque_eligible` cuando se generen para Athletic, o crear pool de jugadores libres vascos para que pueda contratar.
  - Lamine Yamal redujo cycling: 7 transferencias en 16 años (vs cada año antes). Pasaba 2-3 temporadas por club.
  - Top goleador all-time: placeholder RMA 191 goles tras 20 temporadas. Realista para una carrera larga.
