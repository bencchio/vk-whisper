# Benchmarks — vk-whisper (Vulkan)

Resumen de los hallazgos de optimización. Detalle completo por tema en
`vk/bench/`:

- [`vk/bench/beam-size.md`](bench/beam-size.md) — qué es `batchd`, resultados
  de barrer `beam-size`/`best-of` 1 a 6, calidad de transcripción y
  recomendación por caso de uso.
- [`vk/bench/vulkan-mul-mat-vec.md`](bench/vulkan-mul-mat-vec.md) — hipótesis
  de por qué el rendimiento tiene un salto abrupto entre bs=3 y bs=4
  (presión de registros en el shader `mul_mat_vec` de `ggml-vulkan`).
- [`vk/bench/lto.md`](bench/lto.md) — evaluación de `GGML_LTO` como flag de
  compilación.
- [`vk/bench/audio-ctx.md`](bench/audio-ctx.md) — impacto de recortar
  `--audio-ctx` (incluye una advertencia importante: valores muy bajos
  rompen el modelo, no solo degradan calidad).
- [`vk/bench/models-comparison.md`](bench/models-comparison.md) — comparación
  de calidad/velocidad/memoria entre 6 modelos multilingües (small-q8_0,
  medium-q8_0, large-v3-q5_0, large-v3-turbo y sus variantes) con audio real
  en español + jerga técnica en inglés.
- [`vk/bench/openmp.md`](bench/openmp.md) — `GGML_OPENMP` no afecta
  rendimiento con Vulkan activo, pero se mantiene por el fallback a CPU.
- [`vk/bench/compiler.md`](bench/compiler.md) — GCC vs Clang sin diferencia
  de runtime; Clang queda como compilador por defecto en `CMakePresets.json`.
- [`vk/bench/alternative-backends.md`](bench/alternative-backends.md) —
  ¿ROCm en vez de Vulkan? Bloqueado por un bug abierto específico de este
  chip (`gfx1103`). ¿Un modelo más moderno que Whisper? Parakeet-TDT/
  Canary (NVIDIA) atacarían el piso de latencia de 30s de Whisper con una
  arquitectura streaming-nativa — candidato serio para explorar a futuro,
  no se migra ahora por el costo de rehacer toda la validación.
- [`vk/bench/fft-optimization.md`](bench/fft-optimization.md) — mide
  aislado el FFT del mel-spectrogram (candidato real a migrar a C/SIMD/
  ASM): una versión iterativa es 2.5x más rápida, pero el ahorro absoluto
  es ~0.5% del tiempo total — no justifica la reescritura.
- [`vk/bench/language-auto-detect.md`](bench/language-auto-detect.md) —
  hallazgo de código + medición: `-l auto` corre el encoder dos veces
  (detección + transcripción real), +91% de tiempo de encode medido. No
  afecta la configuración actual del proyecto (idioma siempre fijo).
- [`vk/bench/memory-code-review.md`](bench/memory-code-review.md) —
  revisión de código (no de flags) buscando reducir memoria/transferencias:
  3 hallazgos reales en `whisper.cpp`, ninguno aplicable a este caso de uso
  (1 stream local, tiempo real, modelo grande, beam-size=1 fijo).
- [`vk/bench/shader-profile.md`](bench/shader-profile.md) — perfil real de
  shaders con `GGML_VK_PERF_LOGGER=1`: la proyección final a vocabulario
  (512→51864) es ~13% del tiempo de GPU por sí sola, más que la atención
  en varias fases — no optimizable sin cambiar el modelo, ya mitigado por
  cuantización.
- [`vk/bench/vulkan-env-vars.md`](bench/vulkan-env-vars.md) — variables
  `GGML_VK_*` de runtime (fusion, graph-optimize, mmvq, graphics queue):
  ninguna afecta el rendimiento en este caso de uso, probado con
  `large-v3-turbo-q8_0`.
- [`vk/bench/streaming-latency.md`](bench/streaming-latency.md) — latencia
  percibida real en `vk-whisper-stream` (voz en vivo, no archivo): probar
  `--step`/`--length`/VAD reveló que el `encode` tiene un piso fijo de
  ~800-900ms (Whisper siempre procesa una ventana de 30s) — bajar `--step`
  no ayuda y empeora la calidad; el default (`step=3000 length=10000`) es
  la mejor configuración probada.
- [`vk/bench/threads.md`](bench/threads.md) — prueba de la hipótesis
  "menos threads de CPU + iGPU = más rápido": no se confirma, `--threads 4`
  sigue siendo el mejor punto (la única fase CPU-bound es mel-spectrogram).
  Incluye afinidad de CPU (`taskset`) y gobernador de frecuencia: ninguno
  aporta, ya están en su óptimo o sin carga suficiente para importar.
- [`vk/bench/ggml-vendoring.md`](bench/ggml-vendoring.md) — decisión de
  mantener `ggml` vendorizado (no `WHISPER_USE_SYSTEM_GGML`), y estado del
  atraso respecto a upstream (3 cambios de Vulkan a revisar en un futuro
  sync, ninguno urgente).
- [`vk/bench/three-way-comparison.md`](bench/three-way-comparison.md) —
  comparación directa whisper.cpp genérico (sin flags de CPU) vs.
  whisper.cpp optimizado para este CPU vs. `vk-whisper`, los 3 con Vulkan
  y sobre los 7 audios reales de `vk/bench/recordings/`: sin diferencia
  medible (±0.4%) — con `GGML_VULKAN=ON` casi todo el cómputo corre en
  GPU, así que ni los flags de compilación de CPU ni los cambios propios
  del fork mueven la aguja en velocidad bruta. También documenta que
  `vk/orig/` (la copia vendorizada) está rota (le faltan archivos del
  v1.9.4 que declara).
- [`vk/bench/igpu-research.md`](bench/igpu-research.md) — investigación de
  técnicas modernas (drivers RADV, PRs de llama.cpp, extensiones Vulkan)
  para acelerar iGPUs: casi todo ya activo o no aplica a UMA; un solo
  hallazgo nuevo de bajo impacto (copia de staging evitable al cargar el
  modelo, no afecta inferencia).

Script de benchmark: `vk/bench/run.sh` (ver ese archivo para reproducir).
Datos crudos (no versionados) en `vk/bench/results/`.

## Entorno de todas las pruebas

- GPU: AMD Radeon 780M Graphics (RADV PHOENIX), backend `radv` vía Vulkan
- Modelo: `ggml-base.en.bin` (base.en, ~147 MB)
- Audio: `samples/jfk.wav` (11.0s)
- Threads: 4
- Build: `-DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON`

## Recomendación (resumen)

- **Tiempo real / streaming**: `beam-size=1` (greedy) — más rápido (-38% vs.
  default) y el más estable, sin el overhead de `batchd`.
- **Batch / offline**: `beam-size=2` — mejor balance velocidad/calidad
  (-24% vs. default), evitar `beam-size≥4` (salto de costo sin mejora de
  calidad observada).
- **`GGML_LTO`**: no usar en desarrollo (build ~2.7x más lento, <1% de
  ganancia); considerar solo para un build de release único y reusado.
- **`--audio-ctx`**: no reduce el total con `beam-size=1` (decode domina el
  tiempo) y valores muy bajos **rompen el modelo** (fallbacks, 5-25x más
  lento, peor calidad) — no usar cerca del límite sin validar por tipo de
  audio.
- **`GGML_OPENMP`**: dejar en `ON` (default). Con Vulkan activo no cambia el
  rendimiento (todo el cómputo pesado corre en GPU), pero es gratis y
  paraleliza correctamente el fallback a CPU cuando no hay GPU disponible.

## Vulkan con fallback automático a CPU

vk-whisper es "Vulkan-first" pero **no requiere GPU para funcionar**: con
build `-DGGML_VULKAN=ON` (que deja `GGML_CPU=ON` por default), en runtime
`whisper_backend_init` (`src/whisper.cpp:1298-1362`) busca un dispositivo
GPU y, si no lo encuentra (o se pasa `--no-gpu`), cae automáticamente al
backend CPU sin fallar — verificado corriendo `whisper-cli -ng`. No hace
falta ninguna configuración especial para esto: es el comportamiento nativo
de ggml, ya activo en este repo.

Detalle, tablas completas y metodología en los archivos de `vk/bench/`
enlazados arriba.

## Pendiente

- Validar el trade-off de calidad con audio ruidoso/con acentos (todo lo
  probado hasta ahora usa `jfk.wav`, audio limpio).
- Confirmar la hipótesis del salto bs=3→bs=4 con profiling real de GPU.
- Repetir con otros modelos (`small.en`, `medium.en`).
