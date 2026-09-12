json.array! @decisiones do |ticket|
  json.partial! 'api/v1/accounts/helic3/pqr/decision', formats: [:json],
                ticket: ticket, propuestas: @propuestas
end
