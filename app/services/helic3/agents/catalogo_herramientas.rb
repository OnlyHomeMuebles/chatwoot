# frozen_string_literal: true

# H3A-03: catalogo FIJO de herramientas. La implementacion de cada tool vive en
# codigo (con sus validaciones y su registro en el expediente); el admin solo
# puede ESCOGER de esta lista blanca por su clave. Una clave que no este aqui no
# se guarda (lo filtra Helic3::Agente) y no se inyecta al agente.
#
# `siempre: true` marca la herramienta que se inyecta a TODO agente sin que el
# admin la elija (derivar a un humano: un agente nunca puede quedar sin salida).
#
# La clase se guarda como string y se constantiza al construir el agente (H3A-08
# / H3A-10), para no acoplar la carga del catalogo al arbol de tools.
module Helic3::Agents::CatalogoHerramientas
  HERRAMIENTAS = [
    { clave: 'derivar_humano', etiqueta: 'Derivar a un humano',
      ayuda: 'Entrega la conversacion a un asesor humano cuando el cliente lo pide o el caso lo exige.',
      escribe_expediente: false, siempre: true,
      clase: 'Helic3::Agents::Tools::HumanHandoffTool' },
    { clave: 'buscar_conocimiento', etiqueta: 'Buscar en la base de conocimiento',
      ayuda: 'Consulta el RAG (politicas, catalogo, voz aprobada) antes de responder.',
      escribe_expediente: false,
      clase: 'Helic3::KnowledgeBaseSearchTool' },
    { clave: 'radicar_pqr', etiqueta: 'Radicar PQR',
      ayuda: 'Crea el radicado del caso en el expediente.',
      escribe_expediente: true,
      clase: 'Helic3::Agents::Tools::RadicarPqrTool' },
    { clave: 'resolver_pqr', etiqueta: 'Resolver PQR',
      ayuda: 'Aplica un resultado que cierra la PQR o abre garantia.',
      escribe_expediente: true,
      clase: 'Helic3::Agents::Tools::ResolverPqrTool' },
    { clave: 'registrar_consentimiento', etiqueta: 'Registrar consentimiento de datos',
      ayuda: 'Sella en la conversacion la autorizacion de tratamiento de datos (AGT-07).',
      escribe_expediente: true,
      clase: 'Helic3::Agents::Tools::RegistrarConsentimientoTool' },
    { clave: 'agregar_etiqueta', etiqueta: 'Agregar etiqueta',
      ayuda: 'Etiqueta la conversacion en Chatwoot.',
      escribe_expediente: false,
      clase: 'Helic3::Agents::Tools::AddLabelTool' },
    { clave: 'nota_privada', etiqueta: 'Nota privada',
      ayuda: 'Deja una nota interna visible solo para el equipo.',
      escribe_expediente: false,
      clase: 'Helic3::Agents::Tools::PrivateNoteTool' },
    { clave: 'ver_conversacion', etiqueta: 'Ver la conversacion',
      ayuda: 'Lee el historial de la conversacion actual.',
      escribe_expediente: false,
      clase: 'Helic3::Agents::Tools::GetConversationTool' },
    { clave: 'actualizar_atributo', etiqueta: 'Actualizar atributo del expediente',
      ayuda: 'Escribe un atributo del caso (p. ej. datos del cliente).',
      escribe_expediente: true,
      clase: 'Helic3::Agents::Tools::UpdateAttributeTool' }
  ].freeze

  CLAVES = HERRAMIENTAS.pluck(:clave).freeze

  # se inyectan a todo agente aunque no las elija el admin (H3A-10)
  SIEMPRE = HERRAMIENTAS.select { |h| h[:siempre] }.pluck(:clave).freeze

  module_function

  # forma expuesta por la API (H3A-03): sin la clase interna
  def para_api
    HERRAMIENTAS.map { |h| h.slice(:clave, :etiqueta, :ayuda, :escribe_expediente) }
  end

  # instancia las tools de un conjunto de claves + las que van siempre (H3A-10).
  # N5 (revision de Jhan): las de SIEMPRE (derivar_humano) van PRIMERO, igual que
  # las clases actuales, para no cambiar el orden en que el modelo ve las tools.
  def instanciar(claves)
    (SIEMPRE | Array(claves).map(&:to_s)).filter_map do |clave|
      entrada = HERRAMIENTAS.find { |h| h[:clave] == clave }
      entrada && entrada[:clase].constantize.new
    end
  end
end
