# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Devolucion, type: :model do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  # Revision de Jhan (PR #149): presupuesto_dias_habiles tenia que salir de
  # plazo_total_garantia (el mismo presupuesto de Garantia, reusado, como ya
  # documentaba el comentario de la clase) -- antes leia
  # 'plazo_total_devolucion', que nadie siembra, asi que quedaba en nil.
  it 'copia el presupuesto de dias del mismo parametro de Garantia al crear' do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_total_garantia',
                                        valor: '30', unidad: 'dias_habiles')

    devolucion = described_class.create!(account: account, ticket: ticket)

    expect(devolucion.presupuesto_dias_habiles).to eq(30)
  end
end
