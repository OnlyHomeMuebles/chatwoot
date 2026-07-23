# Only Home — Agente multiagente · Cumplimiento de criterios de aceptación

Documento que demuestra, con evidencia verificable, el cumplimiento de los criterios de
aceptación y la Definition of Done (DoD) de las tres tareas del tablero.

- **Código:** `app/services/only_home/`
- **Pruebas:** `spec/services/only_home/`
- **Gema:** `ai-agents` 0.12.0 (módulo `Agents`) — aporta el patrón hub-and-spoke, los handoffs, el runner (thread-safe, historial, detección de agente) y la selección de agente.
- **PRs:** #4 (`feature/agente-triage`), #5 (`feature/agentes-especialistas`), #6 (`feature/handoffs-runner`).

## Resultado de la suite de pruebas

```
$ bundle exec rspec spec/services/only_home/
39 examples, 0 failures
```

RuboCop: `13 files inspected, no offenses detected`.

---

## Tarea 1 — `feature/agente-triage`: agente central (Triage)

> Definir con `Agents::Agent.new` el agente central de entrada, con instrucciones de solo
> enrutar (no resolver) ajustadas a los dominios de Only Home. El patrón hub-and-spoke y la
> selección de agente los aporta la gema.

### Criterios de aceptación

| Criterio | Cómo se cumple | Evidencia |
|---|---|---|
| Definir con `Agents::Agent.new` | El Triage se define con `Agents::Agent.new`. | `triage_agent.rb:21-22` (`Agents::Agent.new`, `name: 'agente_triage'`) |
| Instrucciones explícitas de **solo enrutar, no resolver** | Las instrucciones dicen "Tu ÚNICA responsabilidad es identificar el dominio… No resuelves nada directamente. No des respuestas sustantivas… nunca respondas por tu cuenta". | `triage_agent.rb:8`; test `TriageAgent … sus instrucciones prohíben resolver directamente` |
| Es el **punto de entrada por defecto** del runner | El Triage es el primer agente que se pasa a `Agents::Runner.with_agents`; la gema toma el primero como agente por defecto (`@default_agent = agents.first`). | `runner_service.rb:27,31`; gema `agent_runner.rb:42`; test `RunnerService … registra agente_triage como primer agente (punto de entrada)` |
| Clasifica los **cuatro dominios** (FAQ, PQRS/garantías, logística, cotizaciones) | El Triage nombra los cuatro dominios en sus instrucciones y registra handoff a los cuatro especialistas. | test `TriageAgent … sus instrucciones mencionan los cuatro dominios`; test `… puede transferir a los cuatro especialistas` |

### Definition of Done

| DoD | Evidencia |
|---|---|
| Pruebas que confirman el **enrutamiento por dominio** | `RunnerService › enrutamiento por dominio` (4 tests: conocimiento/FAQ, PQRS, logística, cotizaciones) + `RunnerService › #run con un handoff › enruta desde el triage al especialista de FAQ` |
| **Sin bucles de handoff** en los escenarios de prueba | `TriageAgent … no tiene handoff hacia sí mismo (sin bucles)`; `RunnerService › sin bucles de handoff › el triage no tiene handoff hacia sí mismo`; `… cada especialista solo tiene handoff al triage` |

---

## Tarea 2 — `feature/agentes-especialistas`: agentes especialistas

> Definir con `Agents::Agent` los especialistas de Only Home (Conocimiento/FAQ, PQRS/Garantías,
> Logística, Cotizaciones) con fronteras claras. El trabajo propio es escribir las instrucciones
> del negocio (y Procs con context donde aporte); las capacidades las trae la gema.

### Criterios de aceptación

| Criterio | Cómo se cumple | Evidencia |
|---|---|---|
| Cada especialista con **responsabilidad única y delimitada** | Cada agente define su rol y una sección "Fronteras (qué NO haces)". | `faq_agent.rb`, `pqrs_agent.rb`, `logistica_agent.rb`, `cotizaciones_agent.rb`; tests `… delimitan su responsabilidad …` y `… declaran las fronteras …` (cada agente) |
| **Instrucciones dinámicas basadas en contexto** donde aplique | PQRS, Logística y Cotizaciones usan `instructions` como `Proc` que lee `run_context.context[:state]` e inyecta datos conocidos (cliente, pedido/orden, ciudad, producto). FAQ es estático (conocimiento general). | `pqrs_agent.rb:35-37`, `logistica_agent.rb:34-36`, `cotizaciones_agent.rb:33-35`; tests `… instrucciones dinámicas por contexto › inyecta …` |
| Los especialistas **solo devuelven el control al triage** | Cada instrucción indica "transfiere de vuelta al `agente_triage`"; el cableado del runner conecta cada especialista únicamente al triage. | tests `… devuelve el control al triage fuera de su dominio` (cada agente); `runner_service.rb:22-25` |

### Definition of Done

| DoD | Evidencia |
|---|---|
| Cada agente responde correctamente **en aislamiento** (prueba unitaria) | Un spec unitario por especialista: `faq_agent_spec.rb`, `pqrs_agent_spec.rb`, `logistica_agent_spec.rb`, `cotizaciones_agent_spec.rb` |
| **Documento con el rol y los límites** de cada agente | `app/services/only_home/README.md` (tabla de rol, fronteras y contexto dinámico por agente) |

---

## Tarea 3 — `feature/handoffs-runner`: handoffs y runner

> Usar `register_handoffs` para conectar los especialistas al triage en una sola vía
> (hub-and-spoke) y crear el orquestador con `Agents::Runner.with_agents(triage, ...)`. El Runner
> (thread-safe, historial y detección de agente) lo provee la gema; aquí solo se cablea.

### Criterios de aceptación

| Criterio | Cómo se cumple | Evidencia |
|---|---|---|
| `triage.register_handoffs(...)` en **una sola dirección** (triage → especialistas → triage) | El triage registra handoff a los cuatro especialistas; cada especialista registra handoff solo de vuelta al triage. | `runner_service.rb:21-25`; test `RunnerService › sin bucles de handoff › cada especialista solo tiene handoff al triage` |
| Runner creado con `Agents::Runner.with_agents`, **reutilizable** entre conversaciones | El runner se crea con `Agents::Runner.with_agents(*build_agents)` y se memoiza para reutilizarse en llamadas sucesivas. | `runner_service.rb:31`; test `RunnerService › #run con un handoff › reutiliza el mismo runner entre conversaciones` |
| El agente actual **se determina automáticamente desde el historial** (lo hace la gema) | Lo resuelve la gema en `AgentRunner#determine_conversation_agent` a partir del historial de la conversación. | gema `agent_runner.rb:74,220` |

### Definition of Done

| DoD | Evidencia |
|---|---|
| **Prueba de integración** de un flujo con al menos un handoff | `runner_service_handoff_spec.rb` conduce el runner real de la gema por un handoff triage → especialista (solo se stubbea la capa LLM): `RunnerService › #run con un handoff › enruta desde el triage al especialista de FAQ` |
| El handoff es **transparente para el usuario final** | El resultado final es la respuesta del especialista, sin rastro del traspaso. | test `… entrega al usuario solo la respuesta del especialista (handoff transparente)` |

---

## Cómo reproducir la evidencia

```bash
# Suite completa (39 ejemplos, 0 fallas)
bundle exec rspec spec/services/only_home/

# Ver cada prueba mapeada a su criterio
bundle exec rspec spec/services/only_home/ --format documentation

# Estilo
bundle exec rubocop app/services/only_home/ \
                    spec/services/only_home/
```

Topología del agente (verificable en consola con `bundle exec rails runner`):

```
Entrada por defecto del runner: agente_triage
Triage enruta a: agente_faq, agente_pqrs, agente_logistica, agente_cotizaciones
Cada especialista devuelve solo a: agente_triage   (hub-and-spoke, sin bucles)
Herramientas de handoff del triage:
  handoff_to_agente_faq, handoff_to_agente_pqrs,
  handoff_to_agente_logistica, handoff_to_agente_cotizaciones
```
