require 'rails_helper'

RSpec.describe Helic3::Ticket, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:assignee).class_name('User').optional }
    it { is_expected.to belong_to(:creator).class_name('User').optional }
    it { is_expected.to belong_to(:conversation).optional }
  end

  describe 'display_id' do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }

    it 'assigns sequential per-account ticket numbers via the db trigger' do
      first_ticket = create(:ticket, account: account)
      second_ticket = create(:ticket, account: account)
      other_account_ticket = create(:ticket, account: other_account)

      expect(first_ticket.display_id).to eq(1)
      expect(second_ticket.display_id).to eq(2)
      expect(other_account_ticket.display_id).to eq(1)
      expect(second_ticket.ticket_number).to eq('#2')
    end
  end

  describe 'assignee validation' do
    let(:account) { create(:account) }

    it 'allows assigning an agent of the account' do
      agent = create(:user, account: account, role: :agent)
      ticket = build(:ticket, account: account, assignee: agent)

      expect(ticket).to be_valid
    end

    it 'rejects an assignee from another account' do
      outsider = create(:user)
      ticket = build(:ticket, account: account, assignee: outsider)

      expect(ticket).not_to be_valid
      expect(ticket.errors[:assignee]).to be_present
    end
  end

  describe 'resolved_at' do
    let(:account) { create(:account) }

    it 'sets resolved_at when the ticket is resolved and clears it on reopen' do
      ticket = create(:ticket, account: account)
      expect(ticket.resolved_at).to be_nil

      ticket.update!(status: :resolved)
      expect(ticket.resolved_at).to be_present

      ticket.update!(status: :open)
      expect(ticket.resolved_at).to be_nil
    end
  end

  describe 'clasificacion y relojes (EXP-01)' do
    let(:account) { create(:account) }
    let(:respondida) do
      Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida',
                                         detiene_reloj: true)
    end
    let(:garantia) do
      Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
    end
    let(:informacion) do
      Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Información', codigo: 'informacion',
                                          genera_radicado: false)
    end

    it 'se crea sin clasificar y se clasifica despues, sin que ninguna validacion lo impida' do
      queja = Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Queja', codigo: 'queja',
                                             plazo_dias_habiles: 15)
      ticket = create(:ticket, account: account)

      expect(ticket.categoria).to be_nil

      ticket.update!(categoria: garantia, tipo: queja)
      expect(ticket.reload.tipo.plazo_dias_habiles).to eq(15)
    end

    it 'rechaza clasificar con un catalogo de otra cuenta' do
      ajena = Helic3::Catalogo::Categoria.create!(account: create(:account), nombre: 'Garantía', codigo: 'garantia')
      ticket = build(:ticket, account: account, categoria: ajena)

      expect(ticket).not_to be_valid
      expect(ticket.errors[:categoria]).to be_present
    end

    it 'responder! sella la fecha y deja el expediente en la etapa que detiene el reloj' do
      respondida
      ticket = create(:ticket, account: account, categoria: garantia)

      ticket.responder!

      expect(ticket.respondida_at).to be_present
      expect(ticket.etapa.codigo).to eq('respondida')
      expect(ticket).to be_reloj_detenido
    end

    it 'un expediente respondido queda cerrado para el plazo legal aunque siga abierto operativamente' do
      respondida
      # la garantia sigue viva: el status operativo NO se toca al responder
      ticket = create(:ticket, account: account, categoria: garantia, status: :open)

      ticket.responder!

      expect(ticket.reload).to be_open
      expect(ticket).to be_reloj_detenido
    end

    it 'un expediente de Informacion no recibe numero de radicado visible' do
      con_radicado = create(:ticket, account: account, categoria: garantia)
      sin_radicado = create(:ticket, account: account, categoria: informacion)

      expect(con_radicado.numero_radicado).to be_present
      expect(sin_radicado.numero_radicado).to be_nil
      # el display_id interno existe igual: el historial se conserva
      expect(sin_radicado.display_id).to be_present
    end

    it 'excluye a Informacion del conteo frente a la SIC' do
      pqr = create(:ticket, account: account, categoria: garantia)
      consulta = create(:ticket, account: account, categoria: informacion)
      sin_clasificar = create(:ticket, account: account)

      expect(described_class.cuenta_para_sic).to include(pqr, sin_clasificar)
      expect(described_class.cuenta_para_sic).not_to include(consulta)
    end
  end

  describe 'los lectores del reloj (SEM-01)' do
    let(:account) { create(:account) }
    let(:zona) { Time.find_zone!('America/Bogota') }
    let(:garantia) do
      Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
    end
    let(:informacion) do
      Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Información', codigo: 'informacion',
                                          genera_radicado: false)
    end
    let(:respondida) do
      Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida',
                                         detiene_reloj: true)
    end

    def sembrar_umbrales_pqr
      { 'plazo_respuesta_pqr' => 15, 'umbral_verde_pqr' => 8, 'umbral_amarillo_pqr' => 3 }
        .each do |clave, valor|
        Helic3::Catalogo::Parametro.create!(account: account, clave: clave, valor: valor.to_s,
                                            unidad: 'dias_habiles')
      end
    end

    # expediente radicado el lunes 7/sep/2026 con vencimiento el viernes
    # 25/sep/2026 (septiembre de 2026 no tiene festivos en Colombia)
    def expediente
      @expediente ||= create(:ticket, account: account, categoria: garantia,
                                      radicada_at: zona.local(2026, 9, 7, 9, 0),
                                      plazo_respuesta_vence_at: zona.local(2026, 9, 25, 23, 59))
    end

    it 'recien radicado, con muchos dias por delante, esta en verde' do
      sembrar_umbrales_pqr
      travel_to zona.local(2026, 9, 7, 10, 0) do
        expect(expediente.dias_habiles_restantes).to eq(14)
        expect(expediente.semaforo).to eq(:verde)
      end
    end

    it 'con 4 dias habiles restantes esta en amarillo; con 2, en rojo' do
      sembrar_umbrales_pqr
      travel_to zona.local(2026, 9, 21, 10, 0) do # lunes: quedan 22,23,24,25
        expect(expediente.dias_habiles_restantes).to eq(4)
        expect(expediente.semaforo).to eq(:amarillo)
      end
      travel_to zona.local(2026, 9, 23, 10, 0) do # miercoles: quedan 24,25
        expect(expediente.dias_habiles_restantes).to eq(2)
        expect(expediente.semaforo).to eq(:rojo)
      end
    end

    it 'vencido devuelve un numero negativo y rojo, sin levantar excepcion' do
      sembrar_umbrales_pqr
      travel_to zona.local(2026, 9, 30, 10, 0) do # miercoles, 3 habiles despues del vencimiento
        expect(expediente.dias_habiles_restantes).to eq(-3)
        expect(expediente.semaforo).to eq(:rojo)
      end
    end

    it 'responder! congela el reloj: dias despues devuelve el mismo numero' do
      sembrar_umbrales_pqr
      respondida # responder! necesita la etapa que detiene el reloj
      congelado = nil
      travel_to zona.local(2026, 9, 21, 10, 0) do
        expediente.responder!
        congelado = expediente.dias_habiles_restantes
      end
      travel_to zona.local(2026, 9, 24, 10, 0) do
        expect(expediente.dias_habiles_restantes).to eq(congelado)
        expect(congelado).to eq(4)
      end
    end

    it 'un expediente de Informacion devuelve nil en ambos, no cero' do
      consulta = create(:ticket, account: account, categoria: informacion)

      expect(consulta.dias_habiles_restantes).to be_nil
      expect(consulta.semaforo).to be_nil
    end

    it 'si falta umbral_verde_pqr, el error nombra esa clave exacta' do
      { 'plazo_respuesta_pqr' => 15, 'umbral_amarillo_pqr' => 3 }.each do |clave, valor|
        Helic3::Catalogo::Parametro.create!(account: account, clave: clave, valor: valor.to_s,
                                            unidad: 'dias_habiles')
      end
      travel_to zona.local(2026, 9, 21, 10, 0) do
        expect { expediente.semaforo }
          .to raise_error(Helic3::ParametrosGarantia::ParametroFaltante, /umbral_verde_pqr/)
      end
    end
  end
end
