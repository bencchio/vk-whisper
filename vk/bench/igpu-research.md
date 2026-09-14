# Investigación: técnicas modernas para acelerar iGPUs

Búsqueda de desarrollos recientes (drivers, extensiones Vulkan, PRs de
llama.cpp/ggml) aplicables a la Radeon 780M (RDNA3, UMA), más allá de los
flags de build y hallazgos de código ya cubiertos en el resto de
`vk/bench/`. Conclusión general: **la mayoría de lo "moderno" ya está
activo en este setup, o no aplica a hardware UMA/integrado**. Un solo
hallazgo nuevo real, de bajo impacto.

## Hallazgo nuevo: copia de staging evitable al cargar el modelo

`src/whisper.cpp:1932-1944` — el loader de pesos usa
`ggml_backend_buffer_is_host(tensor->buffer)` para decidir si puede leer
directo al tensor sin copia intermedia:

```cpp
if (ggml_backend_buffer_is_host(tensor->buffer)) {
    // for the CPU and Metal backend, we can read directly into the tensor
    loader->read(loader->context, tensor->data, ggml_nbytes(tensor));
    BYTESWAP_TENSOR(tensor);
} else {
    // read into a temporary buffer first, then copy to device memory
    read_buf.resize(ggml_nbytes(tensor));
    loader->read(loader->context, read_buf.data(), read_buf.size());
    ggml_backend_tensor_set(tensor, read_buf.data(), 0, ggml_nbytes(tensor));
}
```

`ggml_backend_buffer_is_host()` solo devuelve `true` para backends
CPU/Metal — **nunca para Vulkan**, aunque una iGPU con memoria
`HostVisible` (UMA) tenga la misma RAM física de por medio. Resultado:
cada tensor pasa por una copia extra innecesaria (disco → buffer temporal
→ memcpy → buffer Vulkan) que en UMA es un memcpy dentro de la misma RAM.

**Impacto**: bajo. Solo afecta el tiempo de **carga inicial** del modelo
(una vez al arrancar), no el loop de inferencia — del orden de decenas de
ms en modelos chicos hasta ~100-200ms en `large-v3`. Arreglarlo bien
requeriría una API genérica cross-backend (ej.
`ggml_backend_buffer_is_host_visible()`) para no acoplar `whisper.cpp` a
detalles internos de Vulkan — no es un cambio trivial de una línea.

## Técnicas investigadas que NO aportan nada en este caso

| Técnica | Resultado |
|---|---|
| `RADV_PERFTEST=nogttspill` / kernel `amdgpu.runpm=0` | Probado empíricamente (10 corridas vs. 5 baseline, `-bs 1`, `jfk.wav`): 274.69ms vs. 274.04ms — diferencia de +0.2%, dentro del ruido. Soluciona spillover VRAM↔GTT en GPUs discretas; no existe ese problema en UMA (VRAM y GTT son la misma memoria). |
| Fix de "mmap avoidance" para iGPU (PR llama.cpp #26081) | No aplica — `whisper.cpp` nunca usó `mmap` para cargar modelos (loader propio basado en `fread`, confirmado en código). El problema que soluciona ese PR (doble-mapeo de memoria) es específico del loader GGUF de llama.cpp. |
| Flash Attention con `KHR_cooperative_matrix` (kernel `flash_attn_cm1.comp`) | **Ya activo**: confirmado en código (`ggml-vulkan.cpp:3922-3928`) que el device cae en el path `FA_COOPMAT1` automáticamente al detectar `coopmat_support` + `subgroup_require_full_support`. Coincide con "matrix cores: KHR_coopmat" que ya vemos en el log de `whisper-cli`. |
| `coopmat2` (`VK_NV_cooperative_matrix2`) | Extensión exclusiva de NVIDIA — no existe en RDNA3/AMD. No hay nada que activar. |
| Paquete `ggml-vulkan` separado en distros (Arch) | Problema de packaging del binario oficial de Arch (el paquete `whisper-cpp` de pacman no trae el backend Vulkan por default). No aplica: compilamos desde fuente con el backend ya integrado en el mismo binario. |

## Conclusión

La configuración actual del proyecto (Vulkan + `KHR_coopmat` activo +
zero-copy UMA en transferencias, ya documentado en
`memory-code-review.md` hallazgo 4 + `beam-size=1` para tiempo real) ya
está en la frontera de lo que el ecosistema ggml/Vulkan ofrece hoy para
una iGPU AMD RDNA3. El único gap real encontrado es cosmético (tiempo de
carga del modelo, no de inferencia continua) y de bajo impacto práctico
para el caso de uso de este proyecto (1 stream local, tiempo real).

## Fuentes consultadas

- [RADV (Vulkan on AMD/Linux) Performance Debugging Guide — ggml-org/llama.cpp Discussion #23295](https://github.com/ggml-org/llama.cpp/discussions/23295)
- [AMD 780M Vulkan LLM Information (mmap avoidance, BIOS VRAM)](https://note.com/samehadaonsen/n/n59e1dc57b941?hl=en)
- [Flash Attention Reaches Older and Integrated GPUs](https://thegputrade.com/news/flash-attention-reaches-older-and-integrated-gpus-7utmawj9/)
- [Flash Attention and Optimizations — ggml-org/llama.cpp DeepWiki](https://deepwiki.com/ggml-org/llama.cpp/8.2-flash-attention-and-optimizations)
- [Whisper.cpp, GPU, Vulkan and Arch (packaging issue, no crime)](https://dev.to/hopsayer/whispercpp-vulkan-on-arch-a-detective-story-with-no-crime-3nl4)
