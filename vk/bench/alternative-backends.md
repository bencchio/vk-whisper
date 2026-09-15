# Alternativas al backend actual (Vulkan) y al modelo actual (Whisper)

Investigación de si existe algo "más moderno" que reemplace lo que usamos
hoy — separado en dos preguntas distintas: el backend de cómputo (cómo se
ejecuta el modelo) y la arquitectura del modelo (qué se ejecuta).

## 1. Backend de cómputo: ¿ROCm/HIP en vez de Vulkan?

Dentro de `ggml`, la única alternativa vendor-específica real para AMD es
ROCm/HIP (`ggml-hip`). El resto no aplica a esta iGPU: OpenCL en `ggml`
hoy apunta a GPUs móviles Adreno, SYCL es de Intel, WebGPU es para
portabilidad no rendimiento, CANN es de Huawei.

**Bloqueador concreto en este hardware exacto**: issue abierto en
`ggml-org/llama.cpp`
([#20839](https://github.com/ggml-org/llama.cpp/issues/20839)) — `gfx1103`
(el Radeon 780M/Phoenix de esta máquina) **falta en la `TensileLibrary` de
`rocBLAS`**, causando que el backend HIP crashee al calentar el modelo en
builds recientes. Existen workarounds de la comunidad (librerías
reemplazadas a mano, ej.
[likelovewant/ROCmLibs-for-gfx1103-AMD780M-APU](https://github.com/likelovewant/ROCmLibs-for-gfx1103-AMD780M-APU)),
documentados casi exclusivamente para Windows.

Razón estructural adicional para no esperar mucho de ROCm aunque
funcionara: las APUs están limitadas por ancho de banda de memoria
compartida (UMA), no por cómputo puro — la ventaja típica de HIP sobre
Vulkan (menos overhead que un shader compilado genérico) se nota más en
GPUs discretas con VRAM dedicada de alto ancho de banda.

**Decisión**: no migrar a ROCm ahora. Revisar el issue #20839 en el
futuro — si `rocBLAS` agrega soporte oficial para `gfx1103`, ahí sí
valdría la pena un benchmark real ROCm vs. Vulkan en este chip.

## 2. Modelo: ¿algo más moderno que Whisper?

Investigado en el contexto del hallazgo de `streaming-latency.md`: el
encoder de Whisper siempre procesa una ventana fija de 30s, lo que impone
un piso de ~800-900ms de latencia que ninguna configuración de
`--step`/`--length` puede evitar — es una limitación **arquitectónica**,
no de configuración.

### NVIDIA Parakeet-TDT / Canary (arquitectura Transducer)

- **Arquitectura fundamentalmente distinta**: Token-and-Duration
  Transducer, streaming-nativo — procesa incrementalmente con lookahead
  de ~80-320ms en vez del chunking de ventana fija de Whisper. Ataca
  directamente la causa raíz del piso de latencia encontrado, no un
  síntoma.
- **Cobertura de idioma ya no es el dealbreaker histórico**: versiones
  actuales (`parakeet-tdt-0.6b-v3`, `canary-1b-v2`, dataset Granary)
  cubren 25 idiomas europeos incluyendo español — antes Parakeet era
  solo-inglés.
- **Compatible con el ecosistema que ya usamos**: existe
  [`parakeet.cpp`](https://github.com/mudler/parakeet.cpp), un runtime en
  `ggml` (el mismo motor de `whisper.cpp`) con backend Vulkan explícito,
  streaming "cache-aware" con detección de fin de frase, ~785
  estrellas/92 forks.
- **Rendimiento reportado**: Parakeet TDT hasta ~4x más rápido que
  Whisper en CPU en benchmarks de terceros (no verificado en este
  hardware).

### Por qué no se migra ahora (sin descartarlo)

Cambiar de modelo/arquitectura no es cambiar una flag — es cambiar de
codebase completa:

- Todo el trabajo de esta sesión (beam-size, LTO, variables Vulkan,
  perfil de shaders, la reorganización de `vk/orig/`) es específico de
  `whisper.cpp`/Whisper — no se transfiere directamente.
- Habría que rehacer la validación de calidad con audio real en español +
  jerga técnica desde cero (ver `models-comparison.md`) — sin garantía de
  igualar la exactitud ya conseguida con `large-v3-turbo-q8_0`.
- Proyecto comunitario (785 estrellas) mucho más joven que `whisper.cpp` —
  menos terreno probado en Vulkan/RDNA3 específicamente.

**Decisión**: no migrar todavía. Queda como candidato serio para una
prueba exploratoria futura (compilar `parakeet.cpp`, correr el mismo
texto de `vk/bench/texts/streaming-latency.txt`, medir latencia real y
calidad) antes de considerar una migración completa — no es una tarea
para hacer a la ligera dado el esfuerzo ya invertido en el stack actual.
