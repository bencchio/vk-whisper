# Comparación de modelos (multilingüe, español + jerga en inglés)

Generado con `whisper-cli -l es` sobre 6 audios reales (voz propia, headset
Bluetooth WH-CH520 en perfil `headset-head-unit`/mSBC — ver
`examples/vk-stream/bt_profile.h`), comparando 6 modelos multilingües.
Exactitud = `1 - distancia_de_edición(palabras) / palabras_originales`,
sobre las transcripciones recortando alucinaciones de silencio al final del
audio cuando corresponde.

Modelos `.en` quedaron fuera de esta comparación: son solo-inglés y con
audio en español alucinan por completo, sin importar la velocidad.

## Textos usados

| # | Tema | Registro |
|---|---|---|
| T1 | Software/ML/Vulkan | técnico general |
| T2 | Kubernetes/Node.js | jerga técnica de nicho (repetido 2 veces, ver nota) |
| T3 | Viaje (Argentina) | conversacional, sin jerga |
| T4 | Finanzas/trading | jerga técnica con préstamos comunes del inglés |
| T5 | Cardiología | jerga médica, nombres de fármacos |
| T6 | Reflexión personal | conversacional, tono espontáneo |

## Tabla consolidada

| Modelo | Memoria | T1 | T2\* | T3 | T4 | T5 | T6 | **Media** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| small-q8_0 | 528.8 MB | 80.0% | 78.6% | 84.9% | 87.9% | 90.0% | 93.2% | **85.8%** |
| medium-q8_0 | 1.24 GB | 82.9% | 84.7% | 90.7% | 91.9% | 92.3% | 91.8% | **89.1%** |
| large-v3-turbo-q5_0 | 856.3 MB | 82.9% | 77.6% | 91.9% | 93.5% | 95.4% | 95.9% | **89.5%** |
| large-v3-turbo-q8_0 | 1.16 GB | 82.9% | 84.7% | 91.9% | 92.7% | 95.4% | 95.9% | **90.6%** |
| large-v3-q5_0 | 1.66 GB | 84.8% | 84.7% | 90.1% | 92.7% | 94.6% | **97.9%** | **90.8%** |

Los fp16 (`large-v3`, `large-v3-turbo`) se probaron para confirmar que la
cuantización no cuesta calidad (ver hallazgo 1) y luego se borraron —
liberan ~4.1GB y no aportan nada sobre sus versiones quantizadas en las
pruebas hechas. `tiny*` nunca se descargó, quedó fuera desde el principio
por ser el modelo más chico y menos preciso de la familia.

\* T2 se corrió 2 veces: la primera dio 77.6-80.6% en todos los modelos por
igual (los 6 confundieron "memory limit" con "memory leak" — señal de
lectura ambigua, no de un problema de cada modelo). Se repitió con una
lectura más clara y la tabla usa ese segundo resultado, donde todos menos
`turbo-q5_0` subieron a 84.7%. `turbo-q5_0` es el único que se quedó en
77.6% **las dos veces** — la única debilidad que se sostuvo entre
repeticiones en las 6 pruebas hechas.

## Velocidad (factor sobre tiempo real, audios de 40-65s)

| Modelo | T1 | T2 | T3 | T4 |
|---|---:|---:|---:|---:|
| small-q8_0 | 14.9x | 14.9x | 10.4x | 13.2x |
| large-v3-turbo-q8_0 | 10.8x | 11.5x | 10.8x | 10.6x |
| large-v3-turbo-q5_0 | 10.6x | 11.4x | 10.4x | 10.2x |
| medium-q8_0 | 8.7x | 8.3x | 6.4x | 8.6x |
| large-v3-q5_0 | 6.1x | 6.1x | 4.8x | 6.1x |

Todos los modelos, incluso el más lento, transcriben muy por debajo del
tiempo real en esta iGPU — la elección entre ellos puede basarse
exclusivamente en calidad/memoria sin preocuparse por si "llegan a tiempo"
en un caso de uso en vivo.

## Hallazgos

1. **La cuantización Q5/Q8 no cuesta calidad perceptible** — en las 3
   variantes de `turbo` (fp16/q5_0/q8_0), la exactitud es prácticamente
   idéntica en 5 de 6 textos. No hay razón para usar un modelo fp16 en
   producción.
2. **No existe un patrón simple "jerga técnica = turbo pierde"**: `turbo`
   perdió claramente solo en T2 (Kubernetes/Node.js, la primera vez), pero
   ganó o empató en T4 (finanzas) y T5 (medicina), ambos también técnicos.
   La variable real parece ser qué tan específico/poco frecuente es el
   vocabulario dentro de su propio dominio, no "técnico vs. no técnico".
3. **`turbo-q5_0` tiene una sensibilidad puntual y reproducible a T2**
   (77.6% en 2 repeticiones) que sus hermanos fp16/q8_0 no muestran —
   preferir `turbo-q8_0` sobre `turbo-q5_0` (~300MB más, sin el riesgo).
4. **Modelos grandes manejan mejor vocabulario de dominio muy específico**
   (nombres de fármacos en T5): los 4 modelos grandes acertaron
   "aspirina"/"heparina" perfecto, `small`/`medium` los garabatearon por
   completo — la brecha más nítida de toda la serie.
5. **`small-q8_0` mejora mucho en habla conversacional simple** (T6: 93.2%,
   superando incluso a `medium-q8_0`) pero sigue siendo el peor en
   contenido técnico (T1/T2: 78.6-80.0%).
6. **Lección metodológica**: una diferencia chica en una sola corrida puede
   ser ruido de lectura/grabación, no una debilidad real del modelo —
   repetir antes de concluir (como en T2).

## Recomendación

- **Uso general / no se sabe el tipo de contenido**: `large-v3-turbo-q8_0`
  — empata o gana en la mayoría de los textos, es liviano (1.16GB) y
  rápido, sin la sensibilidad puntual de `turbo-q5_0`.
- **Jerga de dominio muy específico y poco frecuente** (nombres de
  fármacos, comandos/herramientas de nicho): `large-v3-q5_0` — la media
  más alta de la tabla y el mejor resultado individual (T6: 97.9%).
- **Evitar `large-v3-turbo-q5_0`** salvo que la memoria sea muy limitada;
  usar `turbo-q8_0` en su lugar.
- **Evitar `small`** salvo que la prioridad absoluta sea velocidad/memoria
  y el contenido sea conversacional simple, sin jerga.
- **Nunca usar variantes `.en`** con audio que pueda tener contenido no
  inglés.

## Nota sobre el micrófono

Grabado con un headset Bluetooth (WH-CH520, perfil `headset-head-unit`,
códec mSBC) — ver `examples/vk-stream/bt_profile.h` para el fix automático
de perfil. Es un límite de calidad de captura presente en las 6 pruebas por
igual; no debería cambiar el ranking relativo entre modelos, aunque con un
micrófono dedicado es esperable que la exactitud absoluta suba en general.

## Pendiente

- Modelos sin probar: `tiny*`, `base` multilingüe, `small`/`medium` fp16,
  familia `large-v1`/`large-v2`.
- Confirmar con más repeticiones si la sensibilidad de `turbo-q5_0` a T2 es
  específica de ese texto o aparece con otro contenido similar.
- Probar con micrófono no-Bluetooth para aislar el efecto de la captura.
