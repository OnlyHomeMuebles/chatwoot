# frozen_string_literal: true

# ERP-06/T3: en modo BD (agentes_desde_bd = true), Helic3::Agents::SeederService#sembrar!
# solo CREA agentes que no existen (next if exists?): donde agente_pqrs ya estaba sembrado
# antes de que este ticket agregara consultar_cliente_erp a su lista de herramientas, la
# fila se queda con la lista vieja para siempre. Esta migracion la pone al dia una sola vez,
# sin tocar nada mas del registro (en particular, nunca el prompt: puede tener ediciones
# del administrador, y las reglas de uso del ERP dependen de una decision pendiente).
class AgregaConsultarClienteErpAAgentePqrs < ActiveRecord::Migration[7.2]
  HERRAMIENTA = 'consultar_cliente_erp'

  def up
    Helic3::Agente.where(codigo: 'agente_pqrs').find_each do |agente|
      next if agente.herramientas.include?(HERRAMIENTA)

      agente.update!(herramientas: agente.herramientas + [HERRAMIENTA])
    end
  end

  def down
    say 'ERP-06/T3 no revierte: quitar la herramienta podria romper un prompt que ya cuenta con ella.'
  end
end
