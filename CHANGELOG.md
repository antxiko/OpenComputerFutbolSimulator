# Changelog

Todas las versiones publicadas, qué se hizo y qué queda. Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [v0.3.1] - 2026-05-09

### Añadido — Profundidad del rol mánager (FM-feel)
- **📬 Inbox de mensajes**: nueva vista accesible desde el cuadrante "Seguimiento" del hub con badge de no-leídos. Tipos: `injury`, `press`, `board_message`, `agent_offer`, `transfer_rumor`, `manager_offer`, `coach_award`, `objective`, `national_call`, `general`. Cada mensaje guarda año + jornada + estado leído. Acumula histórico (cap 200 entries). Botón "Marcar todo como leído". Eventos existentes (lesiones graves, premio coach, ofertas mánager, evaluación objetivo) ahora también dejan registro.
- **🎤 Press conferences pre-partido**: 50% prob de modal antes de cada partido del usuario (no jornada 1). 10 plantillas en `data/press_conferences/templates.json` con preguntas filtradas por contexto (`after_win`/`after_loss`/`always`). 3 respuestas por pregunta con efectos en morale plantilla, manager_reputation y board_satisfaction. Solo se aplica el efecto de la PRIMERA respuesta seleccionada.
- **📋 Junta directiva (BoardExpectations)**: generadas al inicio de temporada según reputación del club: posición Liga objetivo (rep ≥90 → top 3, rep <60 → no descender), Copa esperada, ratio finanzas. Evaluación mid-season (jornada 19) y final con verdict `exceeded`/`met`/`missed`/`failed` y delta a manager_reputation (-5 a +3).
- **🚪 Pre-partido bloqueante**: el modal pre-partido ya NO se cierra con ESC (`dialog_close_on_escape = false`, `exclusive = true`). El usuario debe pulsar uno de los 3 botones [▶ Jugar] / [Configurar alineación] / [🎬 Jugar y ver en 2D]. El modal ahora muestra "team news" (lesionados/sancionados) y reputación de mánager + club.
- **⭐ Reputación del mánager** (separada del club): `manager_reputation: int`, persistida en save. Default = `team.reputation` al elegir equipo. Sube con: campeón Liga (+5), Copa (+3), entrenador del mes (+1), eval board exceeded (+3). Baja con: eval board missed (-2) / failed (-5). Se mantiene al cambiar de club por oferta de mánager.

### Archivos
- **NUEVO** `scripts/data/inbox_message.gd` (Resource: type, title, body, read, year_when, jornada_when, data)
- **NUEVO** `scripts/data/board_expectations.gd` (Resource con generate_for_team + summary_text)
- **NUEVO** `data/press_conferences/templates.json` (10 plantillas)
- `scripts/ui/game_hub.gd` — VIEW_INBOX + modales + hooks en _start_season / _on_advance_jornada / _on_reset_season / _accept_manager_offer
- `scripts/core/save_system.gd` — persistir inbox + manager_reputation + board_expectations (defaults tolerantes)

### Calibración intacta
- 2.68 g/p (target ~2.5), 25.08 tiros/p, 21.3% bloqueados ✓, 34.6% a portería ✓, 8.84 córners/p, 0.30 penalties/p con 78% conversión.


## [v0.3.0] - 2026-05-09

### Añadido — gestión y mercado
- **Tracking europeo en histórico de carrera**: cada temporada guarda progreso en Champions, Europa y Conference (Campeón / Subcampeón / Pasó X / Eliminado en X / Fase de grupos). Vista Carrera con 11 columnas.
- **Recuperación parcial de condition entre partidos**: nueva clase `ConditionRecovery`. Antes reset a 100; ahora según días desde el último partido del jugador (1 día → 55, 3 días → 82, ≥5 → 100). Se beneficia de calendario real.
- **Lesiones largas con seguimiento**: heal_after_days usa días reales del calendario (antes hardcoded 7). Modal "🏥 Parte médico" tras la jornada con lesiones graves del usuario, mostrando la fecha estimada de regreso.
- **Reemplazo automático tras vender titular**: si un equipo vende a un jugador con overall ≥75 o que era core de su slot, gana 1 fichaje extra de slot para reemplazarlo en rondas posteriores del mercado.
- **📝 Renovación manual de contratos**: nueva clase `ContractNegotiation`. Al final de temporada, modal que lista todos los jugadores del usuario con contrato vencido. Por jugador: [Renovar] (sub-modal con SpinBox para salario y años, evalúa oferta con probabilidad de aceptación según ratio salario/justo y rango de años por edad; counter-offer si rechazo) o [Liberar] (va al pool de free agents). Los demás clubes siguen flujo automático.
- **💸 Pujas múltiples / contraofertas en mercado**: si el club vendedor rechaza pero la oferta estaba en zona seria (≥70% del MV), emite contraoferta pidiendo +15-25% según cuán cerca quedó. CPU acepta la counter si tiene budget y no excede 1.3x. El usuario ve modal "Contraoferta — pide X€ para aceptar la venta" con botones [Pagar X€] [Rechazar].
- **🔍 Validador automático de plantillas**: nuevo `tools/validate_squads.gd`. Comprueba en los 42 JSON: tamaño de plantilla, cobertura por slot (GK ≥2, DEF ≥6, MID ≥5, ATK ≥4), duplicados de player_id, contratos, edades, posiciones, tiers. Encontró y corrigió 3 contratos vencidos (Carlos Albarrán @ Córdoba, Mario Maroto y Chuki @ Valladolid). 34 plantillas marcadas como "validadas estructuralmente"; 8 hand-curadas conservan su note específico.

### Añadido — motor de partido granular
- **🎬 Eventos granulares**: nuevos tipos `T_PASS`, `T_LONG_BALL`, `T_DRIBBLE`, `T_INTERCEPT`, `T_TACKLE`. `TickResolver._emit_decorative_chain` genera cadenas de pases/regates/intercepciones según el outcome (advance/keep/lose/shot/corner). Usan `state.visual_rng` (RNG separado, seed = seed ^ 0x5A5A5A5A) para no contaminar la calibración del motor.
- **Variedad de jugadas**: `T_CROSS` (centro desde banda — laterales/extremos), `T_TACKLE_FAIL` (regate fallido con caída — 25% de los regates ahora salen mal), `T_TACTICAL_FOUL` (falta táctica del defensor cortando contra peligroso — 30% de las pérdidas en `atk`). El visor dibuja X roja sobre el jugador caído (timer 0.6s) y shake horizontal sobre el que comete falta táctica (timer 0.5s).
- **Set pieces realistas**:
  - **T_PENALTY** (afecta motor): faltas en zona `atk` tienen 3.5% prob de penalty. Conversión modulada por `porteria` del GK + `tiro` del lanzador, centro en 0.82 (porteria=70). Calibrado a **0.30 penalties/partido y 78% conversión** (real La Liga). Tarjeta amarilla automática al fouler.
  - **T_FREE_KICK** (decorativo): tras foul (no penalty) en zona mid/atk, balón al server.
  - **T_THROW_IN** (decorativo): 30% de las pérdidas en `mid` son saques de banda (lateral del defensor saca, balón sube a la línea de banda).
  - **T_GK_DIST** (decorativo): 25% de las pérdidas en `atk` son recogidas del portero.
  - Bug fix latente: `_maybe_foul` ahora captura `initial_zone`/`initial_poss_id` al inicio del tick.
- **Tipos de remate**: `T_HEADER` (60% en córner o tras T_CROSS), `T_VOLLEY` (8% de los pases normales).
- **Defensa granular**: `T_PRESSURE` (25% de los intercepts con segundo defensor presionando), `T_CLEARANCE` (40% de los intercepts en `atk` son despejes), `T_BACK_PASS` (15% de los "keep" en `def` son pase atrás al GK).
- **Movimientos sin balón**: `T_RUN` (30% de los avances mid→atk con desmarque al área, extra_offset 1.5s) y `T_OVERLAP` (20% cuando carrier es lateral, el extremo del mismo lado sobrepasa).
- Sistema de `extra_offsets: Dictionary[player_id, Vector2]` + timers en el visor para movimientos coreografiados temporales sin tocar la formación base.

### Añadido — Camera mode A2 light
- **⭐ Jugador protagonista**: `Lineup.protagonist_id` (solo seteado en el lineup del usuario). En `_pick_actor`/`_pick_assistant` con `role="attack"`, el protagonista recibe +30% peso → más probable shooter/creator. UI: selector encima de la plantilla del equipo del usuario. Visor: anillo amarillo pulsante + nombre sobre el jugador. Persiste en save.

### Visor 2D más fluido
- El balón viaja a la posición exacta del receptor del pase (`_get_player_field_pos` por id), oscila junto al regateador, va al interceptor. `PASS_TRANSIT_TIME=0.28s` (más rápido que el normal 0.55s). Delay reducido al 45% entre granulares. Modo highlights_only los salta. Se rellena el tiempo entre eventos clave con movimiento real del balón.

### Calibración del motor
- Bloqueados al rango real: 26.9% → **20.8%** (real 20-25%). `block_p` base 0.14→0.10.
- Tiros a portería al rango real: 28.2% → **33.6%** (real 32-38%). `on_target_p` base 0.09→0.14.
- Conversión ajustada (`save_p` base 0.30→0.40) para mantener goles ~2.5/p tras subir on-target.
- Stats finales: **2.67 goles/p, 25.5 tiros/p, 8.8 córners/p, 0.30 penalties/p, 78% conversión penalty**.
- Herramientas: `tools/debug_penalties.gd` para verificación específica de penalty.

### Pendiente (v0.4.0+)
- Camera mode A2 full (control directo del jugador con teclado — refactor enorme)
- Mejoras visuales del visor 2D (sprites, animaciones)


## [v0.2.3] - 2026-05-09

### Añadido
- **🎟 Playoff de ascenso de Segunda** (3º-6º): formato La Liga real, semis a 1 partido (3v6 / 4v5) + final. Top 2 ascienden directos, ganador del playoff es el 3er ascenso. Modal con verdict cuando el usuario participa.
- **Calendario filtrado al equipo del usuario**: en lugar de los 380 partidos de la liga completa, ahora muestra solo los 38 del usuario, una línea por jornada con fecha + rival + L/V + estado (jugado/próximo).

### Arreglado
- **Doble ScrollContainer anidado** dejaba en blanco las vistas de Empleados, Calendario, Finanzas y Champions (`content_area` ya estaba en un scroll externo). Eliminado el scroll interno.


## [v0.2.2] - 2026-05-09

### Añadido
- **Calendario REAL con fechas anuales correctas** (días de la semana exactos para 2027, 2028...). Liga arranca último sábado de agosto, distribución vie/sáb/dom/lun. Champions martes/miércoles, Europa/Conference jueves. UI muestra fechas en calendario completo, última jornada y hub central.
- **Hub PC Manager limpio**: tabs antiguas eliminadas SIEMPRE. Sub-vistas con header reducido (botón 🏠 Hub + título dinámico). Footer hub enriquecido (SALIR · GUARDAR · CARGAR · NOTICIAS · ▶ SEGUIR · ▶▶ TEMPORADA · 🔁 NUEVA TEMP). Status bar fina sobre el footer. Toggle Primera/Segunda en el header del hub.
- **👔 Vista Empleados** con organigrama escalonado realista:
  - GRANDE (rep ≥85 + cap ≥50k): ~897 empleados, 87 entradas, 160M€/año
  - MEDIANO (rep 70-84 + cap 25k+): ~478 empleados, 65 entradas, 36M€/año
  - PEQUEÑO (rep <70 o cap <25k): ~190 empleados, 44 entradas, 12M€/año

  Roles repetitivos (acomodadores, jardineros, seguridad, restauración) agrupados con count=N para mantener UI manejable.

### Cambiado
- Empezar nueva partida directo en hub (antes iba a Alineación).
- Botones "Volver al hub" duplicados eliminados (queda solo el del header).


## [v0.2.1] - 2026-05-09

### Arreglado
- **Tabs no se ocultaban encima del hub**: en v0.2.0 el hub se renderizaba pero las tabs antiguas seguían visibles en la parte superior. Ahora `top_header_box`, `div_tabs_box`, `view_tabs_box`, `top_header_separator` se ocultan en modo hub.
- Botón "🏠 Hub" en el header global de sub-vistas para volver fácilmente al dashboard.


## [v0.2.0] - 2026-05-08

### Añadido
- **🏠 Hub principal estilo PC Manager** con 4 cuadrantes (Seguimiento / Entrenador / Mercado / Finanzas), centro con escudo + próximo rival, header con equipo + fecha + jornada, footer con acciones globales.
- **Escudos reales** de los 42 equipos descargados de Wikipedia ES (`assets/logos/<team_id>.png`).
- **🔍 Vista Ver Rival**: cabecera con escudos, datos del rival (estadio, aforo, posición Liga, formación, entrenador) + top 5 jugadores destacados.
- **⚖ Vista Decisiones**: objetivo del club, sponsors actuales con botón buscar nuevo, accesos a histórico de carrera y Champions.
- **Sistema de gestión del club**:
  - Caja real (cash_balance) que sube/baja con ingresos/gastos.
  - Cierre financiero por temporada con desglose: matchday revenue (capacity × occupancy × ticket × 24 partidos), TV, sponsors, premios (Liga 50M campeón, Champions 25M, Copa 8M, etc.) vs salarios, mantenimiento estadio, personal técnico, fichajes.
  - Modal balance fin de temporada con desglose ingresos/gastos.
- **Estadio extendido**: tier 1-5, state 0-100, 7 mejoras (césped, palcos, museo, ampliación capacidad +5000, subir tier, academia premium, gimnasio top).
- **Patrocinadores**: kit_main / kit_sleeve / training / naming, contratos plurianuales, botón "buscar nuevo" por 500K.
- **Cuerpo técnico**: 4 roles (preparador físico, scout, coach cantera, fisio) con calidad 1-5. Salario 200K-5M cada uno. Buffs activos (scout mejora canteranos, fisio reduce lesiones).
- **Mercado consume cash real**: fichajes/ventas afectan caja inmediato.
- **🏅 Premio entrenador del mes** cada 4 jornadas (750K-1.5M).


## [v0.1.x] - 2026-05-08

### Hitos resumidos
- v0.1.0-0.1.7: setup base. Plantilla de 42 equipos con datos reales scrapeados (Wikipedia + Transfermarkt para posiciones), pool internacional de nombres (40% ES + 60% mundo) para canteranos, calibración del motor de partido (2.5 goles/partido, 11 TA + 1 TR top), sistema de tarjetas con sanciones, Copa del Rey + Supercopa Final 4, Champions League (12 europeos ficticios + 4 spanish, grupos + KO), Europa League + Conference (8 teams cada una, KO directo), ofertas de mánager entre temporadas (estilo FM), pre-temporada con 3 amistosos, multi-save con slots nombrados, visor 2D con jugadores móviles + balón animado + tiros, modo highlights, stats por jugador (PJ/G/A), pestañas Finanzas y Calendario, cedidos diferenciados, sistema de objetivos del club por temporada, agentes libres, mercado de invierno, cesiones, Athletic basque-only fix.

Para detalle de cada versión, ver [historial de releases](https://github.com/antxiko/OpenComputerFutbolSimulator/releases).
