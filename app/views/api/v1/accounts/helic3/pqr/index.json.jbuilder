json.meta do
  json.count @total
  json.current_page(params[:page].presence || 1)
end

json.payload do
  json.array! @pqr do |ticket|
    json.partial! 'api/v1/accounts/helic3/pqr/pqr', formats: [:json], ticket: ticket
  end
end
