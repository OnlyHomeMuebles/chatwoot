# OCR de facturas (AGT-08/AGT-09)

`Helic3::Agents::LectorDeImagenes` lee el texto de las fotos que el cliente adjunta
invocando el binario `tesseract` por `Open3` (sin gema: el `Gemfile` es upstream y
la frontera del fork solo permite tocar `config/routes.rb`). Es un requisito de
infraestructura, no de Ruby: el binario tiene que estar instalado donde corre el
código (web y worker de Sidekiq).

## Producción (Dokploy / railpack / nixpacks)

`tesseract-ocr` y `tesseract-ocr-spa` se instalan como paquetes apt en el
`deploy` de `railpack.json` y en el `[phases.setup]` de `nixpacks.toml`. Ambos
archivos se mantienen en sync a propósito.

## Desarrollo local (nativo, sin Docker)

- **macOS (Homebrew)**:
  ```
  brew install tesseract tesseract-lang
  ```
  El formula principal (`tesseract`) solo trae el idioma inglés; `tesseract-lang`
  agrega el resto de idiomas, incluido español (`spa`).
- **Linux (Debian/Ubuntu, apt)**:
  ```
  sudo apt-get install tesseract-ocr tesseract-ocr-spa
  ```

Verificar la instalación:
```
tesseract --list-langs   # debe listar "spa"
bundle exec rake helic3:ocr:diagnostico
```

## Si el binario falta

`LectorDeImagenes.disponible?` corre `tesseract --list-langs` y confirma que el
idioma configurado (`OCR_IDIOMA`, por defecto `spa`) esté instalado. Solo se
memoiza el resultado `true` (el binario no desaparece a mitad de la vida del
worker); un `false` no se memoiza para siempre, porque puede ser transitorio
(p. ej. un timeout al arrancar con el worker cargado) y se vuelve a confirmar
en la siguiente llamada, sin esperar a un reinicio. Si no está disponible,
`leer` no intenta imagen por imagen: registra una sola línea
`[Helic3][ocr] tesseract no disponible` a nivel error y devuelve `nil`, sin
tumbar el job. El agente tampoco miente: en vez de decir que la foto no tenía
texto legible, dice que no se pudo leer
automáticamente (ver `PqrsAgent.linea_de_imagen`).

## Docker (desarrollo con `docker-compose`)

El `docker/Dockerfile` de este repo (imagen usada por `docker-compose.yaml`,
no por Dokploy) **no** instala tesseract — es un archivo upstream y el binario
de producción se gestiona por `railpack.json`/`nixpacks.toml`. Quien use
`docker-compose` para desarrollo local necesita instalar tesseract dentro del
contenedor a mano (o reconstruir con un `Dockerfile.override` propio) mientras
no exista una imagen de desarrollo separada para el fork.
