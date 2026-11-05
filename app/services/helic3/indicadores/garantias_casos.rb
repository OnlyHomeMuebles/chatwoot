# Lista de casos individuales de Garantias ("Detalle de clientes y casos",
# mockup v12): ordenada por urgencia (vencidas primero, solucionadas al
# final) y paginada. Vive en su propia clase (mismo criterio aplicado a
# Helic3::Indicadores::DevolucionesCasos en el PR #149) para no inflar
# Helic3::Indicadores::Garantias -- el ordenamiento usa una clave liviana
# para TODAS las garantias filtradas, y solo las 7 de la pagina final pagan
# el costo de numero_radicado/cliente/centro/proceso.
class Helic3::Indicadores::GarantiasCasos
  POR_PAGINA = 7
  RANGO_URGENCIA = { rojo: 0, amarillo: 1, verde: 2, sin_presupuesto: 3, resuelta: 4 }.freeze

  def initialize(account:, garantias_filtradas:)
    @account = account
    @garantias_filtradas = garantias_filtradas
  end

  def listar(pagina: 1)
    calendario = Helic3::CalendarioHabil.new
    parametros = Helic3::ParametrosGarantia.desde_catalogo(account, ambito: :garantia)
    ordenadas = garantias_filtradas
                .includes(items: :proceso)
                .map { |garantia| clave_urgencia(garantia, parametros, calendario) }
                .sort_by { |clave| [clave[:rango], clave[:garantia_id]] }
    paginar(ordenadas, pagina)
  end

  private

  attr_reader :account, :garantias_filtradas

  def clave_urgencia(garantia, parametros, calendario)
    resuelta = garantia.resuelta?
    presupuesto = resuelta ? nil : garantia.presupuesto(parametros: parametros, calendario: calendario)
    { garantia_id: garantia.id, resuelta: resuelta, presupuesto: presupuesto,
      rango: rango_urgencia_de_caso(resuelta, presupuesto) }
  end

  def filas_de_pagina(claves)
    garantias = Helic3::Garantia.where(id: claves.pluck(:garantia_id))
                                .includes(:cobertura_ciudad, items: :proceso, ticket: { conversation: :contact })
                                .index_by(&:id)
    claves.map { |clave| fila_de_caso(garantias.fetch(clave[:garantia_id]), clave) }
  end

  def fila_de_caso(garantia, clave)
    conversacion = garantia.ticket.conversation
    {
      id: garantia.id,
      numero_radicado: garantia.numero_radicado,
      cliente: conversacion&.contact&.name,
      centro_operacion: garantia.cobertura_ciudad&.nombre,
      proceso: garantia.proceso_visible&.nombre,
      etapa: clave[:resuelta] ? 'solucionada' : 'en_gestion',
      conversation_display_id: conversacion&.display_id,
      vencimiento: vencimiento_de_caso(clave[:resuelta], clave[:presupuesto])
    }
  end

  def vencimiento_de_caso(resuelta, presupuesto)
    return { estado: 'solucionada' } if resuelta

    {
      estado: presupuesto.semaforo.to_s,
      saldo_dias_habiles: presupuesto.saldo,
      fecha_etapa_vigente: presupuesto.fecha_etapa_vigente
    }
  end

  def rango_urgencia_de_caso(resuelta, presupuesto)
    return RANGO_URGENCIA[:resuelta] if resuelta

    RANGO_URGENCIA.fetch(presupuesto.semaforo, RANGO_URGENCIA[:sin_presupuesto])
  end

  def paginar(claves, pagina)
    total = claves.size
    paginas = [(total.to_f / POR_PAGINA).ceil, 1].max
    pagina_actual = pagina.to_i.clamp(1, paginas)
    inicio = (pagina_actual - 1) * POR_PAGINA
    pagina_de_claves = claves.slice(inicio, POR_PAGINA) || []
    { casos: filas_de_pagina(pagina_de_claves), pagina: pagina_actual, paginas: paginas, total: total }
  end
end
