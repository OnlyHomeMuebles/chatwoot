#!/bin/bash

# Script de inicio para Yampi en Dokploy con Nixpacks
set -e

# Configurar PATH para encontrar bundle
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Configurar variables de entorno
export RAILS_ENV=${RAILS_ENV:-production}
export NODE_ENV=${NODE_ENV:-production}
export PORT=${PORT:-3000}

# Verificar que bundle esté disponible
if ! command -v bundle &> /dev/null; then
    echo "Error: bundle no encontrado. Intentando ubicaciones alternativas..."
    
    # Intentar ubicaciones comunes de bundle
    for bundle_path in /usr/local/bin/bundle /usr/bin/bundle ~/.rbenv/shims/bundle ~/.rvm/gems/default/bin/bundle; do
        if [ -f "$bundle_path" ]; then
            echo "Bundle encontrado en: $bundle_path"
            export PATH="$(dirname $bundle_path):$PATH"
            break
        fi
    done
    
    # Verificar nuevamente
    if ! command -v bundle &> /dev/null; then
        echo "Error: No se pudo encontrar bundle en ninguna ubicación"
        exit 1
    fi
fi

# Mostrar información de debug
echo "=== Información del entorno ==="
echo "Ruby version: $(ruby --version)"
echo "Bundle version: $(bundle --version)"
echo "Rails env: $RAILS_ENV"
echo "Port: $PORT"
echo "PATH: $PATH"
echo "=============================="

# Preparar base de datos: carga schema + seeds en BD vacía, o migraciones pendientes
echo "Preparando base de datos..."
bundle exec rails db:chatwoot_prepare

# Ejecutar el servidor
echo "Iniciando servidor Rails..."
exec bundle exec rails server -p $PORT -e $RAILS_ENV