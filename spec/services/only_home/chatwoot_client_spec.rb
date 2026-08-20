# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnlyHome::ChatwootClient do
  subject(:client) { described_class.new(base_url: 'http://cw.test', account_id: 7, api_access_token: 'tok') }

  def http_response(success:, code: 200, parsed: {}, body: '')
    instance_double(HTTParty::Response, success?: success, code: code, parsed_response: parsed, body: body)
  end

  let(:ok) { http_response(success: true, parsed: { 'id' => 1 }) }

  it 'publica una respuesta outgoing en el endpoint de mensajes con auth' do
    expect(HTTParty).to receive(:post).with(
      'http://cw.test/api/v1/accounts/7/conversations/42/messages',
      hash_including(
        headers: { 'api_access_token' => 'tok', 'Content-Type' => 'application/json' },
        body: { content: 'hola', message_type: 'outgoing', private: false }.to_json
      )
    ).and_return(ok)

    client.create_message(42, content: 'hola')
  end

  it 'marca la nota privada con private: true' do
    expect(HTTParty).to receive(:post).with(
      'http://cw.test/api/v1/accounts/7/conversations/42/messages',
      hash_including(body: { content: 'interno', message_type: 'outgoing', private: true }.to_json)
    ).and_return(ok)

    client.create_message(42, content: 'interno', private_note: true)
  end

  it 'fusiona etiquetas nuevas con las existentes (no reemplaza)' do
    allow(HTTParty).to receive(:get)
      .with('http://cw.test/api/v1/accounts/7/conversations/42/labels', anything)
      .and_return(http_response(success: true, parsed: { 'payload' => %w[soporte] }))
    expect(HTTParty).to receive(:post).with(
      'http://cw.test/api/v1/accounts/7/conversations/42/labels',
      hash_including(body: { labels: %w[soporte pqrs] }.to_json)
    ).and_return(ok)

    client.add_labels(42, 'pqrs')
  end

  it 'envía atributos personalizados' do
    expect(HTTParty).to receive(:post).with(
      'http://cw.test/api/v1/accounts/7/conversations/42/custom_attributes',
      hash_including(body: { custom_attributes: { 'ciudad' => 'Bogotá' } }.to_json)
    ).and_return(ok)

    client.update_custom_attributes(42, { 'ciudad' => 'Bogotá' })
  end

  it 'asigna la conversación a un equipo (handoff humano)' do
    expect(HTTParty).to receive(:post).with(
      'http://cw.test/api/v1/accounts/7/conversations/42/assignments',
      hash_including(body: { team_id: 9 }.to_json)
    ).and_return(ok)

    client.assign(42, team_id: 9)
  end

  it 'cambia el estado de la conversación (ej. open para un humano)' do
    expect(HTTParty).to receive(:post).with(
      'http://cw.test/api/v1/accounts/7/conversations/42/toggle_status',
      hash_including(body: { status: 'open' }.to_json)
    ).and_return(ok)

    client.update_status(42, 'open')
  end

  it 'lee los mensajes de la conversación (contexto del copiloto)' do
    allow(HTTParty).to receive(:get)
      .with('http://cw.test/api/v1/accounts/7/conversations/42/messages', anything)
      .and_return(http_response(success: true, parsed: { 'payload' => [{ 'content' => 'hola' }] }))

    expect(client.conversation_messages(42)).to eq([{ 'content' => 'hola' }])
  end

  it 'lanza ApiError ante una respuesta no exitosa' do
    allow(HTTParty).to receive(:post).and_return(http_response(success: false, code: 401, body: 'unauthorized'))

    expect { client.create_message(42, content: 'x') }
      .to raise_error(described_class::ApiError, /401/)
  end
end
