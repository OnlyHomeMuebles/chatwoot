# CAT-01: siembra y consulta de los catalogos de clasificacion.
namespace :catalogos do
  desc 'Siembra los catalogos de clasificacion con los valores confirmados (idempotente)'
  task sembrar: :environment do
    account = Account.first
    resumen = Helic3::Catalogo::SeederService.new(account).sembrar!
    resumen.each { |catalogo, total| puts format('%<c>-22s %<t>d filas', c: catalogo, t: total) }
    puts 'Semilla aplicada. Correrla de nuevo no duplica (criterio 5).'
  end
end

namespace :catalogos do
  desc 'Lista un catalogo: rake "catalogos:listar[motivos_garantia]"'
  task :listar, [:catalogo] => :environment do |_t, args|
    modelos = {
      'categorias' => Helic3::Catalogo::Categoria,
      'tipos' => Helic3::Catalogo::Tipo,
      'etapas_pqr' => Helic3::Catalogo::EtapaPqr,
      'motivos_garantia' => Helic3::Catalogo::MotivoGarantia,
      'detalles_tipificados' => Helic3::Catalogo::DetalleTipificado,
      'procesos_garantia' => Helic3::Catalogo::ProcesoGarantia,
      'coberturas_ciudad' => Helic3::Catalogo::CoberturaCiudad,
      'motivos_pqr' => Helic3::Catalogo::MotivoPqr,
      'resultados' => Helic3::Catalogo::Resultado
    }
    if args[:catalogo] == 'parametros'
      Helic3::Catalogo::Parametro.where(account: Account.first).order(:clave).each do |p|
        puts format('%<clave>-34s %<valor>-8s %<unidad>s', clave: p.clave, valor: p.valor, unidad: p.unidad)
      end
      next
    end
    modelo = modelos[args[:catalogo]] or abort "Catalogos: #{modelos.keys.join(', ')}, parametros"
    modelo.where(account: Account.first).order(:posicion).each do |fila|
      puts format('%<pos>3d %<cod>-32s %<nom>s%<off>s',
                  pos: fila.posicion, cod: fila.codigo, nom: fila.nombre,
                  off: fila.activo ? '' : '  [INACTIVO]')
    end
  end
end
