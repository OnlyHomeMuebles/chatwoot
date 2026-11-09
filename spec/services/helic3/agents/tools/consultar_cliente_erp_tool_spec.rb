# frozen_string_literal: true

require 'rails_helper'

# ERP-06: la herramienta con la que el agente CONSULTA el ERP por cedula y trae, en texto, los
# datos del cliente + sus facturas para presentarselos y que el cliente los confirme. No guarda
# nada (eso es registrar_datos_cliente con fuente confirmado): solo traduce la consulta del
# dominio (Erp::Cache) al texto que el modelo relata.
RSpec.describe Helic3::Agents::Tools::ConsultarClienteErpTool do
  subject(:tool) { described_class.new }

  let(:account) { create(:account) }
  let(:tool_context) do
    Agents::ToolContext.new(run_context: Agents::RunContext.new(
      { account_id: account.id, state: { conversation_id: 1 } }
    ))
  end

  def consultar(cedula)
    tool.perform(tool_context, cedula: cedula)
  end

  let(:cliente) do
    Helic3::Erp::Customer.new(cedula: '26478046', nombre: 'MAGDA LLANOS',
                              telefono: '3219222701', email: 'magda@correo.com',
                              direccion: 'CR 1 A 1 62 115', ciudad: nil)
  end
  let(:factura) do
    Helic3::Erp::Invoice.new(numero: 'FV-974', fecha: '2023-04-03', total: 1_497_100.0, saldo: 0,
                             estado: 'pagada', centro_operacion: '012', items: [])
  end

  before { allow(Helic3::Erp).to receive(:habilitado?).and_return(true) }

  it 'trae el cliente y sus facturas en texto para presentarlos' do
    resultado = Helic3::Erp::Cache::Resultado.new(cliente: cliente, compras: [factura])
    expect(Helic3::Erp::Cache).to receive(:consultar).with(account: account, cedula: '26478046').and_return(resultado)

    texto = consultar('26478046')

    expect(texto).to include('MAGDA LLANOS', '3219222701', 'magda@correo.com', 'CR 1 A 1 62 115')
    expect(texto).to include('FV-974')
    expect(texto).to include('$1.497.100') # pesos con separador de miles, sin el .0 crudo
    expect(texto).to match(/confirm/i) # instruye al agente a confirmar antes de guardar
  end

  it 'omite el estado de la factura cuando Siesa no lo trae (no deja "estado" colgando)' do
    sin_estado = Helic3::Erp::Invoice.new(numero: 'FV-1', fecha: '2023-01-01', total: 50_000, saldo: 0,
                                          estado: '', centro_operacion: '012', items: [])
    resultado = Helic3::Erp::Cache::Resultado.new(cliente: cliente, compras: [sin_estado])
    allow(Helic3::Erp::Cache).to receive(:consultar).and_return(resultado)

    texto = consultar('26478046')
    expect(texto).to include('FV-1 del 2023-01-01 · total $50.000')
    expect(texto).not_to match(/estado\s*$/) # no queda "estado " vacio al final de la linea
  end

  it 'avisa cuando la ciudad no viene del ERP (codigo DANE, queda vacia)' do
    resultado = Helic3::Erp::Cache::Resultado.new(cliente: cliente, compras: [])
    allow(Helic3::Erp::Cache).to receive(:consultar).and_return(resultado)

    expect(consultar('26478046')).to match(/ciudad.*no.*(disponible|viene|trae)/i)
  end

  it 'dice que no hay facturas cuando el cliente no tiene compras' do
    resultado = Helic3::Erp::Cache::Resultado.new(cliente: cliente, compras: [])
    allow(Helic3::Erp::Cache).to receive(:consultar).and_return(resultado)

    expect(consultar('26478046')).to match(/sin facturas|no.*factura/i)
  end

  it 'si la cedula no esta en el ERP, pide los datos al cliente' do
    resultado = Helic3::Erp::Cache::Resultado.new(cliente: nil, compras: [])
    allow(Helic3::Erp::Cache).to receive(:consultar).and_return(resultado)

    expect(consultar('99999999')).to match(/no.*encontr|pid|a mano/i)
  end

  it 'con el ERP apagado no consulta y avisa que siga a mano' do
    allow(Helic3::Erp).to receive(:habilitado?).and_return(false)
    expect(Helic3::Erp::Cache).not_to receive(:consultar)

    expect(consultar('26478046')).to match(/ERP.*(no.*disponible|apagad|a mano)/i)
  end

  it 'con una cedula invalida avisa sin llamar al ERP' do
    expect(Helic3::Erp::Cache).not_to receive(:consultar)
    expect(consultar('123')).to match(/c[eé]dula/i)
  end

  it 'si el ERP esta caido (NoDisponible) no rompe: avisa que siga a mano' do
    allow(Helic3::Erp::Cache).to receive(:consultar).and_raise(Helic3::Erp::NoDisponible)

    expect(consultar('26478046')).to match(/no.*respond|a mano|intenta/i)
  end

  it 'normaliza la cedula (puntos/espacios) antes de consultar' do
    resultado = Helic3::Erp::Cache::Resultado.new(cliente: cliente, compras: [])
    expect(Helic3::Erp::Cache).to receive(:consultar).with(account: account, cedula: '26478046').and_return(resultado)

    consultar('26.478.046')
  end
end
