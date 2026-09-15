# ¿Vale la pena optimizar/reescribir el FFT de whisper.cpp?

Contexto: buscando código candidato a migrar a C/SIMD/ASM para ganar
velocidad (más allá de `ggml`, que ya está en su óptimo — ver
`ggml-vendoring.md`). El único candidato real encontrado en `whisper.cpp`
es el FFT del cálculo de mel-spectrogram
(`src/whisper.cpp:3105`, función `fft()`), cuyo propio comentario dice
*"poor man's implementation - use something better"*: Cooley-Tukey
recursivo, escalar, sin SIMD, con splits de pares/impares que mueven
memoria en cada nivel de recursión.

## Medición aislada

Microbenchmark standalone (no modifica el repo) con el algoritmo exacto
copiado de `whisper.cpp` (mismas constantes: `WHISPER_N_FFT=400`,
tabla de sin/cos precalculada), simulando los ~3000 frames que se
calculan por llamada (whisper siempre rellena el mel a una ventana de 30s,
ver `streaming-latency.md`), compilado con `-O3 -march=native` (mismas
flags que el build Release del proyecto):

| Versión | 3000 frames, 1 thread | ~4 threads (estimado, escalamiento perfecto) |
|---|---:|---:|
| Recursiva actual (whisper.cpp) | 38.42 ms | ~9.6 ms |
| Iterativa radix-2, in-place, sin SIMD manual (`double`, zero-pad a 512) | 15.11 ms | ~3.8 ms |

La versión iterativa es **2.5x más rápida** que la recursiva, a pesar de
usar `double` (más pesado que el `float` de whisper.cpp) — la ganancia
viene de evitar la recursión y el movimiento de memoria por
pares/impares en cada nivel, no de precisión ni de SIMD.

El resultado single-thread de la versión recursiva (38.4ms) coincide con
el `mel_ms` medido con `-t 1` en `threads.md` (30.99ms, mismo orden de
magnitud considerando que el microbenchmark no incluye windowing/filtro
mel) — confirma que el FFT es la parte dominante del tiempo de `mel_ms`,
no la aplicación de filtros mel.

## Conclusión

El ahorro real de migrar este FFT (a una versión iterativa, o más allá,
a SIMD/asm) sería de **~5.8ms sobre un total de ~1200ms por
transcripción — ~0.5% del tiempo total**. Es una mejora real y medible
en el componente que se toca (2.5x), pero el componente en sí (`mel_ms`,
~1% del total) es demasiado chico para que importe en el balance general,
dominado por el piso fijo de ~800ms de `encode` en GPU
(`streaming-latency.md`) — igual que el resto de los ejes ya descartados
en esta sesión (threads, afinidad de CPU, variables Vulkan).

No se recomienda esta migración: el costo de reescribir y probar código
de bajo nivel no se justifica frente a una ganancia no medible fuera del
ruido de los benchmarks ya hechos.

## Por qué no hay otro candidato de C/Rust/ASM con más upside

El resto del cómputo pesado del proyecto (>95% del tiempo) ya corre en
shaders GLSL compilados a SPIR-V (`ggml-vulkan`) — el equivalente real a
"código de bajo nivel" en este contexto, ejecutado en GPU. El backend
`ggml-cpu` (fallback sin GPU) ya tiene kernels con intrínsecos SIMD
(AVX2/AVX-512/NEON) escritos a mano en C, no C++. El código C++ de
orquestación restante (`whisper.cpp`, `stream.cpp`) es una fracción tan
chica del tiempo total que el lenguaje/nivel de abstracción no puede
moverle la aguja al resultado final — el cuello de botella es GPU-bound,
no CPU-bound.
