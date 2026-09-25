# frozen_string_literal: true

# H3A-07: ensambla el prompt final de un agente en orden fijo, anteponiendo por
# CODIGO las reglas duras. El `prompt` editable del agente es solo su cuerpo de
# dominio (identidad + pautas); las reglas duras y el tono se agregan aqui, de
# modo que un texto del admin NO puede desactivarlas (van primero y por codigo).
#
# Orden: reglas duras (codigo) -> identidad + pautas del admin -> politicas de la
# operacion -> tono (codigo). Con la semilla de H3A-04 (politicas_texto vacio)
# esto reensambla EXACTO el INSTRUCTIONS original de cada clase -> comportamiento
# igual (H3A-04 criterio 4).
#
# Nota (inconsistencia ticket<->codigo, hablada con Jhan): el "como abordarlo" de
# H3A-07 menciona concatenar "herramientas autorizadas" en el prompt. No se
# agrega un bloque de texto de herramientas porque (a) romperia la paridad con el
# prompt actual, que no lista tools en texto, y (b) la AUTORIZACION real de
# herramientas es H3A-10 (el arreglo tools que recibe el agente), no texto. Los
# criterios de aceptacion de H3A-07 (reglas duras primero, identicas, y log de
# depuracion) se cumplen igual.
class Helic3::Agents::PromptBuilder
  def initialize(agente)
    @agente = agente
  end

  # bloque de reglas duras: identico para TODOS los agentes (criterio 2) y
  # siempre primero (criterio 1). Vive en codigo; no pasa por la base de datos.
  def self.reglas_duras
    Helic3::Agents::CoreRules::GUIDE
  end

  # `cuerpo` permite sustituir el cuerpo de dominio del agente sin alterar el orden
  # ni las reglas duras. Lo usa H3A-09: el triage arma su directorio de ruteo desde
  # la BD y pasa el cuerpo ya con ese directorio, en vez del `prompt` almacenado.
  def construir(cuerpo: nil)
    prompt = armar(cuerpo.presence || @agente.prompt.presence)
    # criterio 3: el prompt final queda en el log en modo depuracion
    Rails.logger.debug { "[Helic3][PromptBuilder] agente=#{@agente.codigo}\n#{prompt}" }
    prompt
  end

  private

  def armar(cuerpo)
    [
      self.class.reglas_duras,           # reglas duras (codigo) — SIEMPRE primero
      cuerpo,                            # identidad + pautas (editable por el admin)
      @agente.politicas_texto.presence,  # politicas de la operacion (editable)
      Helic3::Agents::HumanTone::GUIDE   # tono (codigo)
    ].compact.join("\n\n")
  end
end
