# frozen_string_literal: true

namespace :helic3 do
  namespace :agentes do
    # H3A-04: siembra los 5 agentes del bot como filas de helic3_agentes. Idempotente
    # (no duplica al reejecutar), igual que la semilla de catalogos. Sin argumento
    # siembra todas las cuentas; con uno, solo esa.
    #   bundle exec rails 'helic3:agentes:sembrar'
    #   bundle exec rails 'helic3:agentes:sembrar[1]'
    desc 'Siembra los 5 agentes actuales como filas (H3A-04, idempotente)'
    task :sembrar, [:account_id] => :environment do |_t, args|
      cuentas = args[:account_id].present? ? Account.where(id: args[:account_id]) : Account.all
      cuentas.find_each do |account|
        resumen = Helic3::Agents::SeederService.new(account).sembrar!
        puts "cuenta #{account.id}: #{resumen}"
      end
    end
  end
end
