require 'rails_helper'

RSpec.describe 'Tickets API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/helic3/tickets' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/helic3/tickets"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:ticket) { create(:ticket, account: account) }

      it 'returns all the tickets of the account' do
        get "/api/v1/accounts/#{account.id}/helic3/tickets",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.first['id']).to eq(ticket.id)
        expect(response.parsed_body.first['ticket_number']).to eq("##{ticket.display_id}")
      end

      it 'filters by status' do
        create(:ticket, account: account, status: :resolved)

        get "/api/v1/accounts/#{account.id}/helic3/tickets",
            params: { status: 'resolved' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.length).to eq(1)
        expect(response.parsed_body.first['status']).to eq('resolved')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/helic3/tickets' do
    # create nace por Helic3::Casos::Radicar (API-02), que necesita la etapa
    # inicial y el plazo sembrados en la cuenta.
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    context 'when it is an authenticated user' do
      it 'creates a ticket with a sequential ticket number and sets the creator' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Printer on fire', description: 'Third floor',
                                datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } } },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['display_id']).to eq(1)
        expect(response.parsed_body['creator']['id']).to eq(agent.id)
      end

      it 'rejects a ticket without title' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { description: 'no title',
                                datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } } },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST create con clasificacion y reloj (API-02)' do
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    let(:tipo) { Helic3::Catalogo::Tipo.find_by!(account: account, codigo: 'peticion') }
    let(:motivo_garantia) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }
    let(:motivo_info) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'informacion_general') }

    # MAN-01: sin conversacion el cliente es obligatorio; estos casos radican a mano,
    # asi que llevan nombre y telefono por defecto (prueban clasificacion/reloj, no eso).
    def radicar(atributos)
      post "/api/v1/accounts/#{account.id}/helic3/tickets",
           params: { ticket: { title: 'Caso',
                               datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } }.merge(atributos) },
           headers: agent.create_new_auth_token, as: :json
    end

    it 'deriva la categoria del motivo y devuelve numero de radicado y plazo' do
      radicar(tipo_id: tipo.id, motivo_pqr_id: motivo_garantia.id)

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['categoria']['codigo']).to eq('garantia')
      expect(body['tipo']['codigo']).to eq('peticion')
      expect(body['motivo_pqr']['codigo']).to eq('garantia_producto')
      expect(body['numero_radicado']).to be_present
      expect(body['plazo_respuesta_vence_at']).to be_present
    end

    it 'guarda el detalle tipificado del dialogo en la ficha con fuente humano (VIS-04)' do
      detalle = Helic3::Catalogo::DetalleTipificado.where(account: account).activos.first

      radicar(tipo_id: tipo.id, motivo_pqr_id: motivo_garantia.id, detalle_tipificado_id: detalle.id)

      expect(response).to have_http_status(:success)
      ticket = account.tickets.find(response.parsed_body['id'])
      expect(ticket.datos.detalle_tipificado_id).to eq(detalle.id)
      expect(ticket.datos.fuentes['detalle_tipificado_id']).to eq('humano')
    end

    it 'incluye semaforo y dias habiles restantes coherentes con el plazo' do
      radicar(tipo_id: tipo.id, motivo_pqr_id: motivo_garantia.id)

      body = response.parsed_body
      expect(body['dias_habiles_restantes']).to be_a(Integer).and(be_positive)
      expect(body['semaforo']).to be_in(%w[verde amarillo rojo])
    end

    it 'marca el origen humano cuando lo radica una persona' do
      radicar(tipo_id: tipo.id, motivo_pqr_id: motivo_garantia.id)

      expect(response.parsed_body['origen']).to eq('humano')
    end

    it 'un expediente de categoria Informacion no lleva numero ni semaforo' do
      radicar(motivo_pqr_id: motivo_info.id)

      body = response.parsed_body
      expect(body['categoria']['codigo']).to eq('informacion')
      expect(body['numero_radicado']).to be_nil
      expect(body['semaforo']).to be_nil
    end

    it 'rechaza un id de catalogo de otra cuenta' do
      otra = create(:account)
      Helic3::Catalogo::SeederService.new(otra).sembrar!
      motivo_otra = Helic3::Catalogo::MotivoPqr.find_by!(account: otra, codigo: 'garantia_producto')

      radicar(motivo_pqr_id: motivo_otra.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  # MAN-01: radicacion manual (sin conversacion) con la ficha del cliente y la compra.
  describe 'POST create con ficha de cliente y compra (MAN-01)' do
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    let(:motivo) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }
    let(:datos_cliente) do
      { cliente_nombre: 'Ana Perez', cliente_telefono: '3001234567', cliente_email: 'ana@x.com',
        cedula: '12345', ciudad: 'Armenia', direccion: 'Calle 1 # 2-3',
        producto_nombre: 'Sofa Santorini', producto_referencia: 'SOF-1', factura_fecha: '2026-01-15' }
    end

    def radicar_manual(ticket_extra = {}, datos: datos_cliente, numero_orden: 'OH-DEMO-1')
      post "/api/v1/accounts/#{account.id}/helic3/tickets",
           params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id,
                               numero_orden: numero_orden, datos: datos }.merge(ticket_extra) },
           headers: agent.create_new_auth_token, as: :json
    end

    it 'CA1: radica sin conversacion con etapa nueva, vencimiento y la ficha completa (fuente humano)' do
      radicar_manual

      expect(response).to have_http_status(:success)
      ticket = account.tickets.find(response.parsed_body['id'])
      expect(ticket.etapa.codigo).to eq('nuevo')
      expect(ticket.plazo_respuesta_vence_at).to be_present

      ficha = ticket.datos
      expect(ficha.cliente_nombre).to eq('Ana Perez')
      expect(ficha.cliente_telefono).to eq('3001234567')
      expect(ficha.cliente_email).to eq('ana@x.com')
      expect(ficha.producto_referencia).to eq('SOF-1')
      expect(ficha.factura_fecha).to eq(Date.new(2026, 1, 15))
      expect(ficha.factura_numero).to eq('OH-DEMO-1') # numero_orden -> factura_numero (Radicar)

      %w[cliente_nombre cliente_telefono cliente_email cedula ciudad direccion
         producto_nombre producto_referencia factura_numero factura_fecha].each do |campo|
        expect(ficha.fuentes[campo]).to eq('humano')
      end
    end

    it 'CA2: sin conversacion y sin cliente_nombre -> 422 y no crea nada' do
      expect do
        radicar_manual(datos: datos_cliente.except(:cliente_nombre))
      end.not_to change(Helic3::Ticket, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'CA2: sin conversacion y sin cliente_telefono -> 422 y no crea nada' do
      expect do
        radicar_manual(datos: datos_cliente.except(:cliente_telefono))
      end.not_to change(Helic3::Ticket, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'con conversacion el cliente es opcional (el chat no cambia)' do
      conv = create(:conversation, account: account)

      expect do
        radicar_manual({ conversation_id: conv.display_id }, datos: {}, numero_orden: nil)
      end.to change(Helic3::Ticket, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'rechaza con 422 una factura_fecha futura' do
      expect do
        radicar_manual(datos: datos_cliente.merge(factura_fecha: (Date.current + 1).iso8601))
      end.not_to change(Helic3::Ticket, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rechaza con 422 una factura_fecha que no es una fecha' do
      expect do
        radicar_manual(datos: datos_cliente.merge(factura_fecha: 'no-es-fecha'))
      end.not_to change(Helic3::Ticket, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'CA3: revierte la radicacion completa si falla la escritura de la ficha del cliente' do
      allow_any_instance_of(Helic3::Casos::RegistrarDatos)
        .to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(Helic3::TicketDato.new))

      expect do
        radicar_manual(numero_orden: nil) # el unico RegistrarDatos que corre es el del cliente
      end.not_to change(Helic3::Ticket, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'CA4: GET devuelve los campos nuevos en datos y PATCH datos los acepta' do
      radicar_manual
      ticket = account.tickets.find(response.parsed_body['id'])

      get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
          headers: agent.create_new_auth_token, as: :json
      datos = response.parsed_body['datos']
      expect(datos['cliente_nombre']['valor']).to eq('Ana Perez')
      expect(datos['cliente_nombre']['fuente']).to eq('humano')
      expect(datos['factura_fecha']['valor']).to eq('2026-01-15')

      patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/datos",
            params: { datos: { cliente_telefono: '3999999999', direccion: 'Nueva dir' } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ticket.datos.reload.cliente_telefono).to eq('3999999999')
    end

    it 'PATCH datos tambien rechaza con 422 una factura_fecha futura (validacion en el modelo)' do
      radicar_manual
      ticket = account.tickets.find(response.parsed_body['id'])

      patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/datos",
            params: { datos: { factura_fecha: (Date.current + 1).iso8601 } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticket.datos.reload.factura_fecha).to eq(Date.new(2026, 1, 15))
    end
  end

  describe 'GET show de un expediente sin clasificar (API-02)' do
    let!(:ticket) { create(:ticket, account: account) }

    it 'devuelve los cinco objetos de clasificacion en nulo sin romper la vista' do
      get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      %w[categoria tipo motivo_pqr resultado etapa].each do |llave|
        expect(body[llave]).to be_nil
      end
    end
  end

  describe 'robustez del listado y el update (review API-02)' do
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    let(:tipo) { Helic3::Catalogo::Tipo.find_by!(account: account, codigo: 'peticion') }
    let(:motivo) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }

    it 'el listado no expone semaforo ni dias_habiles_restantes (se derivan solo en el detalle)' do
      Helic3::Casos::Radicar.new(account: account, titulo: 'Caso', motivo_pqr: motivo, origen: :humano).call

      get "/api/v1/accounts/#{account.id}/helic3/tickets", headers: agent.create_new_auth_token, as: :json

      fila = response.parsed_body.first
      expect(fila).not_to have_key('semaforo')
      expect(fila).not_to have_key('dias_habiles_restantes')
    end

    it 'update no reasigna la clasificacion ya radicada (categoria/tipo/motivo)' do
      ticket = Helic3::Casos::Radicar.new(account: account, titulo: 'Caso', tipo: tipo, motivo_pqr: motivo,
                                          creator: agent, origen: :humano).call
      otra_categoria = Helic3::Catalogo::Categoria.find_by!(account: account, codigo: 'logistica')

      patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
            params: { ticket: { categoria_id: otra_categoria.id, motivo_pqr_id: nil } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ticket.reload.categoria.codigo).to eq('garantia')
      expect(ticket.motivo_pqr.codigo).to eq('garantia_producto')
    end

    it 'create aplica status y assignee despues de radicar, sin ignorarlos' do
      post "/api/v1/accounts/#{account.id}/helic3/tickets",
           params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, status: 'pending', assignee_id: agent.id,
                               datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } } },
           headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['status']).to eq('pending')
      expect(body['assignee']['id']).to eq(agent.id)
    end

    it 'create aplica la etapa operativa elegida (En gestion) al radicar' do
      en_gestion = Helic3::Catalogo::EtapaPqr.find_by!(account: account, codigo: 'en_gestion')

      post "/api/v1/accounts/#{account.id}/helic3/tickets",
           params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, etapa_id: en_gestion.id,
                               datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['etapa']['codigo']).to eq('en_gestion')
    end

    it 'create rechaza 422 y no radica si la etapa elegida detiene el reloj (Solucionado): RES-01' do
      solucionado = Helic3::Catalogo::EtapaPqr.find_by!(account: account, codigo: 'solucionado')

      expect do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, etapa_id: solucionado.id,
                                 datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } } },
             headers: agent.create_new_auth_token, as: :json
      end.not_to change(Helic3::Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Atomicidad (review de Jhan): los operativos corren dentro de la misma
    # transaccion que la radicacion. Si fallan, no puede quedar un expediente
    # radicado (con numero y reloj legal) huerfano.
    it 'no radica si el assignee es de otra cuenta (rollback completo)' do
      ajeno = create(:user, account: create(:account))

      expect do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, assignee_id: ajeno.id,
                                 datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } } },
             headers: agent.create_new_auth_token, as: :json
      end.not_to change(Helic3::Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'no radica si el status es invalido y responde 422, no 500 (rollback completo)' do
      expect do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, status: 'inexistente',
                                 datos: { cliente_nombre: 'Cliente', cliente_telefono: '3001234567' } } },
             headers: agent.create_new_auth_token, as: :json
      end.not_to change(Helic3::Ticket, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # CTR-01: el frontend manda el display_id (lo que ve en pantalla); el dominio
    # guarda el id de base de datos. El controlador traduce en la frontera.
    it 'traduce el conversation_id de pantalla (display_id) al id de base de datos' do
      3.times { create(:conversation, account: create(:account)) } # separa el display_id del id de BD
      conv = create(:conversation, account: account)
      expect(conv.display_id).not_to eq(conv.id)

      post "/api/v1/accounts/#{account.id}/helic3/tickets",
           params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, conversation_id: conv.display_id } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Helic3::Ticket.find(response.parsed_body['id']).conversation_id).to eq(conv.id)
    end

    it 'responde 404 (no 422 sobre cuentas) y no radica si la conversacion no existe' do
      expect do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, conversation_id: 999_999 } },
             headers: agent.create_new_auth_token, as: :json
      end.not_to change(Helic3::Ticket, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'responde 404 y no radica si la conversacion es de otra cuenta' do
      ajena = create(:conversation, account: create(:account))

      expect do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, conversation_id: ajena.display_id } },
             headers: agent.create_new_auth_token, as: :json
      end.not_to change(Helic3::Ticket, :count)

      expect(response).to have_http_status(:not_found)
    end

    # CTR-02: la respuesta expone el display aparte del id de BD, para que la vista
    # compare display con display sin conocer ids del dominio.
    it 'expone conversation_id (id de BD) y conversation_display_id (el de pantalla)' do
      3.times { create(:conversation, account: create(:account)) }
      conv = create(:conversation, account: account)
      ticket = Helic3::Casos::Radicar.new(account: account, titulo: 'Caso', motivo_pqr: motivo,
                                          conversation_id: conv.id, origen: :humano).call

      get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['conversation_id']).to eq(conv.id)
      expect(response.parsed_body['conversation_display_id']).to eq(conv.display_id)
    end

    it 'conversation_display_id es nil cuando el expediente no tiene conversacion' do
      ticket = Helic3::Casos::Radicar.new(account: account, titulo: 'Sin conversacion', motivo_pqr: motivo,
                                          origen: :humano).call

      get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['conversation_display_id']).to be_nil
    end
  end

  # El menu "Estado" del panel Acciones del detalle pasa a gobernar la ETAPA de la
  # PQR (Nuevo/En gestion), no el status de Chatwoot. Mover entre etapas operativas
  # es seguro; la etapa final (Solucionado) detiene el reloj legal y por RES-01 solo
  # se alcanza al resolver, nunca por este update.
  describe 'PATCH cambia la etapa operativa desde el panel Acciones' do
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    let(:motivo) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }
    let(:en_gestion) { Helic3::Catalogo::EtapaPqr.find_by!(account: account, codigo: 'en_gestion') }
    let(:solucionado) { Helic3::Catalogo::EtapaPqr.find_by!(account: account, codigo: 'solucionado') }
    let(:ticket) do
      Helic3::Casos::Radicar.new(account: account, titulo: 'Caso', motivo_pqr: motivo, creator: agent, origen: :humano).call
    end

    it 'permite mover a una etapa que no detiene el reloj (En gestion)' do
      patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
            params: { ticket: { etapa_id: en_gestion.id } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ticket.reload.etapa.codigo).to eq('en_gestion')
      expect(ticket.reloj_detenido?).to be(false)
    end

    it 'rechaza con 422 mover a la etapa final que detiene el reloj (Solucionado): RES-01' do
      patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
            params: { ticket: { etapa_id: solucionado.id } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticket.reload.etapa.codigo).to eq('nuevo')
      expect(ticket.respondida_at).to be_nil
      expect(ticket.reloj_detenido?).to be(false)
    end

    it 'rechaza con 422 una etapa de otra cuenta (no fuga multi-tenant)' do
      otra = create(:account)
      Helic3::Catalogo::SeederService.new(otra).sembrar!
      etapa_ajena = Helic3::Catalogo::EtapaPqr.find_by!(account: otra, codigo: 'en_gestion')

      patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
            params: { ticket: { etapa_id: etapa_ajena.id } },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticket.reload.etapa.codigo).to eq('nuevo')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/helic3/tickets/{id}/assign' do
    let!(:ticket) { create(:ticket, account: account, creator: agent) }

    context 'when it is the ticket creator' do
      it 'assigns an agent of the account' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/assign",
             params: { assignee_id: agent.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.assignee_id).to eq(agent.id)
        expect(response.parsed_body['assignee']['id']).to eq(agent.id)
      end

      it 'unassigns when assignee_id is empty' do
        ticket.update!(assignee: agent)

        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/assign",
             params: { assignee_id: nil },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.assignee_id).to be_nil
      end
    end

    context 'when it is an agent unrelated to the ticket' do
      it 'returns unauthorized' do
        other_agent = create(:user, account: account, role: :agent)

        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/assign",
             params: { assignee_id: other_agent.id },
             headers: other_agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.reload.assignee_id).to be_nil
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/helic3/tickets/{id}' do
    let!(:ticket) { create(:ticket, account: account, creator: agent) }

    context 'when it is the assigned agent' do
      it 'updates the status' do
        assignee = create(:user, account: account, role: :agent)
        ticket.update!(assignee: assignee)

        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
              params: { ticket: { status: 'resolved' } },
              headers: assignee.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.status).to eq('resolved')
      end
    end

    context 'when it is an agent unrelated to the ticket' do
      it 'returns unauthorized' do
        other_agent = create(:user, account: account, role: :agent)

        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
              params: { ticket: { status: 'closed' } },
              headers: other_agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.reload.status).to eq('open')
      end
    end

    context 'when it is an administrator' do
      it 'updates any ticket' do
        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
              params: { ticket: { status: 'closed' } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.status).to eq('closed')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/helic3/tickets/{id}' do
    let!(:ticket) { create(:ticket, account: account) }

    context 'when it is an agent and the ticket is not theirs' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent and the ticket was created by them' do
      it 'deletes the ticket' do
        own_ticket = create(:ticket, account: account, creator: agent)

        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{own_ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Helic3::Ticket.exists?(own_ticket.id)).to be(false)
      end
    end

    context 'when it is an agent and the ticket is only assigned to them' do
      it 'returns unauthorized' do
        assigned_ticket = create(:ticket, account: account, assignee: agent)

        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{assigned_ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Helic3::Ticket.exists?(assigned_ticket.id)).to be(true)
      end
    end

    context 'when it is an administrator' do
      it 'deletes any ticket' do
        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Helic3::Ticket.exists?(ticket.id)).to be(false)
      end
    end
  end
end
