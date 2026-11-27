# frozen_string_literal: true

# MIG-02 (regla 2): la numeración por cuenta de PQR y garantías. La usan la migración
# (subir antes / dejar en MAX al final), el vaciado y revertir (dejar en el valor
# inicial). Sin filas, cada secuencia queda en su inicio con is_called: false, para que
# el próximo nextval devuelva exactamente ese número: PQR en 1, garantías en el
# parámetro radicado_garantia_inicio.
class Helic3::Migracion::Secuencias
  def initialize(account)
    @account = account
  end

  # el próximo nextval de ambas devuelve tope + 1
  def subir_a(tope)
    [ticket, garantia].each { |secuencia| fijar(secuencia, tope, llamada: true) }
  end

  def dejar_en_max
    max_ticket = max_display_id(:helic3_tickets)
    max_ticket ? fijar(ticket, max_ticket, llamada: true) : fijar(ticket, 1, llamada: false)

    max_garantia = max_display_id(:helic3_garantias)
    if max_garantia && max_garantia >= inicio_garantia
      fijar(garantia, max_garantia, llamada: true)
    else
      fijar(garantia, inicio_garantia, llamada: false)
    end
  end

  def reiniciar
    fijar(ticket, 1, llamada: false)
    fijar(garantia, inicio_garantia, llamada: false)
  end

  def max_display_id(tabla)
    conexion.select_value("SELECT MAX(display_id) FROM #{tabla} WHERE account_id = #{@account.id}")
  end

  private

  def fijar(secuencia, valor, llamada:)
    conexion.execute("CREATE SEQUENCE IF NOT EXISTS #{secuencia}")
    conexion.execute("SELECT setval('#{secuencia}', #{valor}, #{llamada})")
  end

  def ticket
    "helic3_ticket_dpid_seq_#{@account.id}"
  end

  def garantia
    "helic3_garantia_dpid_seq_#{@account.id}"
  end

  def inicio_garantia
    @inicio_garantia ||= Helic3::Catalogo::Parametro.find_by(account_id: @account.id,
                                                             clave: 'radicado_garantia_inicio')&.valor_entero || 1
  end

  def conexion
    ActiveRecord::Base.connection
  end
end
