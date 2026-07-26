## ADDED Requirements

### Requirement: fBm por punto 2D y 3D

La librería SHALL exponer `float fbm2_eval(const noise_state_t*, int base, float x, float y, int octaves, float lacunarity, float gain)` y
análoga `fbm3_eval`. El parámetro `base` selecciona el generador base
(`BASE_PERLIN2`, `BASE_SIMPLEX2`, `BASE_WHITE2` para 2D; equivalentes 3D).
`octaves` > 0; `lacunarity` típicamente 2.0; `gain` (persistence) en `(0, 1)`.

#### Scenario: Más octavas → más detalle
- **WHEN** se evalúa fBm 2D con `(octaves=1)` y con `(octaves=6)` en la
  misma coordenada
- **THEN** el resultado con 6 octavas tiene mayor varianza local
  (más detalle)

#### Scenario: Suma normalizada
- **WHEN** se evalúa fBm 2D con octavas altas (8) y gain 0.5
- **THEN** la salida queda en `[-1, 1]` (aprox.) porque la suma
  está normalizada por la serie geométrica de amplitudes

### Requirement: Ridge noise 2D y 3D

La librería SHALL exponer `float ridge2_eval(...)` y `ridge3_eval(...)`
con la misma firma que fBm. Ridge produce crestas (1 - |n|)² sumado en
octavas, útil para cordilleras.

#### Scenario: Crestas en cero del noise base
- **WHEN** se evalúa Ridge 2D sobre una región donde el noise base
  pasa por 0
- **THEN** la salida alcanza un máximo local en la cresta

### Requirement: Turbulence 2D y 3D

La librería SHALL exponer `float turb2_eval(...)` y `turb3_eval(...)`.
Turbulence Computes `|n|` por octava y suma (valor absoluto), generando
aspecto más azaroso/no-homogéneo que fBm.

#### Scenario: Salida no negativa
- **WHEN** se evalúa Turbulence 2D sobre una grilla de muestras
- **THEN** todas las salidas son `>= 0`

### Requirement: Batch `fill_grid` para fBm/Ridge/Turbulence

La librería SHALL exponer funciones batch que rellenan un buffer `float*`
de tamaño `w*h` en una sola llamada C, evitando round-trips por pixel:
`fbm2_fill_grid`, `ridge2_fill_grid`, `turb2_fill_grid`, y equivalentes 3D
(`*_fill_volume` con buffer `w*h*d`). El parámetro `out` MUST ser no nulo;
el comportamiento con `out == NULL` es undefined (no se valida para
preservar performance).

#### Scenario: Batch == suma de evaluaciones por punto
- **WHEN** se llama `fbm2_fill_grid(s, base, buf, 0, 0, 64, 64, 0.01, 6, 2.0, 0.5)`
  y se comparan los valores con llamadas individuales `fbm2_eval` a las
  mismas coords
- **THEN** los valores coinciden bit-identicos (o dentro de epsilon
  por orden de operaciones)

#### Scenario: Rellena el buffer completo
- **WHEN** se llama `fbm2_fill_grid` con `w=10, h=10`
- **THEN** los 100 elementos de `out` son escritos (al menos uno no
  zero en entrada típica)

### Requirement: Base noise seleccionable

Los samplers fractales MUST aceptar un `int base` que selecciona el
generador base. Se SHALL definir constantes C `BASE_PERLIN2`,
`BASE_PERLIN3`, `BASE_SIMPLEX2`, `BASE_SIMPLEX3`, `BASE_WHITE2`,
`BASE_WHITE3` con valores estables. Un base inválido MUST devolver 0
silenciosamente (sin excepción).

#### Scenario: Base inválido devuelve cero
- **WHEN** se llama `fbm2_eval(s, 999, 1.0, 1.0, 4, 2.0, 0.5)`
- **THEN** la salida es `0.0f`

#### Scenario: Mismo base produce mismo resultado que eval directa
- **WHEN** se llama `fbm2_eval(s, BASE_PERLIN2, x, y, 1, 2.0, 0.5)`
- **THEN** el resultado equivale a `perlin2_eval(s, x, y)` (1 octava,
  gain sin efecto)