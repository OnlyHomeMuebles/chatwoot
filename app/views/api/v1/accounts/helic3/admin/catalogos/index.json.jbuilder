json.array!(@registros) do |registro|
  json.partial! 'api/v1/accounts/helic3/admin/catalogos/catalogo', registro: registro
end
