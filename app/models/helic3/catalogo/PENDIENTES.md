# Catálogos de clasificación — valores pendientes de confirmación

Nota exigida por la definición de terminado de CAT-01: qué valores de semilla
quedaron pendientes de confirmación por parte de Only Home, para saber cuáles
pueden cambiar. La estructura (tablas, campos, validaciones) está completa;
lo pendiente es únicamente DATO y se resuelve re-ejecutando la semilla.

| Catálogo | Qué falta | Fuente esperada |
|---|---|---|
| MotivoPqr | Los 7 motivos, con su categoría y su marca `abre_garantia`. Sin semilla | Diseño validado / Jhan |
| Resultado | Los 7 resultados, con sus marcas `cierra_pqr` y `abre_garantia`. Sin semilla | Diseño validado / Jhan |
| Tipo | El plazo legal en días hábiles por tipo (`plazo_dias_habiles` quedó null) | Confirmar plazo SIC con el área |
| EtapaPqr | Cuáles etapas detienen el reloj legal (`detiene_reloj` quedó false en todas) | Diseño validado / Jhan |
| MotivoGarantia | Reglas y parámetros de los 3 motivos sin regla (solo Reparación ≤30 y Calidad ≥31 están parametrizados, criterio 7) | Área de servicio |
| DetalleTipificado | (1) La asignación quedó igualada al PDF: 28 detalles "acordados con producción" vs los 31 del correo del 04/08 — conciliar cuál lista rige. (2) El mapeo detalle→motivo es PROVISIONAL por afinidad. (3) Erratas literales del correo conservadas a propósito ("Chapilla leventada", "Productos decolorado") | Producción / área |
| ProcesoGarantia | El PDF habla de 7 procesos; el correo entregó 6 (sembrados). Falta el séptimo y los plazos de los 3 que quedaron null | Diseño validado / Jhan |
| CoberturaCiudad | `origen_ruta` quedó null en todas. Con técnico propio se sembraron las 4 del correo (Armenia, Manizales, Pereira, Cali); el PDF dice "Eje Cafetero y Valle" — confirmar si Palmira y Buenaventura también tienen técnico | Operaciones |

Los nombres del correo se conservan literales, erratas incluidas: corregirlos
sin confirmación del área sería inventar. Todo lo de esta tabla se corrige
como datos (semilla o consola), sin tocar código.
