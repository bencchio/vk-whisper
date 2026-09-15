# Parámetro `--threads` (CPU) con Vulkan activo

Hipótesis a probar: con el grueso del cómputo en la iGPU (Vulkan), ¿menos
threads de CPU reduce cambios de contexto/overhead y da un total más
rápido?

Entorno: `large-v3-turbo-q8_0`, `jfk.wav`, `-bs 1`, Radeon 780M/RADV, 3
corridas por valor de `--threads`.

## Qué hace `--threads` en este pipeline

Solo afecta **la fase de mel-spectrogram** (`mel_ms` en los timings): la
conversión del audio crudo (forma de onda) a la representación
tiempo-frecuencia en escala mel que consume el encoder de Whisper. Es un
paso de CPU puro (FFTs), sin backend Vulkan — no hay GPU involucrada ahí.
El resto del pipeline (`encode`/`decode`/`batchd`) corre en la iGPU vía
Vulkan y no compite por esos hilos.

## Resultado

| threads | mel (avg) | total (avg) |
|---:|---:|---:|
| 1 | 30.99 ms | 1228.77 ms |
| 2 | 19.13 ms | 1268.63 ms |
| 4 | 11.50 ms | 1212.62 ms |
| 8 | 10.60 ms | 1215.56 ms |

## Conclusión

**La hipótesis no se confirma.** `mel_ms` escala casi linealmente con
threads (31ms→11ms de t=1 a t=4) porque es la única fase realmente
paralelizable en CPU; esa ganancia compensa cualquier overhead de
scheduling. El total con t=1 y t=4 queda prácticamente empatado dentro del
ruido de medición (t=2 salió peor que ambos, ruido, no tendencia real).
Después de t=4 los rendimientos son decrecientes (t=8 no mejora sobre
t=4) — consistente con que el 780M no tiene muchos más cores útiles para
esta tarea liviana.

## Recomendación

Mantener `--threads 4` (default del proyecto). Bajarlo a 1 no gana nada en
el total y penaliza la única fase que sí es CPU-bound; subirlo a 8 no
aporta sobre 4.

## Afinidad de CPU (`taskset`) y gobernador de frecuencia

Preguntas relacionadas: ¿ayuda pinnear el proceso a cores fijos (evitar
migración/cache-cold en L1/L2) o forzar el gobernador de CPU?

- **Gobernador**: ya está en `performance` por defecto en esta máquina
  (`cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`) — no hay
  rampa de frecuencia que evitar, nada que ganar ahí.
- **Afinidad** (`taskset -c 0-3` vs. sin pin, 3 corridas c/u,
  `large-v3-turbo-q8_0`, `-t 4`, `-bs 1`):

  | | total (avg) |
  |---|---:|
  | sin afinidad | 1203.73 ms |
  | `taskset -c 0-3` | 1200.58 ms |

  Diferencia de ~0.3%, dentro del ruido. La carga CPU-bound (mel, ~11ms)
  es demasiado corta y esporádica para que la migración entre cores
  importe, y con 16 cores libres el scheduler de Linux ya tiende a
  mantener un proceso corto en el mismo core sin necesidad de forzarlo.

**Conclusión**: no hay margen explotable en afinidad de CPU ni en
gobernador de frecuencia para este caso de uso — ambos ya están en su
punto óptimo (o no tienen suficiente carga CPU-bound para que importen).
