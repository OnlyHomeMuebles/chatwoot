# Lista de casos individuales de Devoluciones ("Detalle de clientes y casos",
# mismo patron de Helic3::Indicadores::Garantias): ordenada por urgencia
# (vencidas primero, solucionadas al final) y paginada. Vive en su propia
# clase (revision de Jhan en el PR #149) para no inflar
# Helic3::Indicadores::Devoluciones con lo que es, en esencia, una
# responsabilidad aparte -- el ordenamiento usa una clave liviana para TODAS
# las devoluciones filtradas, y solo las 7 de la pagina final pagan el costo
# de numero_radicado/cliente/centro/proceso.
class Helic3::Indicadores::DevolucionesCasos
  POR_PAGINA = 7
  RANGO_URGENCIA = { rojo: 0, amarillo: 1, verde: 2, sin_presupuesto: 3, resuelta: 4 }.freeze

  def initialize(account:, devoluciones_filtradas:)
    @account = account
    @devoluciones_filtradas = devoluciones_filtradas
  end

  def listar(pagina: 1)
    calendario = Helic3::CalendarioHabil.new
    parametros = Helic3::ParametrosGarantia.desde_catalogo(account, ambito: :garantia)
    ordenadas = devoluciones_filtradas
                .includes(items: :proceso)
                .map { |devolucion| clave_urgencia(devolucion, parametros, calendario) }
                .sort_by { |clave| [clave[:rango], clave[:devolucion_id]] }
    paginar(ordenadas, pagina)
  end

  private

  attr_reader :account, :devoluciones_filtradas

  def clave_urgencia(devolucion, parametros, calendario)
    resuelta = devolucion.resuelta?
    presupuesto = resuelta ? nil : devolucion.presupuesto(parametros: parametros, calendario: calendario)
    { devolucion_id: devolucion.id, resuelta: resuelta, presupuesto: presupuesto,
      rango: rango_urgencia_de_caso(resuelta, presupuesto) }
  end

  def filas_de_pagina(claves)
    devoluciones = Helic3::Devolucion.where(id: claves.pluck(:devolucion_id))
                                     .includes(:cobertura_ciudad, items: :proceso, ticket: { conversation: :contact })
                                     .index_by(&:id)
    claves.map { |clave| fila_de_caso(devoluciones.fetch(clave[:devolucion_id]), clave) }
  end

  def fila_de_caso(devolucion, clave)
    conversacion = devolucion.ticket.conversation
    {
      id: devolucion.id,
      numero_radicado: devolucion.numero_radicado,
      cliente: conversacion&.contact&.name,
      centro_operacion: devolucion.cobertura_ciudad&.nombre,
      proceso: devolucion.proceso_visible&.nombre,
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
