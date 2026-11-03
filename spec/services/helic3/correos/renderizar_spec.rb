# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Correos::Renderizar do
  describe '.asunto' do
    it 'sustituye los marcadores' do
      expect(described_class.asunto('Tu PQR #{{RADICADO_PQR}}', { 'RADICADO_PQR' => '123' }))
        .to eq('Tu PQR #123')
    end

    it 'quita saltos de linea de un dato sustituido (defensa contra inyeccion de cabeceras)' do
      asunto = described_class.asunto('Hola {{CLIENTE}}', { 'CLIENTE' => "Carlos\r\nBcc: otro@mail.com" })
      expect(asunto).not_to include("\r")
      expect(asunto).not_to include("\n")
      expect(asunto).to eq('Hola Carlos Bcc: otro@mail.com')
    end
  end

  describe '.cuerpo_html' do
    it 'convierte **negrita** en <strong>' do
      html = described_class.cuerpo_html('Hola **mundo**', {})
      expect(html).to include('<strong>mundo</strong>')
    end

    it 'separa parrafos por linea en blanco' do
      html = described_class.cuerpo_html("Primero.\n\nSegundo.", {})
      expect(html).to eq('<p>Primero.</p><p>Segundo.</p>')
    end

    it 'sustituye los marcadores antes de escapar' do
      html = described_class.cuerpo_html('Hola {{CLIENTE}}', { 'CLIENTE' => 'Ana' })
      expect(html).to eq('<p>Hola Ana</p>')
    end

    # CA explicito del ticket COR-02: un dato sustituido con <script> sale
    # escapado, nunca ejecutable.
    it 'escapa un <script> que venga en un dato sustituido (nombre del cliente)' do
      html = described_class.cuerpo_html('Hola {{CLIENTE}}', { 'CLIENTE' => '<script>alert(1)</script>' })

      expect(html).not_to include('<script>')
      expect(html).to include('&lt;script&gt;')
    end

    it 'un {{MARCADOR}} sin dato se sustituye por vacio, no revienta' do
      html = described_class.cuerpo_html('Hola {{CLIENTE}}', {})
      expect(html).to eq('<p>Hola </p>')
    end
  end
end
