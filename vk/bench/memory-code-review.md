# Revisión de código: memoria y transferencias

Análisis de `src/whisper.cpp` y `ggml/src/ggml-vulkan/ggml-vulkan.cpp`
buscando oportunidades de reducir consumo de memoria o transferencias, más
allá de cuantización y de los flags de build ya cubiertos en
`beam-size.md`/`lto.md`/`openmp.md`/`compiler.md`.

## 1. El buffer de cómputo del decoder se reserva para el peor caso, no para el uso real

`src/whisper.cpp:3608` — al inicializar el estado, el grafo del decoder se
construye con `n_tokens = hparams.n_text_ctx` (**448, constante fija e
idéntica en todos los tamaños de modelo**, con `worst_case=true`). Esto
explica que el "compute buffer (decode)" ronde 97-100MB tanto en `base`
como en `large-v3` — no escala con el modelo, escala con esa constante.

- Para modelos chicos: overhead proporcionalmente grande (~100MB sobre
  147MB de `base.en` = +68%).
- Para modelos grandes: insignificante (~100MB sobre 3GB de `large-v3` =
  ~3%).

No hay flag para reducir esto — es una reserva fija al cargar el modelo,
independiente de `--max-tokens` o `beam-size` reales.

## 2. El KV-cache del decoder se sobre-asigna explícitamente cuando `beam-size > 1`

`src/whisper.cpp:7267`, al recrear el KV-cache para acomodar más
"decoders" (beams):

```cpp
const int factor = n_decoders_cur > 1 ? n_decoders_cur + 2 : 1;
```

con el comentario *"overallocate to workaround KV cache fragmentation
issues"*. Con `beam-size=5` reserva espacio para **7** decoders (5+2), no
5 — ~40% de memoria extra intencional, documentado como parche a
fragmentación, no una necesidad fundamental. Con `beam-size=1`, `factor=1`
(sin overhead) — cuantifica por qué `bs=1` ya era la opción más liviana en
memoria en `beam-size.md`.

## 3. El KV-cache se destruye y recrea en caliente si el `beam-size` cambia entre llamadas

Mismo bloque (`src/whisper.cpp:7261-7279`): si un mismo `whisper_state`
procesa primero con `beam-size=1` y después con `beam-size=5` (ej. un
server que atiende requests con distintos parámetros), dispara
`whisper_kv_cache_free()` + reinicialización completa del KV-cache — una
reasignación de memoria real en tiempo de ejecución, no solo un ajuste
lógico. Evitable fijando un `beam-size` consistente por instancia/estado.

## 4. Las transferencias Vulkan ya están bien optimizadas para hardware integrado

`ggml_vk_buffer_write_2d`/`ggml_vk_buffer_read_2d_async`
(`ggml-vulkan.cpp:8591-8710`) ya toman el camino rápido `memcpy` directo
cuando el buffer es `HostVisible|HostCoherent` (el caso de una iGPU con
UMA), evitando el staging buffer y el submit de comandos por completo. No
se encontró margen de mejora ahí.

## Aplicabilidad al caso de uso actual (1 stream local, tiempo real)

Con la configuración ya recomendada para este escenario (`beam-size=1`
fijo, sin servidor multi-request), **ninguno de los hallazgos 1-3 aporta
una reducción real** en modelos grandes:

| Hallazgo | ¿Aplica con bs=1 fijo, modelo grande? |
|---|---|
| 1. Buffer decode ~100MB fijo | No — ~3% del tamaño de `large-v3`, insignificante |
| 2. Sobre-asignación KV (factor N+2) | No — con bs=1, `factor=1`, cero overhead |
| 3. Recreación de KV-cache | No — solo ocurre si `beam-size` cambia entre llamadas; con bs=1 fijo se inicializa una sola vez |

**Conclusión**: para este caso de uso puntual, no hay ajuste de código a
nivel de estos buffers que dé una ganancia real de memoria en modelos
grandes. La palanca que sigue moviendo la aguja es la ya establecida en
`models-comparison.md`: **cuantización** (Q5/Q8 vs fp16, sin pérdida de
calidad medible) es lo que realmente reduce el footprint de un modelo
`large-v3-turbo`, no estos ajustes internos de buffers.

Los hallazgos 1-3 sí importan en otros escenarios no cubiertos por este
proyecto hoy: modelos chicos (hallazgo 1) o un server con `beam-size`
variable por request (hallazgos 2 y 3).
