# Variables de entorno de ggml-vulkan

`ggml-vulkan.cpp` expone bastantes variables `GGML_VK_*` para tunear/
depurar el backend en runtime (lista completa vía
`grep 'getenv("GGML_VK' ggml/src/ggml-vulkan/ggml-vulkan.cpp`). Se probaron
las que tienen mayor probabilidad de afectar rendimiento real (se excluyen
las que son solo de logging/debug: `GGML_VK_DEBUG_MARKERS`,
`GGML_VK_PERF_LOGGER`, `GGML_VK_SYNC_LOGGER`, `GGML_VK_MEMORY_LOGGER`,
`GGML_VK_PIPELINE_STATS`).

Entorno: **`large-v3-turbo-q8_0`** (modelo real recomendado del proyecto,
no `base.en`), `jfk.wav`, `-bs 1`, Radeon 780M/RADV, 5 corridas por
configuración.

## Resultado

| Configuración | total (media) | sd |
|---|---:|---:|
| baseline (sin variables) | 1190.11 ms\* | 25.33 |
| `GGML_VK_DISABLE_GRAPH_OPTIMIZE=1` | 1153.98 ms | 19.29 |
| `GGML_VK_DISABLE_FUSION=1` | 1179.72 ms | 3.07 |
| `GGML_VK_ALLOW_GRAPHICS_QUEUE=1` | 1188.00 ms | 34.28 |
| `GGML_VK_FORCE_MMVQ=1` | 1191.21 ms | 5.25 |
| `GGML_VK_DISABLE_MMVQ=1` | 1188.56 ms | 10.77 |

\* La primera corrida del baseline dio 1448ms (outlier de arranque en frío,
mismo patrón visto en sesiones anteriores) — excluida del promedio.

## Conclusión

**Ninguna variable produjo una diferencia fuera del ruido de medición**
(todas dentro de ±3% del baseline, rangos superpuestos considerando la
desviación estándar). Incluso `GGML_VK_DISABLE_FUSION` y
`GGML_VK_DISABLE_GRAPH_OPTIMIZE` — que deberían *empeorar* el rendimiento
al desactivar optimizaciones — no mostraron la regresión esperada.

Hipótesis: en este workload (audio corto, decode dominado por overhead de
dispatch por-token más que por throughput bruto de cómputo, ver
`shader-profile.md`), estas optimizaciones de alto nivel del scheduler no
tienen suficiente margen para mostrarse, o el grafo de whisper es
suficientemente simple/repetitivo como para que fusión/optimización de
grafo no cambien mucho el resultado final.

## Recomendación

No tocar ninguna de estas variables para el caso de uso del proyecto (1
stream local, tiempo real). Quedan documentadas como "probadas, sin
efecto" para no re-investigarlas en el futuro sin una razón nueva (ej. un
modelo mucho más grande, un grafo con más nodos donde graph-optimize/fusion
sí tengan margen para importar).

## Variables no probadas (fuera de alcance de este análisis)

- `GGML_VK_PREFER_HOST_MEMORY` / `GGML_VK_ALLOW_SYSMEM_FALLBACK` /
  `GGML_VK_SUBALLOCATION_BLOCK_SIZE` / `GGML_VK_FORCE_MAX_ALLOCATION_SIZE` /
  `GGML_VK_FORCE_MAX_BUFFER_SIZE`: relacionadas a estrategia de alocación
  de memoria, más relevantes en escenarios de memoria ajustada que en este
  caso de uso.
- `GGML_VK_DISABLE_COOPMAT` / `_COOPMAT2` / `_INTEGER_DOT_PRODUCT` /
  `_BFLOAT16` / `_DOT2` / `_OCP_FP4`: desactivan características de
  hardware ya confirmadas activas y beneficiosas (`igpu-research.md`) — no
  tiene sentido desactivarlas a propósito.
- `GGML_VK_SERIALIZE_SUBMISSIONS` / `GGML_VK_DISABLE_ASYNC`: por diseño
  deberían degradar el paralelismo; no se probaron por ser claramente
  contraproducentes para este caso de uso.
- `GGML_VK_MAX_NODES_PER_SUBMIT` / `GGML_VK_VISIBLE_DEVICES`: no aplican
  con un solo dispositivo/grafo chico como el de whisper.
