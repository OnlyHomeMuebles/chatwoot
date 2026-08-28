# EXP-01: "Informacion o consulta no genera radicado ni plazo. La marca sale
# del catalogo de categorias, no de un condicional en el codigo". Esta columna
# es esa marca: el expediente de una categoria sin radicado se crea igual
# (conserva historial) pero sin numero visible y fuera del conteo ante la SIC.
class AgregaGeneraRadicadoACategorias < ActiveRecord::Migration[7.2]
  def change
    add_column :helic3_catalogo_categorias, :genera_radicado, :boolean, null: false, default: true

    # Las cuentas ya sembradas por CAT-02 no se re-siembran (la semilla solo
    # crea), asi que la marca de Informacion se aplica aqui.
    reversible do |dir|
      dir.up do
        execute "UPDATE helic3_catalogo_categorias SET genera_radicado = FALSE WHERE codigo = 'informacion'"
      end
    end
  end
end
