# Namespace del modulo de conocimiento (RAG) de Helic3. El prefijo de tabla
# se resuelve aqui una sola vez: todo modelo bajo Helic3::Knowledge mapea a
# una tabla helic3_knowledge_* sin declarar self.table_name uno por uno.
module Helic3::Knowledge
  def self.table_name_prefix
    'helic3_knowledge_'
  end
end
