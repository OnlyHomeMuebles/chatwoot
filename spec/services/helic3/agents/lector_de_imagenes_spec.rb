# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::LectorDeImagenes do
  # Doble de lo que devuelve Down.download: un Tempfile con .path, .close, .unlink.
  def archivo_descargado(path)
    instance_double(Tempfile, path: path, close: nil, unlink: nil)
  end

  it 'devuelve nil si no hay imagenes' do
    expect(described_class.leer(nil)).to be_nil
    expect(described_class.leer([])).to be_nil
  end

  it 'descarga la imagen y devuelve el texto que lee tesseract' do
    url = 'https://cdn.chatwoot.test/factura.jpg'
    archivo = archivo_descargado('/tmp/helic3-ocr123.jpg')

    expect(Down).to receive(:download).with(url, max_size: anything, read_timeout: anything).and_return(archivo)
    rtess = instance_double(RTesseract)
    expect(RTesseract).to receive(:new).with('/tmp/helic3-ocr123.jpg', lang: described_class::IDIOMA).and_return(rtess)
    expect(rtess).to receive(:to_s).and_return("Factura N.° 8821\n")

    expect(described_class.leer([url])).to eq('Factura N.° 8821')
  end

  it 'concatena el texto de varias imagenes, separado por un delimitador' do
    urls = ['https://cdn.chatwoot.test/factura.jpg', 'https://cdn.chatwoot.test/cedula.jpg']
    archivo1 = archivo_descargado('/tmp/a.jpg')
    archivo2 = archivo_descargado('/tmp/b.jpg')
    rtess1 = instance_double(RTesseract, to_s: 'Factura 8821')
    rtess2 = instance_double(RTesseract, to_s: 'CC 1032456789')

    allow(Down).to receive(:download).and_return(archivo1, archivo2)
    allow(RTesseract).to receive(:new).and_return(rtess1, rtess2)

    expect(described_class.leer(urls)).to eq("Factura 8821\n---\nCC 1032456789")
  end

  it 'devuelve nil cuando tesseract no encuentra texto (foto del producto, no de un documento)' do
    url = 'https://cdn.chatwoot.test/silla-rota.jpg'
    archivo = archivo_descargado('/tmp/c.jpg')
    allow(Down).to receive(:download).and_return(archivo)
    allow(RTesseract).to receive(:new).and_return(instance_double(RTesseract, to_s: '   '))

    expect(described_class.leer([url])).to be_nil
  end

  it 'devuelve nil (y deja rastro en el log) si la descarga o tesseract fallan, sin tumbar el job' do
    allow(Down).to receive(:download).and_raise(Down::Error, 'timeout')
    expect(Rails.logger).to receive(:error).with(a_string_matching(/lector_de_imagenes fallo/))

    expect(described_class.leer(['https://cdn.chatwoot.test/foto.jpg'])).to be_nil
  end
end
