# Latencia percibida en `vk-whisper-stream`

Hasta acá todos los benchmarks midieron throughput sobre un archivo de
audio completo. Esta prueba mide lo que realmente importa para el caso de
uso del proyecto (1 stream local, tiempo real): **cuánto tarda en aparecer
el texto después de que la persona termina de hablar**, variando los
parámetros de la aplicación (`--step`, `--length`, VAD), no de la
librería.

Entorno: `large-v3-turbo-q8_0`, headset Bluetooth (perfil
`headset-head-unit`), Radeon 780M/RADV, voz real leyendo el mismo texto de
~24s en cada corrida:

> "Estamos probando el pipeline de streaming en tiempo real. La idea es
> medir la latencia entre que dejo de hablar y aparece el texto
> transcrito. Vamos a usar un modelo large cuantizado, corriendo sobre
> Vulkan en la iGPU. El objetivo es encontrar el balance correcto entre
> step size, contexto y velocidad de respuesta, sin gastar recursos de
> más."

## Resultado

| Configuración | Latencia a 1ª frase real | Calidad | encode (avg/run) |
|---|---:|---|---:|
| `--step 3000 --length 10000` (default) | ~6.6s | Buena, errores menores | ~801ms |
| `--step 1000 --length 10000` | ~9.8s | Degradada (repeticiones, incoherencias) | ~792-799ms |
| `--step 0` (VAD, default `length 10000`) | ~15.7s | Incompleta (cortó por timeout) | ~792ms |
| `--step 1000 --length 4000` | peor que default (misma alucinación inicial + errores) | Degradada | ~915ms |

## Hallazgo: el costo de `encode` es un piso fijo, no depende de `--length`

En las 4 configuraciones, el tiempo de `encode` por corrida se mantuvo
entre ~790-915ms **sin importar `--length`** (probado 10000ms y 4000ms).
Esto no es casualidad: el encoder de Whisper procesa **siempre una
ventana fija de 30 segundos** de mel-spectrogram (`n_audio_ctx = 1500`
frames = 30s, ver logs de `whisper_model_load`), rellenando con silencio
el resto si hay menos audio real. `--length` en `stream.cpp` solo controla
cuánto contexto recibe el *decoder* como prompt — no reduce el trabajo del
encoder.

Consecuencia directa: **no existe combinación de `--step`/`--length` que
baje el costo de encode por debajo de ese piso (~800-900ms) con este
modelo**. Es el mismo tipo de límite estructural que el hallazgo de la
proyección de vocabulario en [`shader-profile.md`](shader-profile.md) —
una característica de la arquitectura de Whisper, no algo ajustable por
configuración.

## Por qué `step` más chico empeoró todo

Con `step=1000`, el encode (~800ms) casi no entra en el presupuesto de
1000ms por ciclo. El pipeline se atrasa, y en vez de dar texto más rápido,
re-procesa ventanas desalineadas con el audio real — de ahí las
incoherencias ("el bulto en el eje P1", texto repetido). El modo VAD por
defecto es aún peor porque además necesita acumular una pausa de habla
detectada sobre una ventana de contexto igual de grande (`length=10000`
por defecto).

## Recomendación

**Mantener `--step 3000 --length 10000` (default del proyecto)** para el
caso de uso de este proyecto. Da margen suficiente sobre el piso de
~800ms de encode para no acumular atraso, y fue la única configuración
probada con calidad de transcripción aceptable.

Bajar la latencia por debajo de ~6.6s requeriría un modelo con encoder más
rápido (ver `models-comparison.md`: modelos más chicos son más rápidos
pero pierden exactitud en jerga técnica), no un ajuste de `--step`/
`--length` — ese margen ya está agotado.

## Pendiente

- No se pudo aislar el efecto de VAD sin el piso de `length=10000` (VAD
  con `--length` explícitamente más chico, si el flag lo permite) —
  quedaría por confirmar si VAD con una ventana más chica cambia la
  conclusión.
- Solo se probó con un locutor (voz propia) y un texto — no se validó
  sensibilidad a distintos ritmos de habla/pausas.
