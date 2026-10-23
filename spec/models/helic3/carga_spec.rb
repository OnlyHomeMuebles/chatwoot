# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Carga do
  let(:account) { create(:account) }

  # Revision de Jhan (PR #140): todas las demas FK de helic3 hacia users
  # llevan on_delete: :nullify (helic3_agentes, helic3_documentos,
  # helic3_eventos, helic3_plantillas_formato). Sin eso, borrar en Chatwoot un
  # usuario que subio una carga revienta por la FK -- usuario_id ya es
  # opcional en el modelo, el borrado debe nulificarlo, no reventar.
  it 'nulifica usuario_id (no revienta) si se borra el usuario que subio la carga' do
    usuario = create(:user, account: account)
    carga = described_class.create!(account: account, tipo: 'facturas', modo: 'anexar', usuario: usuario,
                                    nombre_archivo: 'a.csv', estado: 'completado')

    expect { usuario.destroy }.not_to raise_error

    expect(carga.reload.usuario_id).to be_nil
  end
end
