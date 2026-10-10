# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::DatosDelFormato do
  it 'DATOS_DE_EJEMPLO cubre todos los marcadores del diccionario' do
    expect(described_class::DATOS_DE_EJEMPLO.keys).to match_array(Helic3::Formatos::Marcadores.nombres)
  end

  it 'un campo faltante queda vacio, nunca "nil"' do
    ticket = instance_double(Helic3::Ticket, display_id: 7, datos: nil, conversation: nil)
    garantia = instance_double(Helic3::Garantia, numero_radicado: 'GAR-1', ticket: ticket)
    item = instance_double(Helic3::GarantiaItem,
                           garantia: garantia, producto_nombre: 'Silla', producto_referencia: nil,
                           motivo_garantia: nil, detalle_tipificado: nil, decision: nil)

    datos = described_class.call(item: item, user: nil)

    expect(datos['CEDULA']).to eq('')
    expect(datos['CLIENTE']).to eq('')
    expect(datos.values).not_to include('nil')
  end

  describe 'con un caso completo' do
    let(:user) { instance_double(User, name: 'Asesora SAC') }
    let(:datos) { described_class.call(item: item_completo, user: user) }

    def item_completo
      contacto = instance_double(Contact, name: 'Ana Perez', phone_number: '3001234567')
      conversation = instance_double(Conversation, contact: contacto)
      ficha = instance_double(Helic3::TicketDato, cedula: '1.234.567', direccion: 'Calle 1',
                                                  ciudad: 'Cali', factura_numero: 'FAC-9')
      ticket = instance_double(Helic3::Ticket, display_id: 42, datos: ficha, conversation: conversation)
      garantia = instance_double(Helic3::Garantia, numero_radicado: 'GAR-0042', ticket: ticket)
      instance_double(Helic3::GarantiaItem,
                      garantia: garantia, producto_nombre: 'Sofa', producto_referencia: 'REF-1',
                      motivo_garantia: nil, detalle_tipificado: nil, decision: 'Cambio')
    end

    it 'resuelve los datos del cliente y la garantia' do
      expect(datos['CLIENTE']).to eq('Ana Perez')
      expect(datos['TELEFONO']).to eq('3001234567')
      expect(datos['CEDULA']).to eq('1.234.567')
      expect(datos['RADICADO']).to eq('GAR-0042')
      expect(datos['RADICADO_PQR']).to eq('42')
    end

    it 'resuelve los datos del item y el usuario' do
      expect(datos['PRODUCTO']).to eq('Sofa')
      expect(datos['DECISION']).to eq('Cambio')
      expect(datos['ELABORADO_POR']).to eq('Asesora SAC')
    end
  end
end
