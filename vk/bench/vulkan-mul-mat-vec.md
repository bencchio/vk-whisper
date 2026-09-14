# Por qué el salto de rendimiento bs=3 → bs=4 (hipótesis)

Contexto: en las mediciones de [`beam-size.md`](beam-size.md), `batchd`
escala suave de bs=1 a bs=3 pero pega un salto de +48% al pasar a bs=4
(128.6 → 195.2ms), mientras `encode`/`decode` no cambian. Esta nota
documenta la investigación de código sobre por qué.

Código relevante: `ggml/src/ggml-vulkan/ggml-vulkan.cpp:10178` y
`ggml/src/ggml-vulkan/vulkan-shaders/mul_mat_vec.comp:152`.

Cuando el número de columnas de salida (que en este contexto es el
`beam-size`) es `<= mul_mat_vec_max_cols` (8), ggml-vulkan usa un kernel
especializado `mul_mat_vec` en vez del `mul_mat` genérico — más eficiente
para batches chicos. Ese kernel **se compila en una variante distinta por
cada valor de `NUM_COLS`** (1 a 8), y cada invocación mantiene un array
`temp[NUM_COLS][NUM_ROWS]` **en registros por-thread (VGPRs)**, no en
memoria (`mul_mat_vec.comp:152`, con loops `[[unroll]]` sobre `NUM_COLS`).

## Hipótesis

(Respaldada por lectura de código, no confirmada con un profiler de GPU): la
cantidad de wavefronts que corren en paralelo por unidad de cómputo
(occupancy) está limitada por cuántos registros usa cada thread. Al crecer
`NUM_COLS` de 3 a 4, el uso de VGPRs por thread probablemente cruza un
umbral que la GPU (RDNA3 / Radeon 780M vía RADV) ya no puede acomodar con la
misma occupancy que tenía con 1-3 columnas — un "cliff" de rendimiento
característico de GPU, no una degradación gradual. Esto es consistente con
el patrón medido: bs=1→2→3 escala suave, bs=3→4 salta +48% en `batchd`
mientras `encode`/`decode` no cambian.

## Cómo confirmarlo (pendiente)

Haría falta inspeccionar el uso real de VGPRs por variante compilada, por
ejemplo con `RGP` de AMD o con `spirv-cross`/disasm de cada shader
`mul_mat_vec` para NUM_COLS=3 vs NUM_COLS=4. Queda fuera del alcance de este
análisis por ahora.

## Si se confirma

La mitigación no sería un flag de build sino tocar el shader (ej. bajar
`unroll_count`, o dividir el trabajo en menos columnas por invocación cuando
`NUM_COLS>3`), lo cual es una modificación de más riesgo/esfuerzo que
requeriría su propio ciclo de prueba.
