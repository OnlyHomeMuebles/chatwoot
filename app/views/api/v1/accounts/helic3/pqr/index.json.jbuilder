json.meta do
  json.count @total
  json.current_page(params[:page].presence || 1)
  json.per_page Api::V1::Accounts::Helic3::PqrController::RESULTS_PER_PAGE
  # Umbrales del semaforo (nil si la cuenta no los sembro): el cliente pinta el
  # color comparando dias_habiles_restantes de cada fila contra estos dos.
  if @umbrales
    json.umbral_verde @umbrales.umbral_verde
    json.umbral_amarillo @umbrales.umbral_amarillo
  end
  # Metricas del encabezado (BAN-01): conteos de la cuenta para la tira de KPIs.
  json.metricas do
    json.total @metricas[:total]
    json.sin_responder @metricas[:sin_responder]
    json.vencidas @metricas[:vencidas]
    json.respondidas @metricas[:respondidas]
  end
end

json.payload do
  json.array! @pqr do |ticket|
    json.partial! 'api/v1/accounts/helic3/pqr/pqr', formats: [:json], ticket: ticket
  end
end
