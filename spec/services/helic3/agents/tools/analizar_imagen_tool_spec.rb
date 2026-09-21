# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::Tools::AnalizarImagenTool do
  subject(:tool) { described_class.new }

  def tool_context(imagenes: nil)
    state = imagenes.nil? ? {} : { imagenes: imagenes }
    Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: state }))
  end

  # Doble de lo que devuelve Down.download: un Tempfile con .path, .close, .unlink.
  def archivo_descargado(path)
    instance_double(Tempfile, path: path, close: nil, unlink: nil)
  end

  it 'avisa si el cliente no adjuntó ninguna imagen en su ultimo mensaje' do
    expect(tool.perform(tool_context)).to match(/no adjuntó ninguna imagen/i)
  end

  it 'avisa igual si el state trae un array de imagenes vacio' do
    expect(tool.perform(tool_context(imagenes: []))).to match(/no adjuntó ninguna imagen/i)
  end

  it 'descarga la imagen y devuelve el texto que lee tesseract' do
    url = 'https://cdn.chatwoot.test/factura.jpg'
    archivo = archivo_descargado('/tmp/helic3-ocr123.jpg')

    expect(Down).to receive(:download).with(url, max_size: anything, read_timeout: anything).and_return(archivo)
    rtess = instance_double(RTesseract)
    expect(RTesseract).to receive(:new).with('/tmp/helic3-ocr123.jpg', lang: described_class::IDIOMA).and_return(rtess)
    expect(rtess).to receive(:to_s).and_return("Factura N.° 8821\n")

    expect(tool.perform(tool_context(imagenes: [url]))).to eq('Factura N.° 8821')
  end

  it 'concatena el texto de varias imagenes, separado por un delimitador' do
    urls = ['https://cdn.chatwoot.test/factura.jpg', 'https://cdn.chatwoot.test/cedula.jpg']
    archivo1 = archivo_descargado('/tmp/a.jpg')
    archivo2 = archivo_descargado('/tmp/b.jpg')
    rtess1 = instance_double(RTesseract, to_s: 'Factura 8821')
    rtess2 = instance_double(RTesseract, to_s: 'CC 1032456789')

    allow(Down).to receive(:download).and_return(archivo1, archivo2)
    allow(RTesseract).to receive(:new).and_return(rtess1, rtess2)

    expect(tool.perform(tool_context(imagenes: urls))).to eq("Factura 8821\n---\nCC 1032456789")
  end

  it 'avisa que no hay texto legible cuando tesseract no encuentra nada (foto del producto, no de un documento)' do
    url = 'https://cdn.chatwoot.test/silla-rota.jpg'
    archivo = archivo_descargado('/tmp/c.jpg')
    allow(Down).to receive(:download).and_return(archivo)
    allow(RTesseract).to receive(:new).and_return(instance_double(RTesseract, to_s: '   '))

    resultado = tool.perform(tool_context(imagenes: [url]))
    expect(resultado).to match(/no se encontró texto legible/i)
  end

  it 'devuelve un mensaje legible (y deja rastro en el log) si la descarga o tesseract fallan' do
    allow(Down).to receive(:download).and_raise(Down::Error, 'timeout')
    expect(Rails.logger).to receive(:error).with(a_string_matching(/analizar_imagen fallo/))

    resultado = tool.perform(tool_context(imagenes: ['https://cdn.chatwoot.test/foto.jpg']))
    expect(resultado).to match(/no se pudo leer la imagen/i)
  end
end
