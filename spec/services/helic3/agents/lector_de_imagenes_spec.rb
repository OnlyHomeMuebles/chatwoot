# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::LectorDeImagenes do
  # ssrf_filter resuelve el host antes de pedir permiso: sin esto, el dominio
  # de prueba no resuelve a nada y SafeFetch lo rechaza antes de llegar a WebMock.
  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('cdn.chatwoot.test').and_return(['93.184.216.34'])
  end

  def responder_con_imagen(url, cuerpo: File.read(Rails.root.join('spec/assets/avatar.png')))
    stub_request(:get, url).to_return(status: 200, body: cuerpo, headers: { 'Content-Type' => 'image/png' })
  end

  it 'devuelve nil si no hay imagenes' do
    expect(described_class.leer(nil)).to be_nil
    expect(described_class.leer([])).to be_nil
  end

  it 'descarga la imagen via SafeFetch (protegido contra SSRF) y devuelve el texto que lee tesseract' do
    url = 'https://cdn.chatwoot.test/factura.jpg'
    responder_con_imagen(url)
    rtess = instance_double(RTesseract, to_s: "Factura N.° 8821\n")
    expect(RTesseract).to receive(:new).with(a_string_matching(%r{\A/}), lang: described_class::IDIOMA).and_return(rtess)

    expect(described_class.leer([url])).to eq('Factura N.° 8821')
  end

  it 'concatena el texto de varias imagenes, separado por un delimitador' do
    url1 = 'https://cdn.chatwoot.test/factura.jpg'
    url2 = 'https://cdn.chatwoot.test/cedula.jpg'
    responder_con_imagen(url1)
    responder_con_imagen(url2)
    rtess1 = instance_double(RTesseract, to_s: 'Factura 8821')
    rtess2 = instance_double(RTesseract, to_s: 'CC 1032456789')
    allow(RTesseract).to receive(:new).and_return(rtess1, rtess2)

    expect(described_class.leer([url1, url2])).to eq("Factura 8821\n---\nCC 1032456789")
  end

  it 'devuelve nil cuando tesseract no encuentra texto (foto del producto, no de un documento)' do
    url = 'https://cdn.chatwoot.test/silla-rota.jpg'
    responder_con_imagen(url)
    allow(RTesseract).to receive(:new).and_return(instance_double(RTesseract, to_s: '   '))

    expect(described_class.leer([url])).to be_nil
  end

  it 'una imagen que falla no borra el texto que ya se leyo de las demas' do
    url_buena = 'https://cdn.chatwoot.test/factura.jpg'
    url_mala = 'https://cdn.chatwoot.test/rota.jpg'
    responder_con_imagen(url_buena)
    stub_request(:get, url_mala).to_timeout
    allow(RTesseract).to receive(:new).and_return(instance_double(RTesseract, to_s: 'Factura 8821'))
    allow(Rails.logger).to receive(:error)

    expect(described_class.leer([url_buena, url_mala])).to eq('Factura 8821')
    expect(Rails.logger).to have_received(:error).with(a_string_matching(/lector_de_imagenes fallo con #{url_mala}/))
  end

  it 'rechaza un content-type que no sea imagen (SafeFetch), sin tumbar el job' do
    url = 'https://cdn.chatwoot.test/no-es-imagen'
    stub_request(:get, url).to_return(status: 200, body: '<html></html>', headers: { 'Content-Type' => 'text/html' })
    expect(Rails.logger).to receive(:error).with(a_string_matching(/lector_de_imagenes fallo/))

    expect(described_class.leer([url])).to be_nil
  end

  it 'corta y sigue si tesseract se cuelga mas de TIMEOUT_OCR (shell-out sin limite propio)' do
    url = 'https://cdn.chatwoot.test/factura.jpg'
    responder_con_imagen(url)
    allow(RTesseract).to receive(:new) { sleep 0.2 }
    stub_const('Helic3::Agents::LectorDeImagenes::TIMEOUT_OCR', 0.05)
    expect(Rails.logger).to receive(:error).with(a_string_matching(/lector_de_imagenes fallo/))

    expect(described_class.leer([url])).to be_nil
  end

  it 'devuelve nil (y deja rastro en el log) si la descarga falla, sin tumbar el job' do
    url = 'https://cdn.chatwoot.test/foto.jpg'
    stub_request(:get, url).to_raise(SocketError)
    expect(Rails.logger).to receive(:error).with(a_string_matching(/lector_de_imagenes fallo/))

    expect(described_class.leer([url])).to be_nil
  end

  # Chatwoot arma la URL del adjunto con FRONTEND_URL (0.0.0.0/localhost en
  # desarrollo Docker). Esa URL sirve para el navegador del cliente, pero este
  # worker de Sidekiq vive en OTRO contenedor: su `localhost` es él mismo y a
  # `0.0.0.0` nadie se conecta. Por eso reescribimos SOLO esos hosts de bucle
  # local al host interno del servicio (rails:3000) antes de descargar.
  it 'reescribe el host de bucle local al host interno del servicio antes de descargar' do
    stub_const("#{described_class}::HOST_INTERNO", 'rails:3000')
    allow(Resolv).to receive(:getaddresses).with('rails').and_return(['93.184.216.34'])
    url_navegador = 'http://0.0.0.0:3000/rails/active_storage/blobs/factura.jpg'
    url_interna = 'http://rails:3000/rails/active_storage/blobs/factura.jpg'
    responder_con_imagen(url_interna)
    allow(RTesseract).to receive(:new).and_return(instance_double(RTesseract, to_s: 'Factura 8821'))

    expect(described_class.leer([url_navegador])).to eq('Factura 8821')
    expect(a_request(:get, url_navegador)).not_to have_been_made
    expect(a_request(:get, url_interna)).to have_been_made
  end

  it 'no toca una URL externa (CDN de WhatsApp/Instagram): su host no es de bucle local' do
    url = 'https://cdn.chatwoot.test/factura.jpg'
    responder_con_imagen(url)
    allow(RTesseract).to receive(:new).and_return(instance_double(RTesseract, to_s: 'ok'))

    expect(described_class.leer([url])).to eq('ok')
    expect(a_request(:get, url)).to have_been_made
  end
end
