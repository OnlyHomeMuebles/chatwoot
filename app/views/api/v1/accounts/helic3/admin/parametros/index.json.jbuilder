json.array!(@parametros) do |parametro|
  json.partial! 'api/v1/accounts/helic3/admin/parametros/parametro', parametro: parametro
end
