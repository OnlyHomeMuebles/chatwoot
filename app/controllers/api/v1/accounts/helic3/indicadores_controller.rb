# IND-01: endpoint de solo lectura para la seccion "Indicadores" (garantias y
# PQR por mes, trimestre, motivo, detalle, producto, ciudad y responsable).
# Mismo criterio de autorizacion que PqrController: index? es true para
# cualquier agente de la cuenta, la restriccion de la pestana Carga de Datos
# (solo administradores) llega con IND-03.
class Api::V1::Accounts::Helic3::IndicadoresController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def garantias
    @indicadores = Helic3::Indicadores::Garantias.call(account: Current.account, filtros: filtros_garantias)
  end

  private

  def check_authorization
    authorize(Helic3::Ticket, :index?)
  end

  FILTROS_GARANTIAS = %i[anio mes cobertura_ciudad_id motivo_garantia_id detalle_tipificado_id proceso_id
                         producto].freeze

  def filtros_garantias
    params.permit(*FILTROS_GARANTIAS).to_h.symbolize_keys
  end
end
