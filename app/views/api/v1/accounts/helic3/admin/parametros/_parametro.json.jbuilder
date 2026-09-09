# Serializacion explicita. La etiqueta legible sale del locale del modulo; si no
# hay etiqueta definida, cae a una version humanizada de la clave.
json.id parametro.id
json.clave parametro.clave
json.valor parametro.valor
json.unidad parametro.unidad
json.etiqueta I18n.t("helic3.parametros.#{parametro.clave}", default: parametro.clave.humanize)
