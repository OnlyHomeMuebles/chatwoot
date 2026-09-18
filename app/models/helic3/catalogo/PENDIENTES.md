# Catálogos de clasificación — valores pendientes de confirmación

Nota exigida por CAT-01 y actualizada por CAT-02 (criterio 8): lo resuelto por
el addendum del 24/08 salió de esta tabla; lo que sigue abierto queda con su
fuente esperada. La estructura está completa; lo pendiente es DATO.

| Tema | Qué falta | Fuente esperada |
|---|---|---|
| DetalleTipificado | El PDF de asignación habla de 28 detalles "acordados con producción"; el correo del 04/08 entregó 31 (sembrados, literales, erratas incluidas: "Chapilla leventada", "Productos decolorado"). Conciliar cuál lista rige | Producción / Jhan |
| CoberturaCiudad | Confirmar si Palmira y Buenaventura tienen técnico propio: el diseño dice "Eje Cafetero y Valle" y el correo solo nombró Armenia, Manizales, Pereira y Cali (las sembradas) | Operaciones |
| ProcesoGarantia | [P] Confirmar si el **desistimiento del cliente** cuenta también como terminal (hoy se resuelve con la decisión del ítem, no con un proceso). Marcarlo sería una fila más, no código | Only Home / Jhan |
| ProcesoGarantia | El plazo de "Reparación en fábrica" es dinámico (= saldo del presupuesto de 30 días) y por eso queda null: lo calcula PLZ-01. Entrega, devolución y garantía negada no llevan plazo por ser terminales | Resuelto por diseño (insumos Sprint 3) |
| GarantiaItem (futuro) | [P] La ruta alterna cuando el cliente se niega a la recolección (deriva a cambio mano a mano). Se resuelve marcando filas del catálogo cuando se confirme | Only Home / Jhan |
| Parametro | El consecutivo del radicado de garantía (GAR-01) es configurable pero NO se siembra: Only Home no decide si continúa el consecutivo actual o arranca uno nuevo (atado a la migración de histórico, diferida). Claves: `radicado_garantia_prefijo` (unidad texto) y `radicado_garantia_inicio` (unidad cantidad; la lee el trigger al crear la secuencia de la cuenta). Sin configurar: sin prefijo y arranca en 1 | Only Home / Karen |
| Parametro | Los umbrales del semáforo (`umbral_verde`, `umbral_amarillo`) siguen sin valores confirmados; propuesta enviada a Jhan (verde ≥15, amarillo 5–14, rojo <5) | Jhan / Karen |

## Resuelto por el addendum del 24/08 (ya sembrado)

- Los 7 motivos de PQR con categoría, política de garantía (enum de 3 estados)
  y plazo propio del retracto (5 días hábiles).
- Los 7 resultados con sus marcas (cierra_pqr, abre_garantia, aprobacion_humana).
- El reloj legal: solo la etapa "Respondida" detiene el reloj.
- Plazos por tipo: Petición/Queja/Reclamo 15 días hábiles; Sugerencia y
  Felicitación sin plazo legal (null a propósito).
- Origen de ruta por ciudad: con técnico → visita técnica; sin técnico → recolección.
- El mapeo detalle→motivo se ELIMINÓ por diseño (frente A): son ejes
  independientes, el detalle es catálogo autónomo.
- Parámetros de operación: tabla nueva con los 9 valores del addendum.
- El séptimo proceso quedó resuelto por los insumos del Sprint 3 (máquina de
  estados, lista del 19/08): es **"Garantía negada"**, terminal desde el
  dictamen. El supuesto anterior ("Reparación y devolución") se descartó.
- `es_terminal` marcado como dato en los 3 desenlaces finales: entrega del
  producto, devolución de dinero y garantía negada. El cambio de producto NO
  es terminal (termina en la entrega).

## Regla de la semilla desde CAT-02

La semilla solo CREA: si una fila ya existe, no la toca. Después de la
creación, la fuente de verdad son las ediciones hechas por consola (o por la
futura pantalla de administración). Un valor corregido a mano nunca se pierde
por re-ejecutar la semilla.
