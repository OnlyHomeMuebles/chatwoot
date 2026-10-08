# frozen_string_literal: true

# FMT-02: lista los formatos con sus versiones (lectura abierta a agentes) y expone el
# diccionario de marcadores. La escritura de plantillas vive en PlantillasController.
class Api::V1::Accounts::Helic3::Admin::FormatosController < Api::V1::Accounts::BaseController
  def index
    @formatos = Helic3::Catalogo::Formato.where(account: Current.account).order(:posicion)
  end

  def marcadores
    render json: Helic3::Formatos::Marcadores::DICCIONARIO
  end
end
