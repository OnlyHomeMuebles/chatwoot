# Only Home — Copilot (asistente del agente humano)

Versión propia (open source) del **Copilot** de Captain: un asistente que ayuda al **agente humano**
de soporte —no al cliente— a atender una conversación (redactar borradores, resumir el caso, sugerir
próximos pasos, responder dudas sobre la conversación).

Reimplementación con **código propio** sobre la gema `ai-agents` (Captain usa su propio
`Llm::BaseAiService`); namespace `Helic3::Copilot`, sin tocar `enterprise/`.

## Piezas

| Componente | Archivo | Rol |
|---|---|---|
| Agente copiloto | `app/services/helic3/copilot/agent.rb` | `Agents::Agent` que asiste al agente humano; lee la conversación antes de sugerir |
| Herramienta de contexto | `app/services/helic3/tools/get_conversation_tool.rb` | Lee los mensajes recientes de la conversación (Application API) |
| Servicio de sugerencia | `app/services/helic3/copilot/suggestion_service.rb` | Punto de entrada: dada la conversación + la consulta del agente, devuelve la sugerencia |

## Cómo se usa

```ruby
service = Helic3::Copilot::SuggestionService.new
sugerencia = service.suggest(
  conversation_id: 5,                                  # display_id de Chatwoot
  query: 'Redáctame una respuesta amable para el cliente'
)
# => texto sugerido PARA EL AGENTE (no se envía al cliente)
```

- El servicio corre el agente copiloto con el contexto atado al `conversation_id`. El copiloto usa
  `GetConversationTool` para leer la conversación y luego redacta la sugerencia.
- `history:` permite continuidad entre turnos del copiloto; `chatwoot_client:` es inyectable (por
  defecto se construye desde ENV: `ONLY_HOME_CHATWOOT_*`).

## Diferencias con el Copilot de Captain

| | Captain | Only Home (esta versión) |
|---|---|---|
| Base | `Llm::BaseAiService` + arrays de mensajes | Gema `ai-agents` (`Agents::Agent` + Runner) |
| Ubicación | `enterprise/` | open source (`app/services/helic3/`) |
| Namespace | `Captain::Copilot` | `Helic3::Copilot` |
| Alcance | Chat con hilos/mensajes persistentes, API y broadcasting, múltiples tools | Núcleo: servicio de sugerencia + herramienta de contexto |

> La sugerencia la redacta el LLM: para respuestas reales se necesita una API key configurada. La
> estructura (agente, herramienta de contexto, servicio) está probada con specs (runner/cliente
> stubbeados).
