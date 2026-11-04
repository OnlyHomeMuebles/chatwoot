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
                                                  ciudad: 'Cali', factura_numero: 'FAC-9',
                                                  cliente_nombre: nil, cliente_telefono: nil,
                                                  factura_fecha: nil)
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

  # MAN-01: en una PQR manual no hay conversacion, asi que CLIENTE/TELEFONO/FECHA_COMPRA
  # salen de la ficha. En una del chat sin esos datos en ficha, caen al contacto.
  describe 'MAN-01: cliente y fecha de compra desde la ficha' do
    let(:user) { instance_double(User, name: 'Asesora') }

    def item_con(ficha:, contacto:)
      conversation = contacto && instance_double(Conversation, contact: contacto)
      ticket = instance_double(Helic3::Ticket, display_id: 1, datos: ficha, conversation: conversation)
      garantia = instance_double(Helic3::Garantia, numero_radicado: 'G', ticket: ticket)
      instance_double(Helic3::GarantiaItem, garantia: garantia, producto_nombre: 'p',
                                            producto_referencia: 'r', motivo_garantia: nil,
                                            detalle_tipificado: nil, decision: nil)
    end

    it 'CA5: CLIENTE, TELEFONO y FECHA_COMPRA salen de la ficha aunque el contacto sea distinto' do
      ficha = instance_double(Helic3::TicketDato, cedula: '1', direccion: 'd', ciudad: 'c',
                                                  factura_numero: 'f', cliente_nombre: 'Cliente Ficha',
                                                  cliente_telefono: '3151112222',
                                                  factura_fecha: Date.new(2026, 1, 15))
      contacto = instance_double(Contact, name: 'Contacto Viejo', phone_number: '000')

      datos = described_class.call(item: item_con(ficha: ficha, contacto: contacto), user: user)

      expect(datos['CLIENTE']).to eq('Cliente Ficha')
      expect(datos['TELEFONO']).to eq('3151112222')
      expect(datos['FECHA_COMPRA']).to eq('15/01/2026')
    end

    it 'CA5: sin cliente en la ficha, CLIENTE y TELEFONO caen al contacto (PQR del chat)' do
      ficha = instance_double(Helic3::TicketDato, cedula: '1', direccion: 'd', ciudad: 'c',
                                                  factura_numero: 'f', cliente_nombre: nil,
                                                  cliente_telefono: nil, factura_fecha: nil)
      contacto = instance_double(Contact, name: 'Ana Chat', phone_number: '3009998888')

      datos = described_class.call(item: item_con(ficha: ficha, contacto: contacto), user: user)

      expect(datos['CLIENTE']).to eq('Ana Chat')
      expect(datos['TELEFONO']).to eq('3009998888')
      expect(datos['FECHA_COMPRA']).to eq('')
    end
  end
end
