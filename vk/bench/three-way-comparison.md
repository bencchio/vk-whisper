# Comparación de 3 vías: whisper.cpp genérico vs. optimizado vs. vk-whisper

Pregunta: ¿cuánto del rendimiento actual viene de usar Vulkan en sí (lo que
ya trae upstream) vs. de compilar optimizado para este CPU vs. de los
cambios propios de este fork? Comparación con 3 builds distintos, todas con
`GGML_VULKAN=ON` (misma GPU, misma iGPU AMD Radeon 780M):

1. **`vulkan_generic`** — whisper.cpp v1.9.4 upstream (clonado limpio de
   `ggml-org/whisper.cpp`, tag `v1.9.4`), `GGML_VULKAN=ON`,
   `GGML_NATIVE=OFF` — sin ningún flag de compilación específico para este
   CPU.
2. **`vulkan_native`** — el mismo whisper.cpp v1.9.4 upstream,
   `GGML_VULKAN=ON`, `GGML_NATIVE=ON` (default de ggml cuando no se
   cross-compila) — Vulkan + codegen de host optimizado para este CPU
   exacto.
3. **`vk_whisper`** — este repo (`build-x64-linux-vulkan-release`, sin
   LTO), con todos los cambios propios del fork.

## Metodología

- Modelo: `ggml-large-v3-turbo-q8_0.bin` (multilingüe, el mismo usado en
  [`models-comparison.md`](models-comparison.md)).
- Audio: los 7 audios reales en español de
  [`vk/bench/recordings/`](recordings/) (voz propia, mismos usados en
  `models-comparison.md`), convertidos a WAV 16kHz mono con `ffmpeg` (los
  `.ogg` no son el formato nativo que espera `whisper-cli`).
- Flags: `-l es -bs 1 -nt`, `--threads 4`.
- 3 corridas por combinación audio×variante, se reporta el promedio.
- **Nota de entorno importante**: `ggml` carga el backend Vulkan
  dinámicamente (`ggml_backend_load_all`, vía `dlopen`), no lo linkea
  directo — así que si `LD_LIBRARY_PATH` apunta a una instalación previa
  (en esta máquina, `~/Local/lib`, con una build vieja de `vk-whisper`),
  **los 3 binarios terminan cargando la misma librería** sin importar cómo
  se compilaron, invalidando la comparación en silencio. Todas las
  corridas de esta tabla se ejecutaron con `env -u LD_LIBRARY_PATH` para
  forzar que cada binario cargue su propia `libggml-vulkan.so.0` (se
  verificó con `ldd` antes de correr el benchmark real).
- `vk/orig/` (la copia vendorizada de whisper.cpp original en este repo)
  **no compila**: le faltan `cmake/DefaultTargetOptions.cmake` y todo
  `examples/cli/` respecto al v1.9.4 que declara en su propio
  `CMakeLists.txt` (`WHISPER_VERSION_*`). Por eso `vulkan_generic` y
  `vulkan_native` se armaron clonando `v1.9.4` limpio en un directorio
  temporal en vez de usar `vk/orig/`. Esto es un problema preexistente de
  `vk/orig/`, no introducido por esta medición — pendiente de revisar
  aparte.

## Resultado

| Audio | Duración | `vulkan_generic` | `vulkan_native` | `vk_whisper` |
|---|---:|---:|---:|---:|
| t1-software | 40s | 2587 ms (15.5x) | 2524 ms (15.8x) | 2467 ms (16.2x) |
| t2-kubernetes-v1 | 44s | 2471 ms (17.8x) | 2470 ms (17.8x) | 2494 ms (17.6x) |
| t2-kubernetes-v2 | 44s | 2464 ms (17.9x) | 2465 ms (17.9x) | 2465 ms (17.9x) |
| t3-viaje | 60s | 3087 ms (19.4x) | 3077 ms (19.5x) | 3067 ms (19.6x) |
| t4-finanzas | 50s | 2745 ms (18.2x) | 2751 ms (18.2x) | 2744 ms (18.2x) |
| t5-medico | 64s | 3416 ms (18.7x) | 3497 ms (18.3x) | 3485 ms (18.4x) |
| t6-personal | 60s | 2827 ms (21.2x) | 2880 ms (20.8x) | 2888 ms (20.8x) |

(tiempo total = `total time` de whisper-cli; factor entre paréntesis =
tiempo real del audio / tiempo total, cuánto más rápido que tiempo real)

**Promedio de tiempo total entre los 7 audios**: `vulkan_generic` 2799.6 ms,
`vulkan_native` 2809.1 ms, `vk_whisper` 2801.1 ms — diferencias de
±0.4%, dentro del ruido de medición (ver la variación entre corridas
individuales en `t5-medico` y `t6-personal`, donde una corrida ocasional
sube 2-5% sin patrón claro entre variantes).

## Conclusión

**No hay diferencia de rendimiento medible entre las 3 variantes.** Mismo
patrón que ya se documentó en [`compiler.md`](compiler.md) (GCC vs Clang)
y [`openmp.md`](openmp.md): con `GGML_VULKAN=ON`, prácticamente todo el
cómputo pesado (`encode`/`decode`) corre en la GPU vía shaders
precompilados — ni `GGML_NATIVE` (flags de CPU como `-march=native`) ni
los cambios específicos de `vk-whisper` (que son de configuración/uso, no
de código del hot path de cómputo) tienen margen para mostrar una
diferencia real en esta carga de trabajo. La ganancia real de este fork
frente al whisper.cpp genérico no está en velocidad bruta de inferencia,
sino en las decisiones de configuración/UX documentadas en el resto de
`vk/bench/` (selección de modelo, `beam-size`, manejo de audio en vivo,
etc.) — ver [`../benchmarks.md`](../benchmarks.md) para el resumen
completo.
