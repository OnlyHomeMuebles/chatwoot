# frozen_string_literal: true

require 'rails_helper'

# Validaciones comunes de los 9 catalogos de CAT-01 (criterios 2 y 3):
# nombre y codigo obligatorios, codigo unico por cuenta, y las asociaciones
# obligatorias de motivo y detalle.
RSpec.shared_examples 'un catalogo de clasificacion' do
  let(:account) { create(:account) }

  it 'exige nombre y codigo' do
    fila = construir(account)
    expect(fila).to be_valid

    fila.nombre = nil
    expect(fila).not_to be_valid

    fila.nombre = 'Valor'
    fila.codigo = nil
    expect(fila).not_to be_valid
  end

  it 'no permite dos codigos iguales en la misma cuenta' do
    construir(account).save!
    repetido = construir(account)
    expect(repetido).not_to be_valid
    expect(repetido.errors[:codigo]).to be_present
  end

  it 'permite el mismo codigo en otra cuenta' do
    construir(account).save!
    otra = create(:account)
    expect(construir(otra)).to be_valid
  end

  it 'excluye del scope activos a los valores desactivados sin borrarlos' do
    fila = construir(account)
    fila.activo = false
    fila.save!
    expect(descrito.activos.where(account: account)).not_to include(fila)
    expect(descrito.where(account: account)).to include(fila)
  end
end

RSpec.describe 'Helic3::Catalogo' do
  {
    Helic3::Catalogo::Categoria => nil,
    Helic3::Catalogo::Tipo => nil,
    Helic3::Catalogo::Resultado => nil,
    Helic3::Catalogo::EtapaPqr => nil,
    Helic3::Catalogo::MotivoGarantia => nil,
    Helic3::Catalogo::ProcesoGarantia => nil,
    Helic3::Catalogo::CoberturaCiudad => nil
  }.each_key do |modelo|
    describe modelo do
      it_behaves_like 'un catalogo de clasificacion' do
        let(:descrito) { modelo }

        # define_method (y no def): un def no captura la variable del loop
        define_method(:construir) do |cuenta|
          modelo.new(account: cuenta, nombre: 'Valor', codigo: 'valor')
        end
      end
    end
  end

  describe Helic3::Catalogo::MotivoPqr do
    it_behaves_like 'un catalogo de clasificacion' do
      let(:descrito) { described_class }

      def construir(cuenta)
        categoria = Helic3::Catalogo::Categoria.find_or_create_by!(account: cuenta, nombre: 'Garantía', codigo: 'garantia')
        described_class.new(account: cuenta, nombre: 'Valor', codigo: 'valor', categoria: categoria)
      end
    end

    it 'no existe sin su categoria' do
      account = create(:account)
      motivo = described_class.new(account: account, nombre: 'Valor', codigo: 'valor')
      expect(motivo).not_to be_valid
      expect(motivo.errors[:categoria]).to be_present
    end
  end

  describe Helic3::Catalogo::DetalleTipificado do
    it_behaves_like 'un catalogo de clasificacion' do
      let(:descrito) { described_class }

      def construir(cuenta)
        motivo = Helic3::Catalogo::MotivoGarantia.find_or_create_by!(account: cuenta, nombre: 'Calidad', codigo: 'calidad')
        described_class.new(account: cuenta, nombre: 'Valor', codigo: 'valor', motivo_garantia: motivo)
      end
    end

    it 'no se puede guardar sin su motivo asociado (criterio 3)' do
      account = create(:account)
      detalle = described_class.new(account: account, nombre: 'Tela motosa', codigo: 'tela_motosa')
      expect(detalle).not_to be_valid
      expect(detalle.errors[:motivo_garantia]).to be_present
    end
  end
end
