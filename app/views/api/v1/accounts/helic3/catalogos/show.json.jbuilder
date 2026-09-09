json.tipos @tipos do |tipo|
  json.call(tipo, :id, :codigo, :nombre, :plazo_dias_habiles)
end

json.motivos_pqr @motivos_pqr do |motivo|
  json.call(motivo, :id, :codigo, :nombre, :abre_garantia, :plazo_dias_habiles)
  json.categoria do
    json.call(motivo.categoria, :id, :codigo, :nombre)
  end
end

json.etapas_pqr @etapas_pqr do |etapa|
  json.call(etapa, :id, :codigo, :nombre, :detiene_reloj, :visible_cliente)
end

json.resultados @resultados do |resultado|
  json.call(resultado, :id, :codigo, :nombre, :cierra_pqr, :abre_garantia, :aprobacion_humana)
end
