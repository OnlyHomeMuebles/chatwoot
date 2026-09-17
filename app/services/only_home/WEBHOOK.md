# Only Home — Webhook de Chatwoot → sistema agéntico (MA-04)

Conecta un **mensaje entrante** de Chatwoot con el sistema multiagente: Chatwoot envía el evento
`message_created` a un endpoint OSS, que dispara el `OnlyHome::RunnerService` y publica la respuesta
del agente en la conversación.

## Flujo

```
Cliente escribe en Chatwoot
  → message_created (AgentBotListener → AgentBots::WebhookJob)
  → POST /webhooks/only_home            (Webhooks::OnlyHomeController)
  → OnlyHome::WebhookHandler            (filtra + idempotencia)
  → OnlyHome::ProcessConversationJob    (async)
  → OnlyHome::RunnerService.run(..., context: { state: { conversation_id } })
  → respuesta del agente publicada en la conversación (RespondTool / Application API)
```

## Piezas (todas OSS)

| Componente | Archivo |
|---|---|
| Ruta | `config/routes.rb` → `POST /webhooks/only_home` |
| Controlador | `app/controllers/webhooks/only_home_controller.rb` |
| Handler (filtro + idempotencia) | `app/services/only_home/webhook_handler.rb` |
| Job de procesamiento | `app/jobs/only_home/process_conversation_job.rb` |

- **Solo reacciona a** `event == message_created`, `message_type == incoming`, no privado y con contenido.
  Así ignora las respuestas del propio agente y las notas privadas (evita bucles).
- **Contexto atado a la conversación:** el `conversation_id` (display_id) viaja en
  `context[:state][:conversation_id]`, para que las tools actúen sobre la conversación correcta.
- **Idempotencia:** clave Redis `only_home:webhook:message:<id>` con `SET NX EX 1h`. Un reintento del
  mismo mensaje no vuelve a encolar.

## Configuración en Chatwoot (Agent Bot)

1. Crear un **Agent Bot** (`bot_type: webhook`) con `outgoing_url = https://<app>/webhooks/only_home`.
2. Asignarlo a la bandeja (inbox) que debe atender el agente (`agent_bot_inbox` activo).
3. Las variables de entorno para que el job publique la respuesta:
   - `ONLY_HOME_CHATWOOT_BASE_URL`, `ONLY_HOME_CHATWOOT_ACCOUNT_ID`, `ONLY_HOME_CHATWOOT_API_TOKEN`
     (idealmente el token del propio Agent Bot).

## Bloqueo de webhook en modo test/local (ya identificado)

La entrega de webhooks de Chatwoot pasa por **`SafeFetch`** (protección SSRF, `lib/safe_fetch.rb`), que
**bloquea URLs de red privada / `localhost`** salvo que se habilite explícitamente:

```
SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true
```

En una instancia local, sin esa variable el webhook del Agent Bot **no llega** a `http://localhost:3000/...`.
Para probar el flujo E2E localmente hay que arrancar Chatwoot con `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`.
En producción (URL pública) no aplica.

> Nota: la respuesta del agente requiere una API key de LLM configurada para el `RunnerService`. El
> flujo (webhook → runner → publicación de la respuesta) está probado E2E contra una instancia real de
> Chatwoot OSS con el runner simulado, y la idempotencia contra el Redis real.
