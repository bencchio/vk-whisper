# `--audio-ctx`: recorte del contexto de audio

Generado con `vk/bench/run.sh`. Mismo entorno que
[`beam-size.md`](beam-size.md) (base.en, jfk.wav 11.0s, Radeon 780M/RADV,
`-bs 1` en todas las pruebas).

## Qué hace

Por default, `n_audio_ctx = 1500` (cubre 30s de audio, sea cual sea la
duración real del clip). `--audio-ctx N` no solo recorta cuánto contexto
puede leer el decoder vía cross-attention: en el código (`whisper_build_-
graph_conv/encoder/cross`, `src/whisper.cpp:2008-2304`) ese mismo valor
dimensiona **los tres grafos de cómputo**, incluido el encoder. Es decir,
bajarlo reduce trabajo y memoria real del encoder, no solo del decoder — a
diferencia de `beam-size`, que solo afecta al decoder.

## Resultado: recorte agresivo (rompe el modelo)

| ac | encode (ms) | total (media, ms) | fallbacks | calidad |
|---:|------------:|--------------------:|:---------:|---------|
| 256 | 20.2 | **2718** | 1p/1h | texto truncado ("ask not.") |
| 384 | 27.4 | **7177** | 3p/1h | bucle de repetición |
| 512 | 67.0 | **5268** | 3p/0h | texto cortado |

**Advertencia importante**: recortar `audio-ctx` por debajo de cierto umbral
no degrada la calidad gradualmente — **rompe el modelo de forma
catastrófica**. El decoder empieza a repetir frases sin converger, lo que
dispara el mecanismo interno de fallback de whisper.cpp (reintentos con
temperatura distinta ante detección de repetición) y el tiempo total se
dispara **5-25x** respecto al caso normal — el peor resultado posible: más
lento *y* con peor calidad. No usar valores de `audio-ctx` sin validar
primero que no entren en este régimen.

## Resultado: zona segura (5 corridas c/u)

| ac | encode (media, ms) | total (media, ms) | fallbacks |
|---:|--------------------:|--------------------:|:---------:|
| 640 | 41.3 | **274.0** | 0 en las 5 |
| 704 | 47.0 | 277.4 | 0 en las 5 |
| 768 | 46.9 | **242.1** | 0 en las 5 |
| 1024 | 62.2 | 274.1 | 0 |
| 1500 (default) | 83.6 | 277.8 | 0 (referencia) |

`encode` sí baja de forma proporcional al recorte (83.6ms → ~41-47ms en la
zona segura, ~2x más rápido), confirmando que el ahorro de cómputo/memoria en
el encoder es real. Sin embargo, el **`total` no baja proporcionalmente**
con `-bs 1`: en este modo el tiempo está dominado por `decode` (~90ms fijos,
no afectado por `audio-ctx`) y `sample`, así que la ganancia de `encode` se
diluye en el total. Aun así, ninguna corrida en la zona segura mostró
fallbacks ni degradación de calidad.

## Dónde está el límite seguro

Con este audio de 11s, el límite de ruptura está entre `ac=512` (rompe) y
`ac=640` (estable) — no es un valor fijo, depende del contenido real del
audio (más denso en información = necesita más contexto). **No hay una
fórmula simple para calcularlo de antemano**; en producción conviene dejar
margen generoso sobre la duración real del audio en vez de ajustar al límite.

## Recomendación

- **No usar `audio-ctx` como optimización de velocidad para `beam-size=1`**:
  el ahorro en `encode` no se traduce en ganancia neta de `total` porque
  `decode` domina, y el riesgo de entrar en la zona de ruptura (fallbacks,
  5-25x más lento, peor calidad) es alto y difícil de predecir sin probar
  cada tipo de audio.
- **Sí puede tener sentido para reducir el tamaño de la representación en
  memoria en escenarios de streaming con chunks cortos y conocidos** (ej. si
  ya procesás en ventanas de 5-10s, fijar `audio-ctx` a un valor con margen
  sobre esa ventana, nunca al límite) — pero requiere validar por tipo de
  audio antes de desplegar, no es un default seguro para audio arbitrario.
- Si se busca reducir memoria/tiempo del encoder, es más seguro achicar el
  **modelo** (`tiny`/`base` en vez de `medium`/`large`) que jugar con
  `audio-ctx` cerca del límite.

## Pendiente

- Probar con audio más largo (30s+) donde el default de 1500 realmente se usa
  completo, para ver si ahí la ganancia de `encode` sí se refleja en `total`.
- Repetir con `beam-size` > 1, donde el cross-attention KV-cache (que sí
  escala con `beam-size`) podría hacer que el recorte de `audio-ctx` tenga
  más impacto relativo en `total`.
