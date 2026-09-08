json.array!(@registros) do |registro|
  json.merge! registro.attributes
end
