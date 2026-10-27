# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 Indicadores (IND-01)', type: :request do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def get_garantias(query = {})
    get "/api/v1/accounts/#{account.id}/helic3/indicadores/garantias", params: query,
                                                                       headers: agent.create_new_auth_token, as: :json
  end

  it 'exige autenticacion' do
    get "/api/v1/accounts/#{account.id}/helic3/indicadores/garantias"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'devuelve las siete secciones de la respuesta' do
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1))

    get_garantias

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body.keys).to match_array(%w[kpis mensual trimestral por_ciudad por_motivo por_detalle por_proceso
                                        por_producto])
    expect(body['kpis']).to eq('garantias' => 1, 'solucionadas' => 0, 'en_proceso' => 1, 'productos' => 0)
  end

  it 'pasa los filtros de la query al servicio' do
    ciudad = Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales')
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1),
                             cobertura_ciudad: ciudad)
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1))

    get_garantias(cobertura_ciudad_id: ciudad.id)

    expect(response.parsed_body['kpis']['garantias']).to eq(1)
  end

  # N1 (revision de Jhan, PR #113): un anio/mes no numerico tumbaba la consulta con un 500
  # (Postgres comparando numeric con texto) -- ahora se ignora, no se rechaza la peticion.
  it 'no revienta con un anio/mes no numerico, simplemente los ignora' do
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1, 12, 0))

    get_garantias(anio: 'abc', mes: 'xyz')

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['kpis']['garantias']).to eq(1)
  end

  it 'no expone las garantias de otra cuenta' do
    otra_cuenta = create(:account)
    otro_ticket = create(:ticket, account: otra_cuenta)
    Helic3::Garantia.create!(account: otra_cuenta, ticket: otro_ticket, abierta_at: Time.zone.local(2026, 1, 1))

    get_garantias

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['kpis']['garantias']).to eq(0)
  end

  describe 'GET garantias/casos (mockup v12: detalle de clientes y casos)' do
    def get_garantias_casos(query = {})
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/garantias/casos", params: query,
                                                                               headers: agent.create_new_auth_token, as: :json
    end

    before do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_total_garantia', valor: '30',
                                          unidad: 'dias_habiles')
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_verde_garantia', valor: '15',
                                          unidad: 'dias_habiles')
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_amarillo_garantia', valor: '5',
                                          unidad: 'dias_habiles')
    end

    it 'devuelve la pagina de casos con su paginacion' do
      Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1))

      get_garantias_casos

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.keys).to match_array(%w[casos pagina paginas total])
      expect(body['total']).to eq(1)
      expect(body['casos'].first['id']).to be_present
    end

    it 'pasa los mismos filtros que #garantias' do
      ciudad = Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales')
      Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1),
                               cobertura_ciudad: ciudad)
      Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1))

      get_garantias_casos(cobertura_ciudad_id: ciudad.id)

      expect(response.parsed_body['total']).to eq(1)
    end
  end

  describe 'GET pqr (IND-02)' do
    let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'PQR', codigo: 'pqr') }
    let(:tipo) { Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo') }

    def get_pqr(query = {})
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/pqr", params: query,
                                                                   headers: agent.create_new_auth_token, as: :json
    end

    def crear_ticket_pqr(radicada_at:, respondida_at: nil)
      Helic3::Ticket.create!(account: account, title: 'Caso', categoria: categoria, tipo: tipo,
                             radicada_at: radicada_at, respondida_at: respondida_at)
    end

    it 'exige autenticacion' do
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/pqr"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'devuelve las ocho secciones de la respuesta' do
      crear_ticket_pqr(radicada_at: Time.zone.local(2026, 1, 1, 12, 0))

      get_pqr

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.keys).to match_array(%w[kpis mensual trimestral motivo_por_trimestre por_tipo por_categoria
                                          por_resultado por_responsable])
      expect(body['kpis']['radicadas']).to eq(1)
    end

    it 'pasa los filtros de la query al servicio' do
      crear_ticket_pqr(radicada_at: Time.zone.local(2026, 1, 1, 12, 0))
      crear_ticket_pqr(radicada_at: Time.zone.local(2025, 1, 1, 12, 0))

      get_pqr(anio: 2026)

      expect(response.parsed_body['kpis']['radicadas']).to eq(1)
    end

    it 'no revienta con un anio/mes no numerico, simplemente los ignora' do
      crear_ticket_pqr(radicada_at: Time.zone.local(2026, 1, 1, 12, 0))

      get_pqr(anio: 'abc', mes: 'xyz')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['kpis']['radicadas']).to eq(1)
    end

    it 'no expone las PQR de otra cuenta' do
      otra_cuenta = create(:account)
      otra_categoria = Helic3::Catalogo::Categoria.create!(account: otra_cuenta, nombre: 'PQR', codigo: 'pqr')
      otro_tipo = Helic3::Catalogo::Tipo.create!(account: otra_cuenta, nombre: 'Reclamo', codigo: 'reclamo')
      Helic3::Ticket.create!(account: otra_cuenta, title: 'Otra cuenta', categoria: otra_categoria, tipo: otro_tipo,
                             radicada_at: Time.zone.local(2026, 1, 1, 12, 0))

      get_pqr

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['kpis']['radicadas']).to eq(0)
    end
  end

  describe 'GET garantias/csv (IND-05)' do
    def get_garantias_csv(seccion, query = {})
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/garantias/csv", params: query.merge(seccion: seccion),
                                                                             headers: agent.create_new_auth_token
    end

    it 'exige autenticacion' do
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/garantias/csv", params: { seccion: 'mensual' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rechaza una seccion desconocida o faltante' do
      get_garantias_csv('no-existe')

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'descarga el detalle mensual con BOM, separador ; y los mismos numeros que el JSON' do
      ciudad = Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales')
      Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 10, 12, 0),
                               cerrada_at: Time.zone.local(2026, 1, 20, 12, 0), cobertura_ciudad: ciudad)

      get_garantias_csv('mensual')

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to eq('text/csv')
      expect(response.headers['Content-Disposition']).to include('indicadores-garantias-mensual')
      expect(response.body.b).to start_with("\xEF\xBB\xBF".b)
      cuerpo = response.body.delete_prefix("\xEF\xBB\xBF")
      filas = CSV.parse(cuerpo, col_sep: ';')
      expect(filas.first).to eq(['Mes', 'Garantías', 'Solucionadas', 'En proceso'])
      expect(filas.second).to eq(%w[2026-01 1 1 0])
    end

    it 'pasa los filtros de la query al servicio' do
      ciudad = Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales')
      otra_ciudad = Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Pereira', codigo: 'pereira')
      Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1, 12, 0),
                               cobertura_ciudad: ciudad)
      Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1, 12, 0),
                               cobertura_ciudad: otra_ciudad)

      get_garantias_csv('por_ciudad', cobertura_ciudad_id: ciudad.id)

      filas = CSV.parse(response.body.delete_prefix("\xEF\xBB\xBF"), col_sep: ';')
      expect(filas).to contain_exactly(%w[Etiqueta Cantidad], %w[Manizales 1])
    end

    # Las etiquetas nil del JSON (N3, PR #113) se traducen a texto fijo en el
    # CSV: no hay capa de i18n al abrir un archivo en Excel.
    it 'traduce una etiqueta nil a texto fijo, igual al que ya se ve en pantalla' do
      garantia = Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1, 12, 0))
      Helic3::GarantiaItem.create!(account: account, garantia: garantia, producto_nombre: 'Sofá')

      get_garantias_csv('por_motivo')

      filas = CSV.parse(response.body.delete_prefix("\xEF\xBB\xBF"), col_sep: ';')
      expect(filas).to include(['Sin motivo', '1'])
    end

    # "quita ese sin ciudad": una tienda sin asignar no es comparable contra
    # las demas, asi que se excluye del desglose (pantalla y CSV), a
    # diferencia de motivo/detalle/proceso donde "sin dato" si es util.
    it 'excluye del CSV las garantias sin ciudad asignada' do
      Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1, 12, 0))

      get_garantias_csv('por_ciudad')

      filas = CSV.parse(response.body.delete_prefix("\xEF\xBB\xBF"), col_sep: ';')
      expect(filas).to eq([%w[Etiqueta Cantidad]])
    end
  end

  describe 'GET pqr/csv (IND-05)' do
    let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'PQR', codigo: 'pqr') }
    let(:motivo) do
      Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Calidad', codigo: 'calidad', categoria: categoria)
    end

    def get_pqr_csv(seccion, query = {})
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/pqr/csv", params: query.merge(seccion: seccion),
                                                                       headers: agent.create_new_auth_token
    end

    it 'rechaza una seccion desconocida o faltante' do
      get_pqr_csv('no-existe')

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'descarga motivo_por_trimestre con las columnas T1-T4 y total' do
      Helic3::Ticket.create!(account: account, title: 'Caso', categoria: categoria, motivo_pqr: motivo,
                             radicada_at: Time.zone.local(2026, 1, 1, 12, 0))

      get_pqr_csv('motivo_por_trimestre')

      expect(response.headers['Content-Type']).to eq('text/csv')
      filas = CSV.parse(response.body.delete_prefix("\xEF\xBB\xBF"), col_sep: ';')
      expect(filas.first).to eq(%w[Motivo T1 T2 T3 T4 Total])
      expect(filas.second).to eq(%w[Calidad 1 0 0 0 1])
    end
  end

  describe 'GET todas' do
    let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'PQR', codigo: 'pqr') }
    let(:tipo) { Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo') }

    def get_todas(query = {})
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/todas", params: query,
                                                                     headers: agent.create_new_auth_token, as: :json
    end

    it 'exige autenticacion' do
      get "/api/v1/accounts/#{account.id}/helic3/indicadores/todas"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'devuelve garantias y pqr combinados' do
      Helic3::Ticket.create!(account: account, title: 'Caso', categoria: categoria, tipo: tipo,
                             radicada_at: Time.zone.local(2026, 1, 1, 12, 0))

      get_todas

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.keys).to match_array(%w[kpis mensual trimestral])
      expect(body['kpis']).to eq('total_casos' => 1, 'garantias' => 0, 'pqr' => 1, 'solucionadas' => 0,
                                 'en_proceso' => 1)
    end

    # Revision de Jhan (PR #134): toda garantia cuelga de la PQR que la abrio
    # (Helic3::Casos::AbrirGarantia), nunca de un ticket aparte -- sumar
    # "garantias" + "pqr" como universos distintos contaba el mismo caso dos
    # veces.
    it 'no duplica un caso que ya tiene garantia: una PQR con su propia garantia cuenta 1 vez' do
      pqr_con_garantia = Helic3::Ticket.create!(account: account, title: 'Caso', categoria: categoria, tipo: tipo,
                                                radicada_at: Time.zone.local(2026, 1, 1, 12, 0),
                                                respondida_at: Time.zone.local(2026, 1, 3, 12, 0))
      Helic3::Garantia.create!(account: account, ticket: pqr_con_garantia, abierta_at: Time.zone.local(2026, 1, 1, 12, 0),
                               cerrada_at: Time.zone.local(2026, 1, 10, 12, 0))

      get_todas

      body = response.parsed_body
      expect(body['kpis']).to eq('total_casos' => 1, 'garantias' => 1, 'pqr' => 1, 'solucionadas' => 1,
                                 'en_proceso' => 0)
    end
  end
end
