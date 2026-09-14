# Benchmarks — vk-whisper (Vulkan)

Generado con `vk/bench/run.sh`. Datos crudos en `vk/bench/results/history.csv`
y logs individuales en `vk/bench/results/*.log`.

## Entorno

- GPU: AMD Radeon 780M Graphics (RADV PHOENIX), backend `radv` vía Vulkan
- Modelo: `ggml-base.en.bin` (base.en, ~147 MB)
- Audio: `samples/jfk.wav` (11.0s)
- Threads: 4
- Build: `-DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON`

## Qué es `batchd`

Whisper transcribe en dos grandes fases:

1. **Encoder** (`encode`): lee el audio completo (convertido a espectrograma
   mel) una sola vez y produce una representación interna. Es una sola
   pasada, siempre del mismo tamaño — por eso `encode` no cambia sin importar
   qué parámetros de decodificación uses.
2. **Decoder**: a partir de esa representación, genera el texto **token por
   token**, y este proceso se repite muchas veces — una vez por cada token de
   la transcripción.

La diferencia entre `decode` y `batchd` es *cuántas hipótesis de texto* está
generando el decoder al mismo tiempo en cada uno de esos pasos:

- Con `beam-size=1` (greedy), el decoder elige **una sola palabra** a la vez,
  la más probable, y sigue con esa. Cada paso procesa 1 token → se cuenta como
  `decode`.
- Con `beam-size=N>1` (beam search), en vez de comprometerse con una sola
  opción, el decoder mantiene **N transcripciones candidatas en simultáneo**
  ("beams") y en cada paso las expande a todas juntas, para después quedarse
  con la que termine teniendo mejor puntaje global. Como cada paso ahora
  procesa un pequeño lote de N candidatos en vez de 1, ese trabajo se cuenta
  aparte, como **`batchd`** ("batch decode").

Pensalo como la diferencia entre escribir una frase comprometiéndote palabra
por palabra (greedy) vs. tener N "borradores" de la frase escribiéndose en
paralelo y elegir al final el mejor borrador completo (beam search) — esto
último da más chance de corregir un error temprano, pero cuesta más trabajo
por paso. `batchd` es exactamente ese costo extra: el tiempo que se va en
mantener y evaluar esos borradores en paralelo en la GPU.

`best-of` no afecta esto: en modo beam search la salida y el tiempo dependen
solo de `beam-size`; `best-of` únicamente decide la estrategia cuando
`beam-size=1` (greedy).

`decode` y `batchd` son mutuamente excluyentes dentro de una misma corrida:
con `bs=1` todo el trabajo de generación cae en `decode`; en cuanto `bs≥2`
ese trabajo pasa a contarse como `batchd`, y lo que queda en `decode` (5-9ms)
es residual — pasos puntuales donde igual se procesó un solo token.

## Resultado: beam-size 1 a 6 (7 corridas c/u, `-bs N -bo N`)

| bs | encode (ms) | decode (ms) | batchd (ms) | total (media, ms) | total sd (ms) |
|---:|------------:|------------:|------------:|-------------------:|--------------:|
| 1 (greedy) | 82.8 | 91.0 | 0.0 | **268.6** | 5.2 |
| 2 | 82.9 | 5.0 | 134.7 | **331.2** | 3.0 |
| 3 | 83.8 | 8.8 | 132.1 | **335.3** | 2.5 |
| 4 | 84.6 | 5.2 | 195.2 | **402.3** | 3.8 |
| 5 (default) | 83.8 | 8.9 | 214.7 | **435.4** | 4.2 |
| 6 | 84.1 | 8.9 | 239.4 | **467.5** | 3.4 |

`encode` se mantiene estable (~83-85ms) en todo el rango, como se espera —
confirma que las diferencias en `total` vienen del decoder, no de ruido en el
encoder. `batchd` crece con `bs`, pero no linealmente: bs=2→3 casi no cambia
(134.7→132.1ms), bs=3→4 pega un salto grande (+63ms), y de ahí en más escala
de forma más gradual. Sigue sugiriendo que hay un tamaño de batch "incómodo"
para el dispatch de Vulkan entre bs=3 y bs=4 (pendiente investigar en
`ggml-vulkan`).

## Calidad de transcripción

Sobre este audio limpio (`jfk.wav`):

- bs=1, 3, 5: transcripción idéntica.
- bs=2, 6: idéntica salvo una palabra en mayúsculas ("not" → "NOT").
- bs=4: partió la transcripción en dos segmentos en vez de uno.

Sin evidencia de pérdida real de calidad al bajar `beam-size` en este sample
— falta validar con audio ruidoso/difícil antes de generalizar.

## Recomendación por caso de uso

**Tiempo real / streaming** (server con requests continuas, cliente esperando
respuesta en vivo): usar **`bs=1` (greedy)**. Acá lo que importa no es el
promedio sobre un archivo completo sino la latencia por chunk y sobre todo la
**consistencia en el peor caso** — hay que mantenerse más rápido que el audio
entrante sin acumular atraso. bs=1 es la opción más rápida (-38% vs. default)
y no pasa por `batchd`, evitando el overhead de mantener beams en paralelo
que puede introducir picos.

**Batch / offline** (transcribir archivos ya grabados, sin restricción de
tiempo real): usar **`bs=2`** (~331ms, -24% vs. default, y la desviación
estándar más baja de las opciones con beam search). `bs=3` da un resultado
estadísticamente similar en este set (~335ms) pero sin ventaja clara sobre
bs=2 para justificar su leve costo extra. Evitar `bs≥4`: el salto de costo no
viene acompañado de mejora de calidad observable en las pruebas hechas hasta
ahora.

## Pendiente

- Validar el trade-off de calidad con audio ruidoso/con acentos (todo lo
  anterior se probó solo sobre `jfk.wav`, audio limpio).
- Investigar la ineficiencia de dispatch entre bs=3 y bs=4 en `ggml-vulkan`.
- Repetir con otros modelos (`small.en`, `medium.en`).
