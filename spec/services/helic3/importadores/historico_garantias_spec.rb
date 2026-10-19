# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Importadores::HistoricoGarantias do
  let(:account) { create(:account) }

  let!(:bogota) { Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Bogotá', codigo: 'bogota') }
  let!(:calidad) do
    Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Calidad - producto comprado',
                                             codigo: 'calidad_producto_comprado')
  end
  let!(:chapilla) do
    Helic3::Catalogo::DetalleTipificado.create!(account: account, nombre: 'Chapilla leventada', codigo: 'chapilla')
  end
  let!(:entrega) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Entrega de producto',
                                              codigo: 'entrega_producto', posicion: 4, es_terminal: true)
  end

  def encabezados_historico
    [
      'Consecutivo', 'Prioridad', 'Centros de operacion', 'Fecha de creación', 'Alerta de vencimiento',
      'Etapa del Caso', 'Proceso PQR', 'Motivo', 'Detalle Tipificado', 'Cliente', 'Telefono de contacto',
      'Cliente potencial', 'Responsable', 'Fecha Última Compra', 'Fecha de Finalizacion', 'productos', 'Ciudad'
    ]
  end

  def escribir_csv(filas)
    encabezados = encabezados_historico
    archivo = Tempfile.new(['historico', '.csv'])
    CSV.open(archivo.path, 'w') do |csv|
      csv << encabezados
      filas.each { |fila| csv << encabezados.map { |columna| fila[columna] } }
    end
    archivo.path
  end

  def importar(filas)
    described_class.new(account: account, ruta: escribir_csv(filas)).importar!
  end

  describe 'una fila con catalogos escritos distinto al catalogo (acentos/mayusculas/alias)' do
    before do
      importar([{
                 'Consecutivo' => '2346', 'Prioridad' => 'Baja', 'Fecha de creación' => '2026-06-18T15:15:38',
                 'Proceso PQR' => 'ENTREGA PRODUCTO', 'Motivo' => 'Calidad - Producto Comprado',
                 'Detalle Tipificado' => 'Chapilla levantada', 'Cliente' => 'Cliente de prueba',
                 'Fecha de Finalizacion' => '2026-07-30T00:00:00', 'productos' => 'CAMA QUEEN SION ROBLE',
                 'Ciudad' => 'Bogotá, D.C.'
               }])
    end

    let(:ticket) { Helic3::Ticket.find_by!("pqrs_metadata->>'consecutivo_legado' = ?", '2346') }
    let(:item) { ticket.garantia.items.sole }

    it 'crea el ticket con el origen y el cliente del archivo' do
      expect(ticket).to have_attributes(title: 'Cliente de prueba', status: 'resolved')
      expect(ticket.pqrs_metadata['origen']).to eq('historico')
    end

    it 'mapea la ciudad pese al sufijo ", D.C." que no esta en el catalogo' do
      expect(ticket.garantia.cobertura_ciudad_id).to eq(bogota.id)
      expect(ticket.garantia.cerrada_at).to be_present
    end

    it 'mapea motivo, detalle (alias del typo del catalogo) y proceso (alias sin "de")' do
      expect(item.motivo_garantia_id).to eq(calidad.id)
      expect(item.detalle_tipificado_id).to eq(chapilla.id)
      expect(item.proceso_id).to eq(entrega.id)
      expect(item.producto_nombre).to eq('CAMA QUEEN SION ROBLE')
    end
  end

  it 'deja sin asignar lo que no tiene equivalente en el catalogo, sin reventar' do
    resultado = importar([{
                           'Consecutivo' => '9001', 'Fecha de creación' => '2026-01-01T09:00:00',
                           'Motivo' => 'Derecho de retracto', 'Ciudad' => 'Medellín', 'Proceso PQR' => 'PQR FINALIZADA',
                           'Fecha de Finalizacion' => '2026-01-10T00:00:00'
                         }])

    expect(resultado.creados).to eq(1)
    expect(resultado.sin_motivo).to eq(1)
    expect(resultado.sin_ciudad).to eq(1)
    expect(resultado.sin_proceso).to eq(1)

    item = Helic3::Garantia.find_by!(ticket: Helic3::Ticket.find_by("pqrs_metadata->>'consecutivo_legado' = ?", '9001')).items.sole
    expect(item.motivo_garantia_id).to be_nil
    expect(item.proceso_id).to be_nil
  end

  it 'usa un nombre generico cuando el producto viene vacio' do
    importar([{ 'Consecutivo' => '9002', 'Fecha de creación' => '2026-01-01T09:00:00' }])

    item = Helic3::Garantia.joins(:ticket)
                           .find_by!("helic3_tickets.pqrs_metadata->>'consecutivo_legado' = ?", '9002')
                           .items.sole
    expect(item.producto_nombre).to eq('Producto no especificado')
  end

  it 'interpreta las fechas del archivo como hora de Bogota, no UTC' do
    importar([{ 'Consecutivo' => '9003', 'Fecha de creación' => '2026-06-01T20:00:00' }])

    garantia = Helic3::Garantia.joins(:ticket)
                               .find_by!("helic3_tickets.pqrs_metadata->>'consecutivo_legado' = ?", '9003')
    # 2026-06-01 20:00 Bogota (UTC-5) == 2026-06-02 01:00 UTC
    expect(garantia.abierta_at.utc).to eq(Time.utc(2026, 6, 2, 1, 0))
  end

  it 'es idempotente: correr el mismo archivo dos veces no duplica nada' do
    filas = [{ 'Consecutivo' => '9004', 'Fecha de creación' => '2026-01-01T09:00:00' }]
    ruta = escribir_csv(filas)

    primero = described_class.new(account: account, ruta: ruta).importar!
    segundo = described_class.new(account: account, ruta: ruta).importar!

    expect(primero.creados).to eq(1)
    expect(segundo.creados).to eq(0)
    expect(segundo.omitidos).to eq(1)
    expect(Helic3::Ticket.where("pqrs_metadata->>'consecutivo_legado' = ?", '9004').count).to eq(1)
  end

  it 'ignora filas sin Consecutivo' do
    resultado = importar([{ 'Consecutivo' => '', 'Fecha de creación' => '2026-01-01T09:00:00' }])

    expect(resultado.creados).to eq(0)
    expect(resultado.omitidos).to eq(0)
  end

  it 'aisla por cuenta: el mismo consecutivo en otra cuenta no cuenta como ya importado' do
    otra_cuenta = create(:account)
    filas = [{ 'Consecutivo' => '9005', 'Fecha de creación' => '2026-01-01T09:00:00' }]

    described_class.new(account: otra_cuenta, ruta: escribir_csv(filas)).importar!
    resultado = described_class.new(account: account, ruta: escribir_csv(filas)).importar!

    expect(resultado.creados).to eq(1)
  end
end
