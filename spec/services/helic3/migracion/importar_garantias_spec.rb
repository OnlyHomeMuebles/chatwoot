# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Migracion::ImportarGarantias do
  let(:account) { create(:account) }
  let!(:responsable) { create(:user, name: 'Experiencia al cliente', account: account) }

  let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia') }
  let!(:tipo) { Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Garantia', codigo: 'garantia') }
  let!(:etapa) do
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Solucionado', codigo: 'solucionado', detiene_reloj: true)
  end
  let!(:resultado) do
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Procede garantía', codigo: 'procede_garantia',
                                        cierra_pqr: true, abre_garantia: true)
  end
  let!(:motivo_pqr) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto', codigo: 'garantia_producto',
                                        categoria: categoria, abre_garantia: :siempre)
  end
  let!(:p_finalizada) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Garantía Finalizada',
                                              codigo: 'garantia_finalizada', es_terminal: true)
  end
  let!(:p_cambio) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Cambio de producto',
                                              codigo: 'cambio_producto', plazo_dias_habiles: 20)
  end
  let!(:m_calidad) do
    Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Calidad - producto comprado',
                                             codigo: 'calidad_producto_comprado')
  end
  let!(:detalle) do
    Helic3::Catalogo::DetalleTipificado.create!(account: account, nombre: 'Producto desajustado',
                                                codigo: 'producto_desajustado', motivo_garantia: m_calidad)
  end
  let!(:cob_cali) { Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Cali', codigo: 'cali') }
  let!(:cob_bog) { Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Bogotá', codigo: 'bogota') }
  let!(:parametro) do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_respuesta_pqr', valor: '15', unidad: 'dias_habiles')
  end

  let(:csv) do
    <<~CSV
      Consecutivo,Fecha de creación,Prioridad,Centros de operacion,Etapa del Caso,Proceso PQR,Motivo,Detalle Tipificado,Telefono de contacto,Fecha de Finalizacion,productos,Seguimiento u/o Observaciones,Identificación,Nombre del Cliente,Apellido del Cliente,Correo Electrónico,Direccion,Factura / Pedido / Orden de Compra,nro factura,Ciudad,Fecha Última Compra,Tipo Identificación
      100,"19/08/2026, 9:00",Alta,OH CALI,Solucionado,PQR FINALIZADA,Calidad - Producto Comprado,Producto desajustado,3001112233,19/08/2026,MESA,Caso cerrado,30280717 ,Ana,Perez,ana@mail.com,Calle 1,DEJAR,FVE-00000828,Cali,01/06/2026,Cedula de ciudadania
      200,"21/10/2026, 10:00",Media,OH BOGOTA,En gestión,CAMBIO PRODUCTO,Calidad - Producto Comprado,Producto desajustado,3136141853,,SILLA,Caso abierto,30324974,Juan,Lopez,juan@mail.com,Calle 2,,FVE-00001111,Bogotá,05/07/2026,Cedula de ciudadania
    CSV
  end

  def corrida(tipo: 'migracion')
    Helic3::Migracion::Corrida.create!(account: account, tipo: tipo, estado: 'simulando')
  end

  describe 'migración real (simulacion: false)' do
    let!(:resultado_corrida) { described_class.new(corrida: corrida, csv: csv, simulacion: false).call }

    it 'crea las PQR con el consecutivo como número y el reloj detenido' do
      pqr = Helic3::Ticket.find_by(account: account, display_id: 100)
      expect(pqr.motivo_pqr).to eq(motivo_pqr)
      expect(pqr.etapa).to eq(etapa)
      expect(pqr.respondida_at).to eq(pqr.radicada_at)
      expect(pqr.datos.cedula).to eq('30280717')
      expect(pqr.datos.fuentes['cedula']).to eq('migracion')
    end

    it 'cierra la garantía del caso Solucionado con la fecha original a las 23:59' do
      gar = Helic3::Ticket.find_by(account: account, display_id: 100).garantia
      expect(gar.display_id).to eq(100)
      expect(gar.cerrada?).to be(true)
      expect(gar.cerrada_at.in_time_zone('America/Bogota').strftime('%Y-%m-%d %H:%M')).to eq('2026-08-19 23:59')
      expect(gar.observacion_cierre).to eq('Garantía migrada del CRM anterior')
      expect(gar.items.first.proceso).to eq(p_finalizada)
      expect(gar.items.first.resuelto?).to be(true)
    end

    it 'deja abierta la garantía del caso En gestión con el proceso de la columna' do
      gar = Helic3::Ticket.find_by(account: account, display_id: 200).garantia
      expect(gar.cerrada?).to be(false)
      expect(gar.items.first.proceso).to eq(p_cambio)
    end

    it 'registra un Caso por consecutivo y cierra la corrida como completada' do
      corrida = resultado_corrida
      expect(corrida.estado).to eq('completada')
      expect(corrida.total_ok).to eq(2)
      expect(corrida.casos.creados.pluck(:consecutivo)).to contain_exactly(100, 200)
      expect(corrida.casos.find_by(consecutivo: 100).ticket_id).to be_present
    end
  end

  describe 'simulación (simulacion: true)' do
    let!(:resultado_corrida) { described_class.new(corrida: corrida, csv: csv, simulacion: true).call }

    it 'no deja ninguna PQR ni garantía en la base' do
      expect(Helic3::Ticket.where(account: account).count).to eq(0)
      expect(Helic3::Garantia.where(account: account).count).to eq(0)
    end

    it 'sí deja el reporte, con los casos en ok y sin ticket_id' do
      corrida = resultado_corrida
      expect(corrida.estado).to eq('simulado')
      expect(corrida.total_ok).to eq(2)
      expect(corrida.casos.creados.count).to eq(2)
      expect(corrida.casos.find_by(consecutivo: 100).ticket_id).to be_nil
    end
  end

  describe 'idempotencia y colisión' do
    it 'omite los casos ya migrados al correr el mismo archivo de nuevo' do
      described_class.new(corrida: corrida, csv: csv, simulacion: false).call
      segunda = described_class.new(corrida: corrida, csv: csv, simulacion: false).call

      expect(Helic3::Ticket.where(account: account).count).to eq(2)
      expect(segunda.total_omitidos).to eq(2)
    end

    it 'marca número ocupado si un consecutivo ya lo tiene un caso no migrado' do
      Helic3::Ticket.create!(account: account, title: 'Caso real', motivo_pqr: motivo_pqr,
                             categoria: categoria, etapa: etapa).update_columns(display_id: 100)
      resultado = described_class.new(corrida: corrida, csv: csv, simulacion: false).call

      caso = resultado.casos.find_by(consecutivo: 100)
      expect(caso.resultado).to eq('fallido')
      expect(caso.mensaje).to match(/número ocupado/)
    end
  end
end
