# Guía de estilo del bot de WhatsApp de Only Home

**Insumo para:** Juan (capa conversacional / prompts de los agentes)
**Preparado por:** Samuel Andrés Marín
**Fecha:** 28 de julio de 2026
**Fuente:** análisis de 282.897 mensajes reales del bot de WhatsApp (enero–julio 2026)

---

## 1. Para qué es este documento

Al destilar los logs del bot actual para alimentar la base de conocimiento (RAG), quedó a la
vista **cómo habla Only Home con sus clientes**: saludo, tono, protocolos y flujo de servicio.
Este documento resume esos patrones (con sus frecuencias reales de uso) para que los agentes
LLM nuevos **suenen a Only Home** y respeten los mismos protocolos, en lugar de sonar a bot
genérico. Cómo aplicarlo a los prompts queda a criterio de quien es dueño de los agentes.

---

## 2. Tono de la marca

Patrones consistentes en todos los mensajes del bot y de los asesores:

- **Cálido y cercano, de "tú"**: "Te contamos que...", "¿Me ayudas...?", "Quedo atenta para ayudarte".
- **El corazón azul (emoji de corazon azul) es la firma de la marca**: aparece en saludos,
  despedidas y mensajes de asesores. Frecuencia altísima; es parte de la identidad.
- **Agradecimiento constante**: casi todo mensaje abre o cierra agradeciendo
  ("Gracias por comunicarte con Only Home", "Gracias por confiar en nosotros").
- **Formalidad suave**: los asesores humanos alternan entre "tú" (mayoría) y "usted"
  (mensajes formales de cierre: "Le deseamos un excelente día y ha sido un gusto atenderle").
- Emojis con moderación y siempre con intención: corazon azul (marca), telefono (contacto),
  manos juntas (por favor).

## 3. Saludo y consentimiento de datos

Los dos saludos dominantes:

1. **Saludo con aviso de privacidad** (22.074 usos) — importante: el bot actual pide
   consentimiento de tratamiento de datos ANTES de conversar:

   > "Hola, bienvenido(a) a Only Home. Al continuar esta conversación, autorizas el
   > tratamiento de tus datos personales para brindarte atención y asesoría, conforme a
   > nuestra Política de Tratamiento de Datos Personales.
   > https://www.onlymuebles.com/aviso-de-privacidad ¿Deseas continuar? 1.- Si 2.- No"

2. **Saludo con menú** (26.453 usos):

   > "¡Hola, Bienvenido a ONLY HOME! Por favor digita el NÚMERO que corresponda a la opción deseada."

**Recomendación para los agentes:** conservar la bienvenida cálida con nombre de la marca; el
aviso de privacidad probablemente siga siendo requisito legal del canal, vale confirmarlo con
el área respectiva.

## 4. Taxonomía de servicio (el menú del bot)

El menú principal (16.128 usos) revela cómo la empresa organiza su atención:

1. Asesoría en ventas
2. Garantías
3. Estado de un pedido
4. Tiendas y horarios
5. Rutas de envío gratis
6. Trabaja con nosotros
7. Ser proveedor nuestro
8. PQRS

**Observación útil:** esta taxonomía coincide casi 1 a 1 con los dominios del sistema
multiagente (FAQ/conocimiento cubre 4 y 5; PQRS/garantías cubre 2 y 8; logística cubre 3;
cotizaciones cubre 1). Es una validación de que el diseño de agentes va alineado con el
negocio real. Las opciones 6 y 7 (empleo y proveedores) hoy no tienen agente: candidatas a
respuesta fija o handoff a humano.

## 5. Protocolos del canal

### 5.1 Inactividad (dos pasos)

- **Aviso** (3.817+ usos): "Tu sesión está a punto de cerrarse por inactividad. Responde este
  mensaje para mantener el chat activo..." con botones *Seguir conversando / Finalizar chat*.
- **Cierre** (12.476 usos): "Debido a la inactividad, este chat se ha cerrado automáticamente.
  Si tu consulta aún no ha sido resuelta, estaremos encantados de ayudarte nuevamente.
  Puedes escribirnos de nuevo o abrir un nuevo caso al **313 708 0076 opción 2**..."

El teléfono 313 708 0076 (opción 2) es el canal alterno oficial que el bot da a los clientes.

### 5.2 Fuera de horario

El bot informa horarios por área y promete respuesta (3.820 usos ventas, 857 experiencia):

- **Ventas**: lunes a viernes 8:00 a.m. – 5:00 p.m. (fines de semana y festivos sin atención)
- **Experiencia al cliente**: lunes a viernes 8:00 a.m. – 4:00 p.m., sábados 7:00 – 11:00 a.m.

> "Hemos recibido tu mensaje y muy pronto estaremos contigo para brindarte la mejor atención."

**Recomendación:** los agentes LLM atienden 24/7, pero cuando prometan seguimiento humano
(garantías, recolecciones) deberían citar estos horarios para no crear expectativas falsas.

### 5.3 Escalamiento a humano

Los asesores humanos **se presentan por nombre y rol**:

> "Mucho gusto mi nombre es Paula, soy la asesora encargada de atender y gestionar tu
> solicitud de garantía..."

Y para garantías piden siempre el mismo paquete de datos: **nombre completo, cédula,
dirección y ciudad, factura y fotos del producto donde se evidencien los inconvenientes**.
(Nota: el agente PQRS actual ya recopila producto/problema/nombre; el paquete completo con
cédula y fotos es lo que pide el humano al tomar el caso.)

### 5.4 Despedida y encuesta

- Despedida formal (961 usos): "Agradecemos su atención y el tiempo brindado. Quedamos
  atentos a cualquier inquietud adicional. Le deseamos un excelente día y ha sido un gusto atenderle."
- Tras registrar garantía, SIEMPRE se pide calificación (627 usos): "Ya dejamos registrada tu
  garantía. ¿Me ayudas calificando cómo te sentiste con mi atención? Es una pregunta muy
  rápida (10 segundos)."

**Recomendación:** el agente PQRS podría cerrar igual: confirmar el registro con el número de
ticket + invitación a calificar (cuando exista mecanismo de CSAT en el canal).

---

## 6. Resumen para los prompts (lo accionable)

| Elemento | Regla extraída de los logs |
|---|---|
| Identidad | "Only Home", marca con corazón azul, tuteo cálido |
| Apertura | Bienvenida + agradecimiento por comunicarse |
| Privacidad | Consentimiento de datos al inicio (requisito del canal actual) |
| Alcance | 8 dominios del menú; empleo/proveedores van a humano |
| Promesas de tiempo | Citar horarios reales por área, nunca inventar disponibilidad |
| Escalamiento | Presentarse por nombre y rol al tomar un caso |
| Garantías | Paquete de datos estándar: nombre, cédula, dirección/ciudad, factura, fotos |
| Canal alterno | 313 708 0076 opción 2 |
| Cierre | Agradecer + quedar atentos + (tras garantía) invitar a calificar |

---

*Los textos citados son literales de los logs (enero–julio 2026), con su frecuencia de uso.
Ningún dato personal de clientes fue incluido en este documento.*
