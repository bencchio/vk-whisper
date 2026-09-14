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

## Recomendación

No activar `GGML_LTO` en builds de desarrollo (el costo de compilación no se
justifica). Si en algún momento se arma un pipeline de release con un build
único reusado muchas veces (ej. imagen Docker, paquete distribuido),
activarlo no tiene downside en runtime — la fase de build es costo hundido,
pagado una sola vez — así que ahí sí conviene sumarlo (`-DGGML_LTO=ON`)
aunque la ganancia esperada sea marginal.
