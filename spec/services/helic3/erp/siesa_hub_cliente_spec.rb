# frozen_string_literal: true

require 'rails_helper'

# ERP-05: cliente HTTP de Siesa HUB (estandar/consulta/v3). Arma la consulta con las
# credenciales en headers y el filtro en `parametros`. Un 400 con codigo:1 ("sin
# registros") NO es error; otros 4xx/5xx y los fallos de red si.
RSpec.describe Helic3::Erp::SiesaHubCliente do
  subject(:cliente) do
    described_class.new(base_url: 'https://apiqa.siesacloud.com', client_id: 'cid',
                        conni_key: 'ck', conni_token: 'ct', id_compania: '901559759')
  end

  let(:url) { 'https://apiqa.siesacloud.com/siesahub/siesa/estandar/consulta/v3' }

  # Los reintentos no deben dormir de verdad en las pruebas.
  before { allow(cliente).to receive(:sleep) }

  it 'manda credenciales en headers + filtro en parametros y devuelve el JSON (codigo 0)' do
    peticion = stub_request(:get, url)
               .with(query: hash_including('descripcion' => 'API_v2_Ventas_Facturas_DesdePedido',
                                           'idCompania' => '901559759',
                                           'parametros' => "f200_nit_fact=''26478046''"),
                     headers: { 'client_id' => 'cid', 'ConniKey' => 'ck', 'ConniToken' => 'ct' })
               .to_return(status: 200, body: { 'codigo' => 0, 'detalle' => { 'Table' => [] } }.to_json,
                          headers: { 'Content-Type' => 'application/json' })

    resultado = cliente.consultar(descripcion: 'API_v2_Ventas_Facturas_DesdePedido',
                                  parametros: "f200_nit_fact=''26478046''")

    expect(resultado['codigo']).to eq(0)
    expect(peticion).to have_been_requested
  end

  it 'un 400 con codigo:1 (sin registros) NO es error: devuelve el cuerpo' do
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: 400, body: { 'codigo' => 1, 'mensaje' => 'Error' }.to_json,
                                      headers: { 'Content-Type' => 'application/json' })

    expect(cliente.consultar(descripcion: 'X', parametros: 'y')['codigo']).to eq(1)
  end

  it 'un 400 con codigo distinto de 1 (credenciales o SQL malo) SI es error' do
    # No todo 400 es "sin registros": un filtro invalido o credenciales malas tambien dan 400.
    # Tratarlo como vacio enmascararia el problema; debe salir como ErrorConsulta -> 503.
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: 400, body: { 'codigo' => 2, 'detalle' => 'SQL invalido' }.to_json,
                                      headers: { 'Content-Type' => 'application/json' })

    expect { cliente.consultar(descripcion: 'X', parametros: 'y') }
      .to raise_error(described_class::ErrorConsulta)
  end

  it 'un 500 levanta ErrorConsulta' do
    stub_request(:get, url).with(query: hash_including({})).to_return(status: 500, body: 'boom')

    expect { cliente.consultar(descripcion: 'X', parametros: 'y') }
      .to raise_error(described_class::ErrorConsulta)
  end

  it 'un timeout levanta ErrorConsulta' do
    stub_request(:get, url).with(query: hash_including({})).to_timeout

    expect { cliente.consultar(descripcion: 'X', parametros: 'y') }
      .to raise_error(described_class::ErrorConsulta)
  end

  it 'ErrorConsulta es un NoDisponible (contrato del modulo)' do
    expect(described_class::ErrorConsulta.ancestors).to include(Helic3::Erp::NoDisponible)
  end

  it 'reintenta ante un 5xx transitorio y devuelve el cuerpo si luego responde' do
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return({ status: 503, body: 'down' },
                                      { status: 200,
                                        body: { 'codigo' => 0, 'detalle' => { 'Table' => [] } }.to_json,
                                        headers: { 'Content-Type' => 'application/json' } })

    expect(cliente.consultar(descripcion: 'X', parametros: 'y')['codigo']).to eq(0)
  end

  it 'avisa en el log si la pagina llega llena (puede faltar paginar)' do
    filas = Array.new(100) { { 'f350_rowid' => 1 } }
    stub_request(:get, url).with(query: hash_including({}))
                           .to_return(status: 200,
                                      body: { 'codigo' => 0, 'detalle' => { 'Table' => filas } }.to_json,
                                      headers: { 'Content-Type' => 'application/json' })
    expect(Rails.logger).to receive(:warn).with(/pagina llena/)

    cliente.consultar(descripcion: 'X', parametros: 'y', tam_pag: 100)
  end
end
