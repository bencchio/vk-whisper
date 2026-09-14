# Flags de compilación: `GGML_LTO`

Probado `-DGGML_LTO=ON` (Link Time Optimization), off por default en
`ggml/CMakeLists.txt`. Comparación con el mismo protocolo de
[`beam-size.md`](beam-size.md) (7 corridas, bs=1 y bs=2):

| bs | sin LTO: total (sd) | con LTO: total (sd) | diferencia |
|---:|---------------------:|----------------------:|-----------:|
| 1 | 268.6 ms (5.2) | 266.4 ms (2.4) | -0.8% |
| 2 | 331.2 ms (3.0) | 330.9 ms (2.0) | -0.1% |

Tiempo de build: ~2.7x más lento con LTO (2m44s vs. build normal en esta
máquina).

## Conclusión

La ganancia en runtime es prácticamente nula (<1%, dentro del ruido de
medición) — el cuello de botella sigue siendo el dispatch de Vulkan, no el
código C++ del host donde LTO ayudaría (inlining entre `ggml`, `ggml-cpu`,
`whisper`). Sí bajó levemente la desviación estándar en ambos casos, lo que
indica algo más de consistencia, pero no alcanza para justificar el costo
por sí solo.

## LTO con Clang

Repetido con Clang 22.1.8 (compilador por defecto del proyecto desde
`vk/bench/compiler.md`), mismo protocolo:

| bs | sin LTO: total (sd) | con LTO: total (sd) | diferencia |
|---:|---------------------:|----------------------:|-----------:|
| 1 | 280.97 ms (1.52) | 273.44 ms (3.91) | -2.7% |
| 2 | 346.40 ms (5.11) | 340.51 ms (3.33) | -1.7% |

Tiempo de build: **9m48s** (vs. ~2m44s con GCC+LTO — ~3.6x más lento que el
LTO de GCC en esta misma máquina).

Con Clang la ganancia de runtime es algo mayor que con GCC (hasta -2.7% vs.
<1%), pero el costo de build es dramáticamente peor. Probablemente porque
el LTO de Clang en esta configuración es más agresivo que el de GCC.

## Recomendación

No activar `GGML_LTO` en builds de desarrollo con ningún compilador (el
costo de compilación no se justifica en ninguno de los dos casos). Si en
algún momento se arma un pipeline de release con un build único reusado
muchas veces (ej. imagen Docker, paquete distribuido), activarlo no tiene
downside en runtime — la fase de build es costo hundido, pagado una sola
vez — pero ahí conviene usar **GCC** para ese build específico en vez de
Clang: gana una fracción similar de rendimiento por una fracción del costo
de compilación (2m44s vs. 9m48s).
