# CAT-02 (spec del Sprint 3, 25/08): con el modelo de un item por producto,
# la garantia cierra cuando TODOS sus productos llegan a un proceso terminal.
# es_terminal marca cuales cuentan como desenlace final (entrega del
# producto, devolucion de dinero, garantia negada) como DATO del catalogo:
# si el area decide que el desistimiento tambien es terminal, es marcar una
# fila, no reescribir la regla.
class AgregaEsTerminalAProcesosGarantia < ActiveRecord::Migration[7.2]
  def change
    add_column :helic3_catalogo_procesos_garantia, :es_terminal, :boolean, null: false, default: false
  end
end
