# Radicado de garantia (GAR-02). El bloque `presupuesto` calcula dias habiles y
# festivos, por eso se sirve solo en la vista detallada (misma razon que el
# semaforo del expediente). Los parametros salen del catalogo, ambito garantia.
json.id resource.id
json.display_id resource.display_id
json.numero_radicado resource.numero_radicado
json.abierta_at resource.abierta_at
json.cerrada_at resource.cerrada_at
json.presupuesto_dias_habiles resource.presupuesto_dias_habiles

visible = resource.proceso_visible
if visible
  json.proceso_visible do
    json.call(visible, :id, :codigo, :nombre, :es_terminal)
  end
else
  json.proceso_visible nil
end

ciudad = resource.cobertura_ciudad
if ciudad
  json.cobertura_ciudad do
    json.call(ciudad, :id, :codigo, :nombre, :tecnico_propio)
  end
else
  json.cobertura_ciudad nil
end

parametros = Helic3::ParametrosGarantia.desde_catalogo(resource.account, ambito: :garantia)
presupuesto = resource.presupuesto(parametros: parametros)
json.presupuesto do
  json.consumidos presupuesto.consumidos
  json.saldo presupuesto.saldo
  json.fecha_etapa_vigente presupuesto.fecha_etapa_vigente
  json.semaforo presupuesto.semaforo
end

json.items resource.items do |item|
  json.id item.id
  json.producto_nombre item.producto_nombre
  json.producto_referencia item.producto_referencia
  json.decision item.decision
  json.resuelto_at item.resuelto_at
  %i[motivo_garantia detalle_tipificado proceso].each do |llave|
    registro = item.public_send(llave)
    if registro
      json.set! llave do
        json.call(registro, :id, :codigo, :nombre)
      end
    else
      json.set! llave, nil
    end
  end
end
