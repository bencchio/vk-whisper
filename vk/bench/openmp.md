# Flags de compilación: `GGML_OPENMP`

Probado `-DGGML_OPENMP=OFF` (default `ON` en `ggml/CMakeLists.txt`) contra
el build normal. Mismo protocolo que `beam-size.md`: 7 corridas, bs=1 y
bs=2, `base.en` + `jfk.wav`.

| bs | con OpenMP: total (sd) | sin OpenMP: total (sd) | diferencia |
|---:|-------------------------:|--------------------------:|-----------:|
| 1 | 287.19 ms (6.31) | 286.84 ms (2.53) | -0.1% (ruido) |
| 2 | 358.48 ms (4.79) | 359.58 ms (2.64) | +0.3% (ruido) |

## Conclusión

Ninguna diferencia medible. Con `GGML_VULKAN=ON`, prácticamente todo el
cómputo pesado (`encode`/`decode`/`batchd`) corre en la GPU vía Vulkan, no
en la CPU — OpenMP solo paralelizaría trabajo que queda en CPU (parte del
preprocesamiento), que aquí es una fracción mínima del tiempo total. Sin
OpenMP la desviación estándar bajó levemente (más consistente), pero dentro
del margen de ruido.

## Recomendación

**Dejar `GGML_OPENMP=ON` (su default)**. No aporta ni resta rendimiento con
el backend Vulkan activo, pero sí importa como red de seguridad para el
**fallback a CPU**: si en algún sistema no hay GPU compatible con Vulkan, o
se fuerza `--no-gpu`, ahí el cómputo pasa a `ggml-cpu` y OpenMP sí paraleliza
ese trabajo de forma real. Desactivarlo no gana nada en el caso GPU y
perjudicaría el caso CPU-only.
