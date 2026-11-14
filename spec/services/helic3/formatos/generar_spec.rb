# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::Generar do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let(:item) { garantia.items.create!(account: account, producto_nombre: 'Sofá') }
  let(:formato) do
    Helic3::Catalogo::Formato.create!(account: account, nombre: 'No. 3 · Visita de técnico',
                                      codigo: 'visita_tecnica', posicion: 0)
  end

  def plantilla_activa(version: 1)
    formato.plantillas.create!(account: account, version: version, estado: 'activa', marcadores: %w[CLIENTE])
  end

  # VistaPrevia usa LibreOffice (no esta en el entorno de test); se stubea para
  # probar la logica de Generar, no la conversion (eso lo cubre VistaPrevia_spec).
  before do
    allow(Helic3::Formatos::VistaPrevia).to receive(:call).and_return(
      { bytes: 'PK demo', extension: 'docx',
        tipo_mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }
    )
  end

  it 'crea un Documento clase formato, origen operador, con el DOCX adjunto [CA1]' do
    plantilla_activa
    documento = described_class.call(ticket: ticket, item: item, formato: formato, user: user)

    expect(documento).to be_persisted
    expect(documento.clase).to eq('formato')
    expect(documento.origen).to eq('operador')
    expect(documento.garantia).to eq(garantia)
    expect(documento.remitente_nombre).to eq(user.name)
    expect(documento.archivo).to be_attached
    expect(Helic3::Formatos::VistaPrevia).to have_received(:call).with(hash_including(formato: :docx))
    expect(documento.archivo.filename.to_s).to end_with('.docx')
    expect(documento.archivo.content_type)
      .to eq('application/vnd.openxmlformats-officedocument.wordprocessingml.document')
  end

  it 'generar dos veces deja generación 1 y 2 con títulos distintos [CA2]' do
    plantilla_activa
    uno = described_class.call(ticket: ticket, item: item, formato: formato, user: user)
    dos = described_class.call(ticket: ticket, item: item, formato: formato, user: user)

    expect(uno.metadata['generacion']).to eq(1)
    expect(dos.metadata['generacion']).to eq(2)
    expect(uno.titulo).to end_with('generación 1')
    expect(dos.titulo).to end_with('generación 2')
  end

  it 'activar una versión nueva no cambia la metadata del documento ya generado [CA3]' do
    plantilla_activa(version: 1)
    documento = described_class.call(ticket: ticket, item: item, formato: formato, user: user)
    expect(documento.metadata['plantilla_version']).to eq(1)

    formato.plantillas.update_all(estado: 'retirada') # rubocop:disable Rails/SkipsModelValidations
    plantilla_activa(version: 2)

    expect(documento.reload.metadata['plantilla_version']).to eq(1)
  end

  it 'registra formato_generado en la bitácora con el nombre del actor [CA4]' do
    plantilla_activa
    expect do
      described_class.call(ticket: ticket, item: item, formato: formato, user: user)
    end.to change { ticket.eventos.where(tipo: 'formato_generado').count }.by(1)

    evento = ticket.eventos.find_by(tipo: 'formato_generado')
    expect(evento.origen).to eq('humano')
    expect(evento.payload['actor_nombre']).to eq(user.name)
  end

  it 'falla si el formato no tiene plantilla activa [CA5]' do
    expect do
      described_class.call(ticket: ticket, item: item, formato: formato, user: user)
    end.to raise_error(described_class::Error, /plantilla activa/)
  end

  it 'falla si el ítem es de otra garantía [CA5]' do
    plantilla_activa
    otro_item = Helic3::Garantia.create!(account: account, ticket: create(:ticket, account: account))
                                .items.create!(account: account, producto_nombre: 'Mesa')

    expect do
      described_class.call(ticket: ticket, item: otro_item, formato: formato, user: user)
    end.to raise_error(described_class::Error, /este expediente/)
  end

  it 'un formato desactivado no se puede generar aunque tenga plantilla activa [bug A Jhan #117]' do
    plantilla_activa
    formato.update!(activo: false)

    expect do
      described_class.call(ticket: ticket, item: item, formato: formato, user: user)
    end.to raise_error(described_class::Error, /desactivado/)
  end

  # FMT-07: lo que el operador escribe en el modal viaja al documento y a la metadata,
  # pero no toca la base; y faltan los editables obligatorios bloquea la generacion.
  describe 'valores_producto (FMT-07)' do
    it 'lleva lo escrito en el modal al documento, a la metadata y al título' do
      formato.plantillas.create!(account: account, version: 1, estado: 'activa', marcadores: %w[PRODUCTO])

      documento = described_class.call(ticket: ticket, item: item, formato: formato, user: user,
                                       valores_producto: { 'PRODUCTO' => 'Mueble' })

      expect(Helic3::Formatos::VistaPrevia).to have_received(:call)
        .with(hash_including(valores_producto: { 'PRODUCTO' => 'Mueble' }))
      expect(documento.metadata['valores']['PRODUCTO']).to eq('Mueble')
      expect(documento.metadata['valores_editados']).to eq({ 'PRODUCTO' => 'Mueble' })
      expect(documento.titulo).to include('Mueble')
      expect(item.reload.producto_nombre).to eq('Sofá') # la base NO cambia
    end

    it 'responde 422 si la plantilla usa un marcador editable y queda vacío' do
      formato.plantillas.create!(account: account, version: 1, estado: 'activa',
                                 marcadores: %w[PRODUCTO PRODUCTO_NUEVO])

      expect do
        described_class.call(ticket: ticket, item: item, formato: formato, user: user)
      end.to raise_error(described_class::Error, /Producto nuevo/)
    end

    it 'genera si la plantilla NO usa el marcador editable vacío' do
      formato.plantillas.create!(account: account, version: 1, estado: 'activa', marcadores: %w[PRODUCTO])

      documento = described_class.call(ticket: ticket, item: item, formato: formato, user: user)

      expect(documento).to be_persisted
    end
  end
end
