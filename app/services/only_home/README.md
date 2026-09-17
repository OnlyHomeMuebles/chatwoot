# Only Home — Agentes multiagente (ai-agents)

Sistema de atención multiagente de Only Home construido sobre la gema `ai-agents`
(`Agents::Agent`). Sigue el patrón **hub-and-spoke**: un agente central de enrutamiento
(triage) transfiere la conversación a un especialista de dominio, y los especialistas solo
devuelven el control al triage. El patrón de handoff, la selección de agente y el runner
(thread-safe, con historial) los aporta la gema; aquí solo se definen los agentes, sus
instrucciones y el cableado.

- Entrada por defecto del runner: `agente_triage` (primer agente en `Agents::Runner.with_agents`).
- Cableado (una sola vía): `triage → {faq, pqrs, logistica, cotizaciones} → triage`.
- Idioma de atención: español. Precios en pesos colombianos (COP).

## Rol y límites de cada agente

| Agente | Nombre | Rol (responsabilidad única) | NO hace (fronteras) | Contexto dinámico |
|---|---|---|---|---|
| Triage | `agente_triage` | Clasifica la solicitud y transfiere al especialista correcto. Solo enruta, no resuelve. | No responde ni resuelve consultas por su cuenta. | — |
| Conocimiento / FAQ | `agente_faq` | Preguntas informativas: características y materiales de productos, proceso de compra, tiempos y condiciones generales, política de garantías. | Quejas/garantías (PQRS), seguimiento de pedidos (Logística), precios/cotizaciones (Cotizaciones). | Estático (conocimiento general). |
| PQRS y Garantías | `agente_pqrs` | Peticiones, quejas, reclamos y sugerencias; productos defectuosos/incompletos; devoluciones/cambios; activación de garantía postventa. | Seguimiento logístico, cotizaciones, dudas informativas generales. | Inyecta `customer_name`, `order_number`. |
| Logística | `agente_logistica` | Estado y seguimiento de pedidos, fechas y novedades de entrega, transportadoras, reprogramación de instalaciones. | Quejas/garantías, cotizaciones, dudas informativas generales. | Inyecta `customer_name`, `order_number`. |
| Cotizaciones | `agente_cotizaciones` | Precios, presupuestos y cotizaciones; condiciones comerciales (financiación, descuentos, tiempos estimados). | Quejas/garantías, seguimiento de pedidos, dudas informativas generales. | Inyecta `customer_name`, `city`, `product`. |

## Instrucciones dinámicas (Procs con `context`)

Los especialistas de PQRS, Logística y Cotizaciones usan `instructions` como un `Proc` que lee
`run_context.context[:state]`. Si el estado ya trae datos conocidos (cliente, número de
pedido/orden, ciudad, producto), se añaden a las instrucciones para que el agente no vuelva a
pedirlos. Sin estado, el agente usa solo sus instrucciones base. FAQ es estático porque atiende
conocimiento general y no depende de datos del cliente.

## Archivos

- `triage_agent.rb`, `faq_agent.rb`, `pqrs_agent.rb`, `logistica_agent.rb`, `cotizaciones_agent.rb`
- `runner_service.rb` — cablea los handoffs y expone el runner de la gema.
