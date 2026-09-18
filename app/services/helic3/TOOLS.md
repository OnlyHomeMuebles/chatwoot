# Only Home — Tools de Chatwoot (Application API)

Tools de la gema `ai-agents` (subclases de `Agents::Tool`) que permiten a los agentes actuar
sobre una conversación real de Chatwoot mediante la **Application API** (HTTP). Se adjuntan a un
agente vía `tools: [...]` en `Agents::Agent.new`.

Todas heredan de `Helic3::Agents::Tools::BaseTool`, que:
- Lee el `conversation_id` desde el estado del run (`tool_context.state[:conversation_id]`).
- Usa el cliente `Helic3::ChatwootClient` (inyectable en el estado como `:chatwoot_client`; si no, se
  construye desde ENV).
- Convierte errores de API en un mensaje legible para el agente en vez de romper el run.

## Configuración (`Helic3::ChatwootClient`)

> **Nota:** el `conversation_id` que reciben las tools (desde `tool_context.state[:conversation_id]`)
> es el **`display_id`** de la conversación en Chatwoot — la Application API ubica la conversación por
> `display_id`, no por el id de base de datos.

Autenticación por header `api_access_token` (token de un usuario o de un Agent Bot). Variables de entorno:

| Variable | Descripción |
|---|---|
| `ONLY_HOME_CHATWOOT_BASE_URL` | URL base de Chatwoot (fallback: `FRONTEND_URL`, luego `http://localhost:3000`) |
| `ONLY_HOME_CHATWOOT_ACCOUNT_ID` | ID de la cuenta |
| `ONLY_HOME_CHATWOOT_API_TOKEN` | Token de acceso de la Application API |

## Qué API usa cada tool

| Tool | Acción | Endpoint de la Application API |
|---|---|---|
| `Helic3::Agents::Tools::RespondTool` | Responde al cliente (mensaje público) | `POST /api/v1/accounts/:account_id/conversations/:id/messages` con `message_type: outgoing` |
| `Helic3::Agents::Tools::PrivateNoteTool` | Deja una nota privada interna | `POST /api/v1/accounts/:account_id/conversations/:id/messages` con `private: true` |
| `Helic3::Agents::Tools::AddLabelTool` | Agrega una etiqueta (conserva las existentes) | `GET` + `POST /api/v1/accounts/:account_id/conversations/:id/labels` (lee las actuales y envía la unión) |
| `Helic3::Agents::Tools::UpdateAttributeTool` | Guarda un atributo personalizado | `POST /api/v1/accounts/:account_id/conversations/:id/custom_attributes` |
| `Helic3::Agents::Tools::HumanHandoffTool` | Escala a un humano: nota con motivo, etiqueta `escalado-humano`, (opcional) asigna a equipo y reabre | `messages` (nota) + `labels` + `assignments` + `toggle_status` |

## Escalamiento a humano (INT-02)

`HumanHandoffTool` es equivalente al handoff a humano de Captain. Cuando un agente no puede resolver,
lo invoca con un `reason`: deja el motivo como **nota privada**, agrega la etiqueta `escalado-humano`,
opcionalmente asigna a un equipo (`tool_context.state[:human_team_id]`) y **reabre la conversación**
(`status: open`) para que un humano la tome con todo el contexto. Los especialistas la llevan adjunta y
sus instrucciones definen **cuándo derivar** (petición explícita del cliente, queja grave/legal, no poder
resolver tras intentarlo, o casos que requieren acción humana).

## Uso

```ruby
tools = [
  Helic3::Agents::Tools::RespondTool.new,
  Helic3::Agents::Tools::PrivateNoteTool.new,
  Helic3::Agents::Tools::AddLabelTool.new,
  Helic3::Agents::Tools::UpdateAttributeTool.new
]
agent = Agents::Agent.new(name: 'agente_faq', instructions: '...', tools: tools)
# En tiempo de ejecución, el estado del run debe incluir el id de la conversación:
#   runner.run(mensaje, context: { state: { conversation_id: 42 } })
```
