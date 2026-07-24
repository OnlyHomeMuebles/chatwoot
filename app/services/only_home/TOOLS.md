# Only Home — Tools de Chatwoot (Application API)

Tools de la gema `ai-agents` (subclases de `Agents::Tool`) que permiten a los agentes actuar
sobre una conversación real de Chatwoot mediante la **Application API** (HTTP). Se adjuntan a un
agente vía `tools: [...]` en `Agents::Agent.new`.

Todas heredan de `OnlyHome::Tools::BaseTool`, que:
- Lee el `conversation_id` desde el estado del run (`tool_context.state[:conversation_id]`).
- Usa el cliente `OnlyHome::ChatwootClient` (inyectable en el estado como `:chatwoot_client`; si no, se
  construye desde ENV).
- Convierte errores de API en un mensaje legible para el agente en vez de romper el run.

## Configuración (`OnlyHome::ChatwootClient`)

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
| `OnlyHome::Tools::RespondTool` | Responde al cliente (mensaje público) | `POST /api/v1/accounts/:account_id/conversations/:id/messages` con `message_type: outgoing` |
| `OnlyHome::Tools::PrivateNoteTool` | Deja una nota privada interna | `POST /api/v1/accounts/:account_id/conversations/:id/messages` con `private: true` |
| `OnlyHome::Tools::AddLabelTool` | Agrega una etiqueta (conserva las existentes) | `GET` + `POST /api/v1/accounts/:account_id/conversations/:id/labels` (lee las actuales y envía la unión) |
| `OnlyHome::Tools::UpdateAttributeTool` | Guarda un atributo personalizado | `POST /api/v1/accounts/:account_id/conversations/:id/custom_attributes` |

## Uso

```ruby
tools = [
  OnlyHome::Tools::RespondTool.new,
  OnlyHome::Tools::PrivateNoteTool.new,
  OnlyHome::Tools::AddLabelTool.new,
  OnlyHome::Tools::UpdateAttributeTool.new
]
agent = Agents::Agent.new(name: 'agente_faq', instructions: '...', tools: tools)
# En tiempo de ejecución, el estado del run debe incluir el id de la conversación:
#   runner.run(mensaje, context: { state: { conversation_id: 42 } })
```
