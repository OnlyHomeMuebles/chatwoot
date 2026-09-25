# Agentes editables — decisiones pendientes de cerrar (H3A)

Nota exigida por la revisión del PR #70 (E4). El backend de agentes editables
(H3A-01/02/03/04/07/08/12) ya está; lo que sigue abierto queda escrito aquí para
no cerrarlo en silencio.

## N3 — La semilla congela `PoliticasEstaticas` y no hay camino de actualización

`Helic3::Agents::SeederService#extraer_cuerpo` guarda en la columna `prompt` el
cuerpo YA interpolado del agente (en FAQ eso incluye `EMPRESA`, `CATALOGO`,
`COMBOS`, `TIENDAS`, `POLITICAS` y `FAQ`, resueltos desde `PoliticasEstaticas`).

Como el seeder **solo crea y nunca actualiza** (igual que el de catálogo), a
partir de la **primera siembra** hay dos fuentes de verdad: tocar
`PoliticasEstaticas` en código ya **no** llega a los agentes en modo `:bd`.

**Decisión (a confirmar con Jhan):** dos caminos posibles:

1. Un `resembrar!` explícito que re-extraiga el cuerpo de las clases y **pise** el
   `prompt` de las filas de sistema (arriesga perder ediciones hechas desde la UI).
2. El código pasa a ser **solo semilla inicial** y, a partir de ahí, **manda la
   BD**: `PoliticasEstaticas` deja de mantenerse para los agentes en modo `:bd`.

**Inclinación de Jhan (revisión PR #70):** la opción 2. Alinea con la misma regla
del seeder de catálogo (ver `app/models/helic3/catalogo/PENDIENTES.md`: "la semilla
solo CREA"). Falta la confirmación formal para dejarlo cerrado.

## Otras decisiones ya declaradas (contexto)

| Tema | Estado |
|---|---|
| **Modelo por agente vs por cuenta** | Implementado por **cuenta** (sale de `LlmRuntime`). La columna `helic3_agentes.modelo` ya se respeta como **override** en `RunnerService#construir_agente` (N1): activar "modelo por agente" solo requiere llenar esa columna desde la UI. Falta la decisión de producto de si se expone en H3A-13. |
| **Reglas duras reales** | La lista imborrable que antepone `PromptBuilder` = `CoreRules::GUIDE`. Confirmar con Jhan que ese es el texto legal/seguridad definitivo. |
| **Secciones contextuales por código** | El consentimiento del triage (AGT-07), los tiempos/códigos de PQRS y el contexto de logística/cotizaciones se reproducen en código keyed por `codigo`, no en el `prompt`, para preservar la paridad. Un agente **nuevo** creado desde el admin solo recibe el cuerpo estático. |
| **Ruteo dinámico (H3A-09)** | Pendiente en el siguiente PR: hoy el triage rutea con su lista sembrada, así que un agente **nuevo** no recibiría tráfico hasta que el triage arme el ruteo desde `criterio_ruteo`. |
| **`confianza_minima` (H3A-11)** | **No implementada.** El runner (gem `ai-agents`) NO produce un puntaje de confianza; el LLM devuelve texto, no un número. No hay valor que comparar contra `confianza_minima`. Además NO está entre los 3 criterios de aceptación de H3A-11 (que son `max_respuestas`, `horario` y el log del motivo, ya implementados). Falta definir con Jhan una **fuente de confianza** (p. ej. un tool que el agente llame para autoevaluarse, o un umbral sobre alguna señal del proveedor) antes de poder aplicarla. |
