# GCC vs Clang

Comparación de runtime compilando el mismo código con GCC 16.2.1 y
Clang 22.1.8, mismo protocolo que `beam-size.md` (7 corridas, bs=1 y bs=2,
`base.en` + `jfk.wav`, `-DGGML_VULKAN=ON`).

## Resultado (primera tanda)

| | GCC: total (sd) | Clang: total (sd) | diferencia |
|---|---:|---:|---:|
| bs=1 | 281.88 ms (11.28) | 280.97 ms (1.52) | -0.3% |
| bs=2 | 351.08 ms (16.14) | 346.40 ms (5.11) | -1.3% |

La media es prácticamente igual, pero la desviación estándar de GCC fue
mucho mayor. Una segunda tanda corrida más próxima en el tiempo (5 corridas,
bs=1) mostró una diferencia de consistencia mucho más chica:

| | GCC: total (sd) | Clang: total (sd) |
|---|---:|---:|
| bs=1 | 280.73 ms (5.75) | 279.80 ms (3.68) |

## Conclusión

**Sin diferencia de rendimiento significativa entre GCC y Clang** para esta
carga de trabajo. Tiene sentido: con `GGML_VULKAN=ON` casi todo el cómputo
pesado corre en la GPU, así que el código generado por el compilador del
host (que solo afecta mel/sampling/glue) tiene poco margen para mostrar
diferencias reales — mismo patrón que ya vimos con `GGML_OPENMP` y
`GGML_LTO`. La mayor varianza de GCC en la primera tanda fue ruido puntual
del sistema (térmico o algún proceso de fondo), no reproducido de forma
consistente en la segunda.

## Decisión: Clang por defecto

Sin diferencia de runtime, el criterio de desempate es velocidad de
compilación. `CMakePresets.json` usa Clang (`x64-linux-clang`) como
compilador por defecto en los presets `x64-linux-vulkan-*`; se agregó
`x64-linux-vulkan-gcc-release` como alternativa explícita si hace falta
compilar con GCC (por ejemplo, para reproducir el fix de `-Wnonnull` de
`ggml-vulkan.cpp`, que es específico de GCC).
