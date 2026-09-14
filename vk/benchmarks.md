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

Detalle, tablas completas y metodología en los archivos de `vk/bench/`
enlazados arriba.

## Pendiente

- Validar el trade-off de calidad con audio ruidoso/con acentos (todo lo
  probado hasta ahora usa `jfk.wav`, audio limpio).
- Confirmar la hipótesis del salto bs=3→bs=4 con profiling real de GPU.
- Repetir con otros modelos (`small.en`, `medium.en`).
