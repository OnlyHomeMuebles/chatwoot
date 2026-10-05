# frozen_string_literal: true

require 'rails_helper'

# FMT-01 rev: se stubea Open3 porque LibreOffice no corre en el entorno de test;
# el stub escribe el archivo de salida esperado en el --outdir y simula el proceso.
RSpec.describe Helic3::Formatos::Conversor do
  after { described_class.instance_variable_set(:@disponible, nil) }

  # Escribe la salida esperada (<base>.<convert-to>) en el --outdir del comando.
  def escribir_salida(args, contenido)
    destino = args[args.index('--convert-to') + 1]
    outdir = args[args.index('--outdir') + 1]
    base = File.basename(args.last, File.extname(args.last))
    File.binwrite(File.join(outdir, "#{base}.#{destino}"), contenido)
  end

  # El wait_thread de Open3 no tiene una clase publica estable (es un Thread con
  # metodos de proceso agregados: #pid, #value), por eso un double simple.
  def hilo_falso(exito:, cuelga:, pid: 7777)
    estado = instance_double(Process::Status, success?: exito, exitstatus: exito ? 0 : 1)
    double('wait_thread', value: estado, pid: pid).tap do |t| # rubocop:disable RSpec/VerifiedDoubles
      allow(t).to receive_messages(join: cuelga ? nil : true, kill: nil)
    end
  end

  def stub_soffice(contenido: '%PDF-1.7 ok', exito: true, cuelga: false)
    allow(Process).to receive(:kill)
    allow(Open3).to receive(:popen2e) do |*args, **_opts, &blk|
      escribir_salida(args, contenido) unless cuelga
      blk.call(StringIO.new, StringIO.new(''), hilo_falso(exito: exito, cuelga: cuelga))
    end
  end

  describe '.a_pdf' do
    it 'convierte un .docx a PDF y devuelve los bytes' do
      stub_soffice(contenido: '%PDF-1.7 contenido')

      expect(described_class.a_pdf('docx-bytes', extension: 'docx')).to start_with('%PDF')
    end

    it 'acepta un .fodt ya relleno como entrada' do
      stub_soffice

      expect { described_class.a_pdf('<office/>', extension: 'fodt') }.not_to raise_error
    end

    it 'levanta Error si la salida no empieza con %PDF' do
      stub_soffice(contenido: 'esto no es un pdf')

      expect { described_class.a_pdf('docx', extension: 'docx') }
        .to raise_error(described_class::Error, /%PDF/)
    end

    it 'rechaza una extension de entrada no soportada' do
      expect { described_class.a_pdf('x', extension: 'xlsx') }
        .to raise_error(described_class::Error, /no soportada/)
    end
  end

  describe '.a_fodt' do
    it 'convierte un .docx a .fodt (OpenDocument plano)' do
      stub_soffice(contenido: '<?xml version="1.0"?><office:document/>')

      expect(described_class.a_fodt('docx-bytes')).to include('office:document')
    end
  end

  describe '.a_docx' do
    it 'convierte un .fodt a .docx y devuelve bytes que empiezan con PK (zip)' do
      stub_soffice(contenido: "PK\x03\x04 docx")

      expect(described_class.a_docx('<office/>', extension: 'fodt')).to start_with('PK')
    end

    it 'levanta Error si la salida no parece un .docx (sin PK)' do
      stub_soffice(contenido: 'no es docx')

      expect { described_class.a_docx('<office/>', extension: 'fodt') }
        .to raise_error(described_class::Error, /docx/)
    end
  end

  describe 'aislamiento por conversion (concurrencia, CA3)' do
    it 'cada conversion usa su propio -env:UserInstallation' do
      perfiles = []
      allow(Process).to receive(:kill)
      allow(Open3).to receive(:popen2e) do |*args, **_opts, &blk|
        perfiles << args.find { |arg| arg.to_s.start_with?('-env:UserInstallation=') }
        escribir_salida(args, '%PDF-1.7')
        blk.call(StringIO.new, StringIO.new(''), hilo_falso(exito: true, cuelga: false, pid: 1))
      end

      described_class.a_pdf('a', extension: 'docx')
      described_class.a_pdf('b', extension: 'docx')

      expect(perfiles.compact.size).to eq(2)
      expect(perfiles.uniq.size).to eq(2)
    end
  end

  describe 'robustez (CA4)' do
    it 'mata el grupo de procesos y levanta Error al vencer el timeout' do
      stub_soffice(cuelga: true)

      expect { described_class.a_pdf('docx', extension: 'docx') }
        .to raise_error(described_class::Error, /límite/)
      expect(Process).to have_received(:kill).with('KILL', -7777)
    end

    it 'levanta Error si soffice sale con codigo != 0' do
      stub_soffice(exito: false)

      expect { described_class.a_pdf('docx', extension: 'docx') }
        .to raise_error(described_class::Error, /código/)
    end

    it 'disponible? es false si el binario no responde' do
      allow(Open3).to receive(:popen2e).and_raise(Errno::ENOENT)

      expect(described_class.disponible?).to be(false)
    end
  end
end
