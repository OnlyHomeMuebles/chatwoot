json.array!(@parametros) do |parametro|
  json.merge! parametro.attributes
end
