# frozen_string_literal: true

require 'rails_helper'

# ERP-05: parser de la consulta de clientes de Siesa HUB. Arma el Customer con identificacion,
# nombre y contacto (telefono, correo, direccion). La ciudad viene como codigo (idCiudad/idDepto),
# no como nombre, asi que por ahora queda nil (traducir el codigo DANE es un follow-up).
RSpec.describe Helic3::Erp::SiesaClientes do
  # Fila como la devuelve la consulta real (campos camelCase, sin prefijo f200_).
  def fila(overrides = {})
    { 'id' => '26478046', 'razonSocial' => 'LLANOS HERRERA MAGDA JOHANA',
      'apellido1' => 'LLANOS', 'apellido2' => 'HERRERA', 'nombres' => 'MAGDA JOHANA',
      'direccion1' => 'CR 1 A 1 62 115', 'idCiudad' => '001', 'idDepto' => '63',
      'telefono' => '3219222701', 'email' => 'JOHNALLANOS@HOTMAIL.COM' }.merge(overrides)
  end

  def respuesta(*filas)
    { 'codigo' => 0, 'detalle' => { 'Table' => filas } }
  end

  it 'arma el nombre en orden natural y trae telefono, correo y direccion' do
    cli = described_class.parsear(respuesta(fila), cedula: '26478046')

    expect(cli.nombre).to eq('MAGDA JOHANA LLANOS HERRERA')
    expect(cli.cedula).to eq('26478046')
    expect(cli.telefono).to eq('3219222701')
    expect(cli.email).to eq('JOHNALLANOS@HOTMAIL.COM')
    expect(cli.direccion).to eq('CR 1 A 1 62 115')
  end

  it 'deja la ciudad en nil (viene como codigo, no como nombre; traducir DANE es follow-up)' do
    expect(described_class.parsear(respuesta(fila), cedula: '26478046').ciudad).to be_nil
  end

  it 'para una empresa (sin nombres) usa la razon social' do
    empresa = fila('nombres' => '', 'razonSocial' => 'MUEBLES ONLY HOME SAS')
    expect(described_class.parsear(respuesta(empresa), cedula: '900123456').nombre).to eq('MUEBLES ONLY HOME SAS')
  end

  it 'con filas duplicadas (una por empresa idCia) arma un solo cliente con la primera' do
    cli = described_class.parsear(respuesta(fila('idCia' => 1), fila('idCia' => 2)), cedula: '26478046')
    expect(cli).to be_a(Helic3::Erp::Customer)
    expect(cli.nombre).to eq('MAGDA JOHANA LLANOS HERRERA')
  end

  it 'campos de contacto vacios quedan en nil, no en cadena vacia' do
    cli = described_class.parsear(respuesta(fila('telefono' => '', 'email' => '', 'direccion1' => '')),
                                  cedula: '26478046')
    expect(cli.telefono).to be_nil
    expect(cli.email).to be_nil
    expect(cli.direccion).to be_nil
  end

  it 'devuelve nil si la cedula no esta en el maestro (sin registros)' do
    sin_registros = { 'codigo' => 1, 'detalle' => 'No se encontraron registros' }
    expect(described_class.parsear(sin_registros, cedula: '999')).to be_nil
  end
end
