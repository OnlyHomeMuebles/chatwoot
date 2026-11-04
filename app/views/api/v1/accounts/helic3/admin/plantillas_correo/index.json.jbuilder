json.array!(@registros) do |registro|
  json.partial! 'api/v1/accounts/helic3/admin/plantillas_correo/plantilla_correo', registro: registro
end
