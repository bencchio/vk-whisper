# `-l auto` duplica el costo de encode (hallazgo de código + medición)

Revisando `whisper_full_with_state` (`src/whisper.cpp:6918`) buscando
oportunidades de reducir latencia/cómputo más allá de lo ya cubierto en
`memory-code-review.md` (que se enfocó en buffers/KV-cache).

## El problema

Cuando `params.language` es `nullptr`, vacío o `"auto"` (y
`params.detect_language == false`), `whisper_full_with_state` corre un
**encode + decode completos solo para detectar el idioma**
(`whisper_lang_auto_detect_with_state`, `src/whisper.cpp:4125-4144`, llama
a `whisper_encode_with_state` con `seek=0`) y **luego** el flujo principal
corre su propio encode (`whisper_encode_internal`,
`src/whisper.cpp:7160`) para la transcripción real. No hay ningún caché
que reutilice el resultado del primer encode — son dos pasadas
completas e independientes por el encoder.

## Medición

`large-v3-turbo-q8_0`, `jfk.wav` (inglés), `-bs 1`:

| | encode total | runs |
|---|---:|---:|
| `-l en` (idioma explícito) | 808.01 ms | 1 |
| `-l auto` (detección) | 1544.14 ms | 2 |

**+91% de tiempo de encode** por usar `-l auto` en vez de fijar el idioma
— casi exactamente el doble, como predice el código.

## Impacto en el caso de uso del proyecto

`examples/vk-stream/stream.cpp` ya usa un default explícito
(`language = "en"`, línea 49) y en nuestras pruebas de streaming siempre
pasamos `-l es` — **este hallazgo no afecta la configuración actual**. Se
documenta como advertencia para no caer en esto en el futuro: usar
`-l auto` en un stream en tiempo real (por conveniencia, para no fijar
idioma) pagaría el doble de costo de encode **en cada llamada**, no solo
la primera.

## Si alguna vez se necesita soporte multilenguaje real en streaming

Patrón recomendado en vez de `-l auto` por llamada: detectar el idioma
**una sola vez** (con `params.detect_language = true` sobre el primer
chunk, o simplemente `-l auto` en la primera llamada) y despues fijar
`params.language` al resultado (`state->lang_id`/`whisper_lang_str`) para
todas las llamadas siguientes del mismo stream. Esto es un cambio en la
aplicación (`stream.cpp`), no en la librería — no se implementó porque el
caso de uso actual es de idioma fijo conocido de antemano.
