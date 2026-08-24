# Catálogos de clasificación — valores pendientes de confirmación

Nota exigida por CAT-01 y actualizada por CAT-02 (criterio 8): lo resuelto por
el addendum del 24/08 salió de esta tabla; lo que sigue abierto queda con su
fuente esperada. La estructura está completa; lo pendiente es DATO.

| Tema | Qué falta | Fuente esperada |
|---|---|---|
| DetalleTipificado | El PDF de asignación habla de 28 detalles "acordados con producción"; el correo del 04/08 entregó 31 (sembrados, literales, erratas incluidas: "Chapilla leventada", "Productos decolorado"). Conciliar cuál lista rige | Producción / Jhan |
| CoberturaCiudad | Confirmar si Palmira y Buenaventura tienen técnico propio: el diseño dice "Eje Cafetero y Valle" y el correo solo nombró Armenia, Manizales, Pereira y Cali (las sembradas) | Operaciones |
| ProcesoGarantia | Plazos de 4 procesos quedaron null a propósito (solo visita 8, recolección 15 y cambio 20 están confirmados): Reparación en fábrica, Entrega de producto, Devolución de dinero, Reparación y devolución | Área de servicio |
| ProcesoGarantia | SUPUESTO DECLARADO: el "séptimo proceso" del addendum se interpretó como "Reparación y devolución" (la etapa que Only Home describió y no estaba sembrada). Confirmar la interpretación | Jhan |

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

## Regla de la semilla desde CAT-02

La semilla solo CREA: si una fila ya existe, no la toca. Después de la
creación, la fuente de verdad son las ediciones hechas por consola (o por la
futura pantalla de administración). Un valor corregido a mano nunca se pierde
por re-ejecutar la semilla.
