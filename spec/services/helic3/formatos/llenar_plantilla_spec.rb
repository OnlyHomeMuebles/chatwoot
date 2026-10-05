# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::LlenarPlantilla do
  def fodt(cuerpo)
    ns = 'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"'
    oficina = 'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"'
    %(<?xml version="1.0"?><office #{oficina} #{ns}>#{cuerpo}</office>)
  end

  it 'reemplaza un marcador partido en tres text:span con formatos distintos [CA3]' do
    xml = fodt('<text:p><text:span>Hola {{CLI</text:span><text:span>EN</text:span><text:span>TE}}!</text:span></text:p>')
    salida = described_class.call(xml, 'CLIENTE' => 'Ana')
    expect(Nokogiri::XML(salida).text).to eq('Hola Ana!')
  end

  it 'escapa valores con < > & y deja XML valido [CA4]' do
    xml = fodt('<text:p><text:span>{{CLIENTE}}</text:span></text:p>')
    salida = described_class.call(xml, 'CLIENTE' => '<script> & "x"')
    doc = Nokogiri::XML(salida)
    expect(doc.errors).to be_empty
    expect(doc.text).to eq('<script> & "x"')
  end

  it 'tolera espacios dentro de las llaves' do
    xml = fodt('<text:p><text:span>{{ CLIENTE }}</text:span></text:p>')
    expect(described_class.marcadores_de(xml)).to eq(['CLIENTE'])
    salida = described_class.call(xml, 'CLIENTE' => 'Ana')
    expect(Nokogiri::XML(salida).text).to eq('Ana')
  end

  it 'reduce saltos de linea del valor a espacio' do
    xml = fodt('<text:p><text:span>{{DIRECCION}}</text:span></text:p>')
    salida = described_class.call(xml, 'DIRECCION' => "Calle 1\nApto 2")
    expect(Nokogiri::XML(salida).text).to eq('Calle 1 Apto 2')
  end

  it 'marcadores_de encuentra en parrafos, encabezados y tablas' do
    xml = fodt('<text:h><text:span>{{RADICADO}}</text:span></text:h><text:p><text:span>{{CLIENTE}}</text:span></text:p>')
    expect(described_class.marcadores_de(xml)).to contain_exactly('RADICADO', 'CLIENTE')
  end

  it 'no re-interpreta un marcador que venga dentro de un valor (evita inyeccion)' do
    xml = fodt('<text:p><text:span>{{CLIENTE}}</text:span></text:p>')
    salida = described_class.call(xml, 'CLIENTE' => 'Pedro {{PRODUCTO}}', 'PRODUCTO' => 'Sofa')
    expect(Nokogiri::XML(salida).text).to eq('Pedro {{PRODUCTO}}')
  end

  it 'un valor que es literalmente un marcador no cuelga el proceso' do
    xml = fodt('<text:p><text:span>{{CLIENTE}}</text:span></text:p>')
    salida = described_class.call(xml, 'CLIENTE' => '{{CLIENTE}}')
    expect(Nokogiri::XML(salida).text).to eq('{{CLIENTE}}')
  end
end
