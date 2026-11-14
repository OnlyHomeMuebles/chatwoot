# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::Marcadores do
  it 'conoce los marcadores nuevos que se llenan en el modal' do
    expect(described_class.conocido?('PRODUCTO_DESCRIPCION')).to be(true)
    expect(described_class.conocido?('PRODUCTO_NUEVO')).to be(true)
  end

  describe '.editables' do
    it 'lista solo los marcadores que el operador edita al generar, con etiqueta y tipo' do
      editables = described_class.editables

      expect(editables.keys).to contain_exactly('PRODUCTO', 'PRODUCTO_DESCRIPCION', 'PRODUCTO_NUEVO')
      expect(editables['PRODUCTO'][:etiqueta]).to eq('Nombre del producto')
      expect(editables['PRODUCTO_NUEVO'][:etiqueta]).to eq('Producto nuevo')
      expect(editables['PRODUCTO_DESCRIPCION'][:tipo]).to eq(:area)
      expect(editables['PRODUCTO'][:tipo]).to eq(:texto)
    end
  end

  describe '.editable?' do
    it 'es true para un marcador de producto editable y false para el resto' do
      expect(described_class.editable?('PRODUCTO')).to be(true)
      expect(described_class.editable?('PRODUCTO_DESCRIPCION')).to be(true)
      expect(described_class.editable?('CLIENTE')).to be(false)
    end
  end

  it 'PRODUCTO_REFERENCIA sigue siendo conocido pero NO editable en el modal' do
    # Karen lo quita de sus plantillas, pero no se borra para no romper las que lo usen.
    expect(described_class.conocido?('PRODUCTO_REFERENCIA')).to be(true)
    expect(described_class.editable?('PRODUCTO_REFERENCIA')).to be(false)
  end
end
