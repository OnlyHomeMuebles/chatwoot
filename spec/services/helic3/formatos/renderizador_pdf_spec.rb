# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::RenderizadorPdf do
  # wait_thr real (objeto con pid/join/value) para no usar dobles sin verificar.
  def fake_wait_thr(exito:, finished:)
    estado = Object.new
    estado.define_singleton_method(:success?) { exito }
    estado.define_singleton_method(:exitstatus) { exito ? 0 : 1 }
    hilo = Object.new
    hilo.define_singleton_method(:pid) { 7777 }
    hilo.define_singleton_method(:join) { |_timeout| finished ? self : nil }
    hilo.define_singleton_method(:value) { estado }
    hilo
  end

  # escribe un PDF falso en la ruta que chromium recibiria en --print-to-pdf
  def escribir_pdf_falso(args, contenido)
    salida = args.find { |a| a.to_s.start_with?('--print-to-pdf=') }&.split('=', 2)&.last
    File.write(salida, contenido) if salida
  end

  # Simula a chromium: escribe (o no) el PDF y devuelve el wait_thr con su estado.
  def stub_chromium(escribe_pdf: true, exito: true, finished: true, contenido: "%PDF-1.4\nfake\n")
    hilo = fake_wait_thr(exito: exito, finished: finished)
    allow(Open3).to receive(:popen2e) do |*args, &blk|
      escribir_pdf_falso(args, contenido) if escribe_pdf
      blk.call(StringIO.new, StringIO.new(''), hilo)
    end
    hilo
  end

  describe '.call' do
    it 'devuelve los bytes del PDF cuando chromium termina bien' do
      stub_chromium

      expect(described_class.call('<html><body>hola</body></html>')).to start_with('%PDF')
    end

    it 'invoca el binario con los argumentos del ticket, sin shell' do
      stub_chromium

      described_class.call('<html></html>')

      expect(Open3).to have_received(:popen2e) do |*args|
        expect(args).to include('--headless', '--no-sandbox', '--disable-gpu', '--no-pdf-header-footer')
        expect(args.any? { |a| a.to_s.start_with?('--print-to-pdf=') }).to be(true)
        expect(args.last).to start_with('file://')
      end
    end

    it 'levanta Error si chromium sale con código != 0' do
      stub_chromium(exito: false, escribe_pdf: false)

      expect { described_class.call('<html></html>') }.to raise_error(described_class::Error, /código/)
    end

    it 'levanta Error si la salida no empieza con %PDF (nunca un PDF vacío)' do
      stub_chromium(contenido: 'no soy un pdf')

      expect { described_class.call('<html></html>') }.to raise_error(described_class::Error, /%PDF/)
    end

    it 'levanta Error si chromium no generó el archivo' do
      stub_chromium(escribe_pdf: false)

      expect { described_class.call('<html></html>') }.to raise_error(described_class::Error, /no generó/)
    end

    it 'mata el proceso (SIGKILL) y levanta Error si chromium se cuelga' do
      stub_chromium(finished: false, escribe_pdf: false)
      allow(Process).to receive(:kill)

      expect { described_class.call('<html></html>') }.to raise_error(described_class::Error, /excedió/)
      expect(Process).to have_received(:kill).with('KILL', 7777)
    end

    it 'no deja directorios temporales, ni cuando falla' do
      patron = File.join(Dir.tmpdir, 'helic3-pdf*')
      antes = Dir.glob(patron).size

      stub_chromium
      described_class.call('<html></html>')
      stub_chromium(exito: false, escribe_pdf: false)
      expect { described_class.call('<html></html>') }.to raise_error(described_class::Error)

      expect(Dir.glob(patron).size).to eq(antes)
    end
  end

  # El motor de PDF trabaja sobre el layout de impresion; se verifica aqui porque
  # es la pieza que FMT-01 entrega junto al servicio.
  describe 'layout de impresión (layouts/helic3/formato.html.erb)' do
    let(:html) do
      ActionController::Base.render(
        template: 'helic3/formatos/diagnostico',
        layout: 'helic3/formato',
        assigns: { fecha: '2026-09-28 10:00' }
      )
    end

    it 'no referencia ningún recurso remoto (todo va inline)' do
      expect(html).not_to match(%r{https?://})
    end

    it 'declara tamaño A4 y renderiza tildes y eñes' do
      expect(html).to include('size: A4')
      expect(html).to include('áéíóú', 'ñÑ')
    end
  end

  describe '.disponible?' do
    before { described_class.instance_variable_set(:@disponible, nil) }

    it 'es true cuando el binario responde a --version' do
      stub_chromium(escribe_pdf: false)

      expect(described_class.disponible?).to be(true)
    end

    it 'es false (sin reventar) cuando el binario no está' do
      allow(Open3).to receive(:popen2e).and_raise(Errno::ENOENT)

      expect(described_class.disponible?).to be(false)
    end

    it 'memoiza el resultado por proceso (una sola consulta al binario)' do
      stub_chromium(escribe_pdf: false)

      described_class.disponible?
      described_class.disponible?

      expect(Open3).to have_received(:popen2e).once
    end
  end
end
