# frozen_string_literal: true

# DAT-01: escribe los datos del expediente respetando la procedencia. Un solo
# punto de escritura para los tres productores (el operador desde el panel, el
# agente con fuente ia, el ERP con fuente erp), para que la regla de quien pisa
# a quien viva en un lado y no repartida.
#
# Precedencia: humano > erp > ia. Lo que escribio una persona no lo sobreescribe
# el agente ni el ERP; lo que trajo el ERP no lo sobreescribe una deduccion del
# modelo. Al reves si. Es la unica logica del servicio.
class Helic3::Casos::RegistrarDatos
  # el rango ES la precedencia; sin dato previo = rango 0, cualquiera lo llena.
  RANGO = { 'ia' => 1, 'erp' => 2, 'humano' => 3 }.freeze

  def initialize(ticket:, campos:, fuente:)
    @ticket = ticket
    @campos = campos
    @fuente = fuente.to_s
  end

  def call
    # 1:1: si el expediente no tiene ficha se crea, si la tiene se actualiza.
    datos = @ticket.datos || @ticket.build_datos(account: @ticket.account)
    aplicar(datos)
    datos.save!
    datos
  end

  private

  def aplicar(datos)
    campos_validos.each do |campo, valor|
      next if valor.blank?           # un campo vacio NO borra el que habia
      next unless puede_pisar?(datos, campo)

      datos[campo] = valor
      datos.fuentes = datos.fuentes.merge(campo.to_s => @fuente)
    end
  end

  # solo los campos que la ficha conoce; cualquier otra llave se ignora. to_h
  # acepta tanto un hash del agente como los params permitidos del controlador.
  def campos_validos
    @campos.to_h.symbolize_keys.slice(*Helic3::TicketDato::CAMPOS)
  end

  # se escribe solo si la fuente nueva es de rango mayor o igual a la que ya
  # tenia ese campo. fetch (no []) para que una fuente invalida reviente ruidosa.
  def puede_pisar?(datos, campo)
    actual = RANGO[datos.fuentes[campo.to_s]] || 0
    RANGO.fetch(@fuente) >= actual
  end
end
