# Siembra de catálogos, parámetros y agentes (SIE-01)

Cómo Helic3 deja los datos base (catálogos de clasificación, parámetros de
operación y agentes de IA) listos en **toda cuenta**, tanto en local como en
producción, sin pasos manuales y sin pisar lo que se haya editado a mano.

## Por qué por migración y no por rake

En producción la base **ya existe**, así que el arranque (`deployment/start.sh`)
solo corre `db:migrate`; **no** re-ejecuta `db:seed` (`db:chatwoot_prepare` no
vuelve a sembrar). Por eso la siembra vive en una **migración idempotente** y no
en una tarea rake de consola: así entra sola en cada despliegue, queda registrada
en el log y no depende de que alguien se acuerde de correrla.

- Migración: [`db/migrate/20261002120000_siembra_helic3_catalogos_y_agentes.rb`](../../db/migrate/20261002120000_siembra_helic3_catalogos_y_agentes.rb)
- Reutiliza los dos seeders reales:
  - `Helic3::Catalogo::SeederService` — catálogos + parámetros.
  - `Helic3::Agents::SeederService` — agentes de sistema.

La migración recorre `Account.find_each` y, por cada cuenta, llama primero al
seeder de catálogos (siembra el parámetro `agentes_desde_bd=false`) y luego al de
agentes. Imprime un resumen por cuenta con `say`, que queda como evidencia en el
log del despliegue.

## Idempotencia: la semilla solo CREA

La llave natural es **por cuenta**:

- catálogos y agentes → `(account, codigo)`
- parámetros → `(account, clave)`

Si la fila ya existe, la semilla **no la toca**. Después de crearse, la fuente de
verdad son las ediciones hechas desde la consola (o la pantalla de administración).
Un valor corregido a mano **nunca se pierde** por re-ejecutar la siembra, y el
índice único de cada tabla es la red de seguridad final. (Ver también la "Regla de
la semilla" en [`app/models/helic3/catalogo/PENDIENTES.md`](../../app/models/helic3/catalogo/PENDIENTES.md).)

Correr `up` dos veces no cambia los conteos (criterio de aceptación 3).

## El `down` no revierte

`db:rollback` **no borra** lo sembrado (criterio de aceptación 9): las filas
pueden estar referenciadas por expedientes reales y pudieron editarse desde el
panel. Revertir borraría datos de verdad, así que el `down` es un no-op que solo
deja una nota en el log.

## Guardas contra arranques frágiles

La migración corre junto a otras del mismo despliegue, así que los seeders se
protegen de estados a medias:

- **`tabla_lista?(modelo)`** — si la tabla del catálogo aún no existe (una
  migración posterior la crea), ese bloque de siembra se salta en vez de reventar.
- **`reset_column_information`** — una migración anterior del mismo despliegue pudo
  agregar columnas; se limpia el cache de columnas para crear las filas con el
  esquema real y no con el cacheado al cargar la clase.
- **`puede_sembrar_agente?`** (en el seeder de agentes) — no crea un agente de
  sistema si ya existe uno para la cuenta con otro código.

Un error **no previsto** sí debe parar el despliegue y verse: por eso la migración
no atrapa excepciones genéricas.

## Convención de orden de las migraciones (IMPORTANTE)

> Si una migración **cambia el esquema** del que depende la siembra, su timestamp
> tiene que ser **ANTERIOR** al de esta migración (`20261002120000`).

Ejemplo real: PRM (PR #108) cambia la columna `valor` de los parámetros a `text`
para que quepan los mensajes largos de Karen. Esa migración lleva timestamp
`20261002110000` **a propósito** — corre **antes** de la siembra `...120000`. Si
corriera después, la siembra intentaría meter textos largos en una columna `string`
(límite 255) y fallaría el despliegue.

Regla práctica al agregar una migración nueva relacionada con catálogos/parámetros:
- ¿**Cambia el esquema** (columna, tipo, índice) que la siembra necesita? → timestamp **menor** que `...120000`.
- ¿Solo **agrega más datos** a sembrar? → va en las constantes del seeder
  (`PARAMETROS`, `CATEGORIAS`, …); el conteo de los specs usa `.size`, no un número
  fijo, para no romperse cuando la lista crece.

## Dónde van los valores de negocio

Nunca en el código ni en el prompt del agente: van en las **constantes de datos**
del seeder (`Helic3::Catalogo::SeederService` y `Helic3::Agents::SeederService`),
que son las que la migración siembra. Los textos del área se conservan **literales**
(incluidas erratas) salvo confirmación explícita. Lo que sigue sin confirmar queda
anotado en los `PENDIENTES.md` de catálogos y de agentes.

## Verificar

```bash
# conteos esperados por cuenta (ajusta la cuenta):
#   Categoria 6, MotivoPqr 7, Parametro = SeederService::PARAMETROS.size, Agente 5
docker compose exec -e RAILS_ENV=test rails \
  bundle exec rspec spec/helic3/db/migrate/siembra_helic3_catalogos_y_agentes_spec.rb
```

> Recordatorio: los specs de este repo se corren **siempre** con `-e RAILS_ENV=test`;
> sin eso usan la base/entorno de desarrollo y dan fallas falsas.
