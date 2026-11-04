json.call(carga, :id, :tipo, :nombre_archivo, :modo, :estado, :filas_leidas, :filas_insertadas,
          :filas_actualizadas, :filas_omitidas, :errores, :created_at)
json.usuario carga.usuario&.name
