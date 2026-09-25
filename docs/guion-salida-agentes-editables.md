# Guion de salida — Agentes editables (Helic3 / H3A-16)

Este documento es el **runbook de despliegue y de vuelta atrás** del módulo de
agentes editables (H3A). Cubre el criterio 2 y 3 de H3A-16:

- **Criterio 2:** procedimiento escrito para volver atrás en **menos de 5 minutos**.
- **Criterio 3:** cada paso nombra **quién lo ejecuta** y **en qué orden**.

La regresión de comportamiento (criterio 1) la cubre el spec
`spec/services/helic3/agents/regresion_bandera_spec.rb` (paridad bandera
apagada vs. encendida) más `catalogo/seeder_service_spec.rb` (paridad del prompt).

---

## 1. Idea clave: el interruptor de seguridad

Todo el módulo cuelga de **una bandera por cuenta**: el parámetro
`agentes_desde_bd` (`Helic3::Catalogo::Parametro`), **apagada por defecto**.

- **Apagada** → el runner arma los agentes desde las **clases** de siempre
  (`RunnerService#construir_desde_clases`). Es el comportamiento de producción
  actual, sin ningún riesgo nuevo.
- **Encendida** → el runner arma los agentes desde la **base de datos**
  (`helic3_agentes`), lo editable.

Volver atrás = **apagar la bandera**. No requiere desplegar, ni migrar, ni
reiniciar procesos: el siguiente mensaje ya vuelve a las clases (la caché de
config se invalida sola, H3A-06). Por eso el rollback cabe en < 5 min.

> Regla de oro: **nunca** se enciende `agentes_desde_bd` en una cuenta sin haber
> sembrado antes sus agentes (paso D2). Encenderla con la tabla vacía deja la
> bandeja sin agentes y el job entrega la conversación al humano (crit 3 de H3A-08:
> no se rompe, pero la IA deja de responder).

---

## 2. Roles

| Rol | Quién | Responsabilidad |
|-----|-------|-----------------|
| **Responsable de despliegue** | Julián | Ejecuta migración y seed; enciende/apaga la bandera; da el visto bueno final. |
| **Revisor técnico** | Jhan | Aprueba el PR; valida en staging; decide si se sigue o se revierte. |
| **Ejecutor / soporte** | Samuel | Corre las verificaciones, observa logs y avisa si algo se desvía. |

En una emergencia fuera de horario, **cualquiera** de los tres puede ejecutar el
rollback del §4 (apagar la bandera): es una acción reversible y segura.

---

## 3. Despliegue (orden estricto)

Precondición: el PR del módulo está aprobado por Jhan y mergeado a la rama de
despliegue.

- **D0 — Jhan:** confirma que CI está verde (rspec + rubocop + guardian OSS) en el
  merge y da luz verde.
- **D1 — Julián:** despliega el código con la bandera **apagada**. En este punto
  producción sigue idéntica a hoy (camino `:clases`). *Checkpoint:* nada debería
  cambiar para el usuario final.
- **D2 — Julián:** corre las migraciones y la **siembra** de la cuenta piloto:

  ```
  docker compose exec rails bundle exec rails db:migrate
  docker compose exec rails bundle exec rails runner "Helic3::Agents::SeederService.new(Account.find(ID_CUENTA)).sembrar!"
  ```

  Esto crea los 5 agentes en `helic3_agentes` con el mismo prompt y herramientas
  que las clases. *Checkpoint (Samuel):* `Helic3::Agente.where(account_id: ID_CUENTA).count == 5`.
- **D3 — Samuel:** verifica la paridad **antes** de encender, corriendo la
  regresión contra esa cuenta (o en CI):

  ```
  docker compose exec rails bundle exec rspec spec/services/helic3/agents/regresion_bandera_spec.rb
  ```

  Debe pasar en verde. Si falla, **no se enciende**: se avisa a Jhan (§4).
- **D4 — Julián:** enciende la bandera **solo en la cuenta piloto**:

  ```
  docker compose exec rails bundle exec rails runner "Helic3::Catalogo::Parametro.find_or_create_by(account_id: ID_CUENTA, clave: 'agentes_desde_bd').update!(valor: 'true', unidad: 'booleano')"
  ```

  Desde el siguiente mensaje, esa cuenta corre en modo `:bd`.
- **D5 — Samuel + Jhan:** observan durante ~15 min. En los logs debe aparecer
  `[Helic3][ruteo] enrutó a …` y las respuestas deben verse iguales a antes.
  *Checkpoint:* ruteo correcto + sin errores en Sidekiq.
- **D6 — Julián:** si el piloto va bien, repite D2→D4 cuenta por cuenta. La
  bandera es **por cuenta**: se puede ir encendiendo gradualmente.

---

## 4. Vuelta atrás (< 5 minutos)

Disparadores: respuestas raras, ruteo equivocado, errores en Sidekiq, o cualquier
duda de Jhan. **Ante la duda, se apaga.** Es seguro y reversible.

- **R1 — quien detecte el problema (Samuel/Jhan/Julián):** avisa por el canal del
  equipo: "apagando agentes_desde_bd en cuenta X".
- **R2 — Julián (o quien esté disponible):** apaga la bandera de la cuenta
  afectada:

  ```
  docker compose exec rails bundle exec rails runner "Helic3::Catalogo::Parametro.where(account_id: ID_CUENTA, clave: 'agentes_desde_bd').update_all(valor: 'false')"
  ```

  Para apagar **todas** las cuentas de un golpe:

  ```
  docker compose exec rails bundle exec rails runner "Helic3::Catalogo::Parametro.where(clave: 'agentes_desde_bd').update_all(valor: 'false')"
  ```

- **R3 — automático:** el `after_commit` del parámetro/agente invalida la caché
  de config (H3A-06), así que el **siguiente mensaje** ya usa las clases. No hay
  que reiniciar `rails` ni `sidekiq`.
- **R4 — Samuel:** confirma en los logs que dejó de aparecer el ruteo `:bd` y que
  las respuestas volvieron a la normalidad. *Checkpoint:* `RunnerService.new(account: Account.find(ID_CUENTA)).modo == :clases`.

Tiempo total esperado: **1–3 min** (un comando + verificación). No se toca el
código desplegado; los datos en `helic3_agentes` quedan intactos para reintentar
más tarde.

### Rollback de código (solo si el interruptor no bastara)

Apagar la bandera cubre el 100% de los casos porque el camino `:clases` no depende
de nada nuevo. El rollback de código (revertir el deploy) solo haría falta si el
propio despliegue rompiera algo ajeno al módulo; en ese caso lo ejecuta **Julián**
con el procedimiento estándar de deploy del proyecto, y **no** es parte de este
runbook.

---

## 5. Resumen de una línea

> Encender = sembrar la cuenta y poner `agentes_desde_bd=true`.
> Apagar = `agentes_desde_bd=false`. El apagado es instantáneo, por cuenta, sin
> desplegar y sin perder datos.
