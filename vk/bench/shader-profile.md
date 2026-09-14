# Perfil real de shaders (GGML_VK_PERF_LOGGER)

`ggml-vulkan` trae un profiler integrado activable con
`GGML_VK_PERF_LOGGER=1` en el entorno — da tiempo real por operación/shader,
no solo por fase (encode/decode/batchd) como `whisper_print_timings`. Se usó
para identificar qué shaders dominan realmente la carga de trabajo, más
allá de la hipótesis de `vulkan-mul-mat-vec.md`.

Entorno: `base.en` + `jfk.wav` (11s), `-bs 1`, Radeon 780M/RADV.

```
GGML_VK_PERF_LOGGER=1 whisper-cli -m models/ggml-base.en.bin -f samples/jfk.wav -bs 1
```

## Desglose por operación (corrida completa)

| Operación | n | Tiempo | % del total GPU |
|---|---:|---:|---:|
| FLASH_ATTN_EXT | 330 | 33.11ms | 21.2% |
| ADD | 604 | 26.87ms | 17.2% |
| MUL_MAT f16 (encoder) | 50 | 26.81ms | 17.2% |
| MUL_MAT_VEC f16 | 189 | 22.71ms | 14.5% |
| MUL_MAT_ADD MUL_MAT_VEC f16 | 648 | 9.82ms | 6.3% |
| MUL_MAT_ADD_ADD MUL_MAT_VEC f16 | 486 | 9.52ms | 6.1% |
| CPY | 375 | 7.90ms | 5.1% |
| MUL | 526 | 6.51ms | 4.2% |
| NORM | 526 | 4.98ms | 3.2% |
| GELU | 170 | 4.93ms | 3.2% |
| SCALE | 330 | 2.35ms | 1.5% |
| resto (IM2COL, GET_ROWS, CONT) | — | 0.61ms | 0.4% |
| **Total tiempo GPU** | | **156.12ms** | |

## Hallazgo: la proyección final a vocabulario domina `MUL_MAT_VEC`

Dentro del bucket `MUL_MAT_VEC f16`, la proyección `m=51864 n=1 k=512`
(hidden state → logits sobre las 51864 palabras del vocabulario) representa:

```
grep "MUL_MAT_VEC f16 m=51864" perf.log
→ 27 llamadas, 20.47ms de los 22.71ms del bucket (~90%)
```

Es decir, **~13% de todo el tiempo de GPU de la corrida** se gasta
únicamente en proyectar al vocabulario, con solo 27 llamadas (una por token
generado en esta transcripción). No es atención, no son las capas del
transformer — es la capa de salida.

### Por qué

Whisper tiene un vocabulario inusualmente grande (51864 tokens, por soporte
multilingüe + tokens especiales) relativo a su dimensión oculta chica (512
en `base`). Esa proyección final (`512 → 51864`) se paga completa por cada
token generado, independientemente del tamaño del resto del modelo — a
diferencia de las capas de atención/FFN, que sí escalan con el tamaño del
modelo pero no con el tamaño del vocabulario.

### ¿Es optimizable?

No a nivel de shader/código de este proyecto:

- Es matemáticamente necesaria para obtener probabilidades sobre todo el
  vocabulario en decodificación estándar — no hay atajo sin cambiar el
  algoritmo de decodificación.
- La única vía real de reducir su costo es **cuantizar esa capa** (ya
  cubierto indirectamente al elegir modelos `q8_0`/`q5_0` en vez de fp16,
  ver `models-comparison.md` — la cuantización no distingue por capa, así
  que ya se está beneficiando de esto sin acción adicional).
- Técnicas más profundas (adaptive softmax, vocabulario jerárquico)
  cambiarían la arquitectura del modelo — se definen en el entrenamiento
  original de Whisper, no son algo ajustable en inferencia.

## Conclusión

El perfil real confirma que el costo de generación por-token en whisper no
está dominado por atención como uno esperaría por defecto, sino que la
proyección de vocabulario es un contribuyente grande y "invisible" en los
timings agregados de `whisper_print_timings` (aparece diluida dentro de
`decode`/`batchd`). No hay acción de código pendiente aquí — es una
característica estructural del modelo, ya mitigada por la recomendación de
usar modelos cuantizados.
