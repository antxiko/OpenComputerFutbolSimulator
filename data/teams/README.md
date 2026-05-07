# Captura de datos de equipos

## Estado de la captura

**Total: 42/42 equipos cargables** (20 Primera + 22 Segunda) — 1033 jugadores. Cero colisiones de IDs.

### Primera (20/20 cargables)

Con datos reales de jugadores (BORRADOR — verificar):
- [x] athletic_club  *(Athletic, 24 jugadores reales)*
- [x] fc_barcelona  *(verificar Rashford préstamo, Szczęsny)*
- [x] atletico_madrid  *(verificar fichajes 2025)*
- [x] real_sociedad  *(verificar Zubimendi, Imanol)*
- [x] villarreal_cf  *(verificar veteranos retirados)*
- [x] real_betis  *(verificar Antony, Cucho)*
- [x] sevilla_fc  *(alta rotación; verificar plantilla y entrenador)*

Con metadatos reales + jugadores placeholder (esqueleto):
- [~] real_madrid  *(esqueleto)*
- [~] valencia_cf  *(esqueleto)*
- [~] girona_fc  *(esqueleto)*
- [~] ca_osasuna  *(esqueleto)*
- [~] rayo_vallecano  *(esqueleto)*
- [~] celta_vigo  *(esqueleto)*
- [~] rcd_mallorca  *(esqueleto)*
- [~] getafe_cf  *(esqueleto)*
- [~] deportivo_alaves  *(esqueleto)*
- [~] rcd_espanyol  *(esqueleto)*
- [~] levante_ud  *(esqueleto, ascendido)*
- [~] elche_cf  *(esqueleto, ascendido)*
- [~] real_oviedo  *(esqueleto, ascendido)*

### Segunda (22/22 cargables, todos esqueleto)

Lista basada en mi mejor estimación para 2025-26 — la composición real puede variar:
- [~] real_valladolid (descendido 24-25)
- [~] ud_las_palmas (descendido 24-25)
- [~] cd_leganes (descendido 24-25)
- [~] real_sporting (Sporting de Gijón)
- [~] real_zaragoza
- [~] granada_cf
- [~] ud_almeria
- [~] sd_eibar
- [~] burgos_cf
- [~] fc_cartagena
- [~] cadiz_cf
- [~] cd_tenerife
- [~] albacete_balompie
- [~] cd_mirandes
- [~] cd_castellon
- [~] cd_eldense
- [~] malaga_cf
- [~] sd_huesca
- [~] cordoba_cf
- [~] racing_santander
- [~] ad_ceuta
- [~] fc_andorra

Para los esqueletos, los `manager_name` están como `"Por confirmar"` cuando no estaba seguro.

## Leyenda

- **[x]** = JSON con jugadores reales (BORRADOR — verificar).
- **[~]** = JSON con metadatos del club reales (estadio, ciudad, fundación, colores) pero **plantilla de placeholder** (`<SHORT> Player N`). Listo para simulación; afina los nombres cuando quieras.

## Cómo capturar/afinar un equipo

1. Abre el JSON correspondiente.
2. Reemplaza placeholder players (`<SHORT> Player N`) por nombres reales.
3. Ajusta el `tier` y `potential_tier` cuando convenga.
4. Si añades/quitas jugadores, mantén la convención de `id`: `<short>_pNNN`.
5. Marca como `[x]` en este README cuando lo des por capturado.

## Por jugador necesitas

Lo **imprescindible**:
- `id` (convención `<team_short>_p<NNN>`)
- `name`, `birth_date`, `nationality`, `positions`, `preferred_foot`
- `tier` (S/A/B/C/D/Y) y `potential_tier`
- `shirt_number`, `joined_year`
- `contract.until_year`, `contract.salary_eur_year`

Lo **opcional**:
- `traits` (lista, puede ser `[]`)
- `overrides` (diccionario, puede ser `{}`)
- `captain` (default false)
- `contract.release_clause_eur` (cláusula)

## Convenciones

- **Posiciones**: `GK / CB / LB / RB / LWB / RWB / CDM / CM / CAM / LM / RM / LW / RW / CF / ST`
- **Pie**: `L` izquierdo, `R` derecho, `B` ambidiestro
- **Nacionalidad**: ISO 3166 alpha-2 (`ES`, `BR`, `FR`, `AR`, `MA`…). Para Inglaterra/Escocia/Gales usa `GB-ENG`, `GB-SCT`, `GB-WLS`.
- **Tiers**: véase `data/schemas/tier_system.md`.

## Re-generar esqueletos

El script `scripts/tools/generate_team_templates.gd` **respeta los archivos existentes** (no sobrescribe). Para regenerar uno hay que borrarlo primero. Para añadir un equipo nuevo, edita `TEAM_SPECS` en ese mismo archivo y ejecuta:

```
"C:\Users\Antxiko\Downloads\Godot_v4.6.2-stable_win64_console.exe" --path . --headless --script scripts/tools/generate_team_templates.gd
```
