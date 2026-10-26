# Puerta de fidelidad de los formatos (FMT-01, §4.5)

Antes de pasar al motor de **relleno** (FMT-02) hay que confirmar que el motor de
PDF (LibreOffice headless) produce un documento **igual** al que saca Word desde
el mismo `.docx`. Si el PDF de LibreOffice se ve distinto (fuentes cambiadas, logo
movido, tabla de daños descuadrada, saltos de página corridos), el motor **no
pasa** y no se sigue.

Esta verificación **no corre en el dev local**: necesita LibreOffice + las fuentes
instaladas, que solo están en el contenedor de despliegue. Por eso se hace en una
sesión con Julián, en el contenedor.

## Insumos

- Los 4 formatos originales de Karen. **NO están en el repo** (llevan el logo del
  cliente y el repo es público; ver FMT-05 §4 del ticket). Se bajan de la carpeta
  del proyecto en Drive y se dejan en una carpeta del contenedor, con estos nombres:
  - `visita-tecnica.docx`
  - `recoleccion.docx`
  - `garantia-cambio-devolucion.docx`
  - `garantia-reparada.docx`
- La tarea los busca en `HELIC3_FORMATOS_DIR` (por defecto `tmp/formatos-originales`
  dentro del contenedor).
- El contenedor con `libreoffice-writer-nogui` + fuentes
  (`fonts-crosextra-carlito`, `fonts-crosextra-caladea`, `fonts-liberation`), que
  entran por `railpack.json` / `nixpacks.toml`.

## Paso 1 — Generar los PDF con nuestro motor

Dentro del contenedor, primero dejar los 4 originales (bajados de Drive) en la
carpeta que la tarea espera, y luego correrla:

```bash
mkdir -p tmp/formatos-originales
# copiar ahí visita-tecnica.docx, recoleccion.docx,
# garantia-cambio-devolucion.docx y garantia-reparada.docx (desde Drive)
bundle exec rake helic3:formatos:fidelidad
```

(Si los dejas en otra ruta, pásala con `HELIC3_FORMATOS_DIR=/ruta bundle exec rake ...`.)

La tarea, por cada formato: convierte `docx → fodt → pdf`, verifica que el
contenido clave sobrevive (si falta una palabra distintiva, LibreOffice no leyó
bien el `.docx` y la tarea falla con código ≠0), y deja el PDF en `tmp/fidelidad/`:

- `tmp/fidelidad/visita-tecnica.pdf`
- `tmp/fidelidad/recoleccion.pdf`
- `tmp/fidelidad/garantia-cambio-devolucion.pdf`
- `tmp/fidelidad/garantia-reparada.pdf`

## Paso 2 — Exportar los PDF de referencia desde Word

Abrir cada `.docx` original en Word y exportarlo con **Archivo → Guardar como →
PDF** (o "Exportar a PDF"). Estos son los PDF "patrón" contra los que comparamos.
(Los puede entregar Karen directamente, para no depender de la versión de Word.)

## Paso 3 — Comparar a ojo (checklist)

Poner lado a lado el PDF de `tmp/fidelidad/` y el de Word, por cada formato:

- [ ] **Logo** de Only Home presente, en la misma posición y sin deformar.
- [ ] **Fuentes** iguales (tamaño y tipo); el texto no se ve "corrido" ni con otra letra.
- [ ] **Tabla de daños** (visita técnica y recolección) completa y alineada:
      las 4 secciones (MADERA, TELA, PINTURA Y ACABADO, CROMADO) con sus ítems y
      las columnas *Daño / Aplica / Piezas afectadas / Observaciones*.
- [ ] **Tildes y eñes** correctas (DIRECCIÓN, VERIFICACIÓN, reparación, garantía…).
- [ ] **Saltos de página** en el mismo lugar (que no se parta una tabla a la mitad
      distinto a como lo hace Word).
- [ ] **Firmas y campos** del pie (NOMBRE, CÉDULA, FIRMA CLIENTE/CONDUCTOR, CARGO)
      en su sitio.

## Resultado

- **Pasa** si los 4 formatos se ven equivalentes al PDF de Word (diferencias
  mínimas de espaciado son aceptables; lo que no se acepta es fuente distinta,
  logo roto o tabla descuadrada).
- **No pasa** si alguno se ve claramente distinto → anotar qué formato y qué falló,
  y revisar fuentes faltantes o estilos del `.docx` antes de reintentar.

Solo cuando pasa la puerta de fidelidad se arranca FMT-02 (relleno de la plantilla).
Ver el estado del motor en [`conversor.rb`](../../app/services/helic3/formatos/conversor.rb)
y la convención de paquetes del contenedor en `railpack.json` / `nixpacks.toml`.
