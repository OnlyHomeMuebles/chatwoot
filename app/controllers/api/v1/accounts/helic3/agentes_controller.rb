class Api::V1::Accounts::Helic3::AgentesController < Api::V1::Accounts::BaseController
  # H3A-03: catalogo FIJO de solo lectura. Las herramientas disponibles y el texto
  # de las reglas duras viven en codigo; se exponen aqui para que el panel (H3A-14)
  # no los duplique. Agregar una herramienta en el catalogo la hace aparecer aqui
  # sin tocar el front. Las reglas duras son el bloque real de CoreRules (decision 2).
  def catalogo
    render json: {
      herramientas: Helic3::Agents::CatalogoHerramientas.para_api,
      reglas_duras: Helic3::Agents::PromptBuilder.reglas_duras
    }
  end
end
