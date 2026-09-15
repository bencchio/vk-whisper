# Decisión: mantener `ggml` vendorizado (no instalarlo por separado)

`whisper.cpp` usa `ggml` como motor de tensores/backends (Vulkan incluido)
— no tiene su propia implementación de matmuls/shaders. En este repo,
`ggml` vive vendorizado en `ggml/` y se agrega vía `add_subdirectory(ggml)`
en `CMakeLists.txt:165`. La opción `WHISPER_USE_SYSTEM_GGML` (upstream,
default `OFF`) permite usar un `ggml` instalado por separado vía
`find_package(ggml)` en su lugar.

## Estado actual vs. upstream

Nuestro `ggml` vendorizado quedó fijado en el sync `52a939a2` (2026-09-04),
el fork parte de `master` en `f133970b` (2026-09-14). Upstream ya
avanzó más allá de eso (`sync : ggml` en `1d549b3c`, 2026-09-14, con
`ggml : bump version to 0.24.0`). Revisado el diff de `ggml-vulkan/` entre
ambos syncs: nada resuelve la hipótesis abierta de
[`vulkan-mul-mat-vec.md`](vulkan-mul-mat-vec.md), pero hay 3 cambios
relevantes para revisar en un futuro sync:

- `vulkan: add command-buffer debug labels for GPU profilers` (llama/28101)
  — habilitaría confirmar esa hipótesis con RGP sin instrumentar nada
  nosotros mismos.
- `vulkan: fuse UNARY(GELU|SIGMOID|SILU|SOFTPLUS) + MUL` (llama/27220) —
  potencial ahorro de dispatch sobre los buckets `GELU`/`MUL` vistos en
  [`shader-profile.md`](shader-profile.md) (3.2% + 4.2% del tiempo de GPU).
- `vulkan: use CPU writes in ggml_backend_vk_cpy_tensor_async if the
  context is idle` (llama/28618) — a revisar si toca el área del hallazgo
  de copia de staging evitable de [`igpu-research.md`](igpu-research.md).

No es urgente: ninguno es un fix crítico ni bloquea el caso de uso actual.

## Por qué no instalar `ggml` por separado

`ggml` no es una librería con API/ABI estable pensada para consumo
externo — es el motor interno de `whisper.cpp`/`llama.cpp`, cambia seguido
de forma no compatible hacia atrás entre versiones. Por eso el propio
proyecto upstream hace `sync : ggml` periódicamente en vez de depender de
una versión instalada aparte: garantiza que el `ggml` vendorizado sea
exactamente el que `whisper.cpp` espera en cada punto.

Riesgos concretos de `WHISPER_USE_SYSTEM_GGML=ON`:

- Desalineación de versión entre lo que `whisper.cpp` espera y lo que hay
  instalado — las fallas serían sutiles (comportamiento incorrecto, no
  necesariamente error de compilación).
- No hay un paquete `libggml` estable y ampliamente distribuido en
  distros — ya vimos en `igpu-research.md` un caso real (paquete
  `whisper-cpp` de Arch) donde separar el backend Vulkan del binario
  causó justamente un problema de packaging.
- La única razón real para hacerlo sería compartir un build de `ggml`
  entre varios proyectos locales (ej. junto a `llama.cpp`) para no
  duplicar compilación — no aplica al caso de uso de este proyecto (un
  build propio y enfocado).

## Decisión

Mantener el vendoring actual (`add_subdirectory(ggml)`, default de este
repo). Sincronizar `ggml` desde upstream es una tarea futura de
mantenimiento normal, no algo urgente ni bloqueado por esta decisión.
