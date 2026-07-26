## ADDED Requirements

### Requirement: Estado de ruido seedable y determinista

La librería SHALL exponer un tipo opaco `noise_state_t` y una función
`void noise_init(noise_state_t* s, uint64_t seed)` que rellena el estado
de forma determinista a partir de la semilla. Ejecutar `noise_init` dos
veces con la misma semilla MUST producir estados bit-idénticos dentro
del mismo build.

#### Scenario: Misma semilla produce mismo estado
- **WHEN** se llama `noise_init(s, 42)` dos veces sobre estados distintos
- **THEN** los campos internos (`perm[]`, `seed`) son bit-idénticos

#### Scenario: Distinta semilla produce estado distinto
- **WHEN** se llama `noise_init(s, 42)` y `noise_init(s2, 43)`
- **THEN** al menos uno de los 256 primeros elementos de `perm[]`
  difiere entre `s` y `s2`

#### Scenario: Salida determinista para misma semilla y coords
- **WHEN** se evalúa `perlin2_eval(s, 1.5, 2.5)` con dos estados
  inicializados con la misma semilla
- **THEN** los dos resultados son bit-idénticos

### Requirement: Perlin noise 2D y 3D

La librería SHALL exponer `float perlin2_eval(const noise_state_t*, float x, float y)` y
`float perlin3_eval(const noise_state_t*, float x, float y, float z)`
implementando Perlin improved-gradient. La salida MUST estar en el
rango aproximado `[-1, 1]` (se acepta desbordamiento marginal por -ffast-math).

#### Scenario: Salida en rango válido
- **WHEN** se evalúa Perlin 2D sobre una grilla regular de muestras
  en `[-10, 10] × [-10, 10]`
- **THEN** todos los valores están en `[-1.1, 1.1]`

#### Scenario: Periodo entero cero
- **WHEN** se evalúa `perlin2_eval(s, 5.0, 5.0)` y `perlin2_eval(s, 6.0, 5.0)`
- **THEN** los valores son distintos (no degenera en enteros)

### Requirement: OpenSimplex2S 2D y 3D

La librería SHALL exponer `float simplex2_eval(const noise_state_t*, float x, float y)`
y `float simplex3_eval(const noise_state_t*, float x, float y, float z)`
implementando la variante OpenSimplex2S (K.jpg). La salida MUST estar
en el rango aproximado `[-1, 1]`.

#### Scenario: Salida en rango válido
- **WHEN** se evalúa OpenSimplex2 3D sobre muestras dispersas
- **THEN** todos los valores están en `[-1.1, 1.1]`

#### Scenario: Distribución isotrópica
- **WHEN** se evalúa OpenSimplex2 2D sobre un círculo de radio 100
- **THEN** la varianza radial no presenta picos direccionales
  evidentes (no hay artefactos de ejes)

### Requirement: White noise 2D y 3D

La librería SHALL exponer `float white2_eval(const noise_state_t*, int ix, int iy)`
y `float white3_eval(const noise_state_t*, int ix, int iy, int iz)` que
devuelven un ruido independiente por celda entera, mapeado a `[-1, 1]`.
No interpolan. La salida MUST ser determinista por (estado, coords).

#### Scenario: Coords enteras distintas → valores distintos
- **WHEN** se evalúa `white2_eval(s, 0, 0)`, `white2_eval(s, 1, 0)`,
  `white2_eval(s, 0, 1)`
- **THEN** al menos 2 de los 3 valores difieren

#### Scenario: Misma celda → mismo valor
- **WHEN** se evalúa `white2_eval(s, 7, 3)` dos veces
- **THEN** los dos valores son bit-idénticos

### Requirement: API C `extern "C"` sin excepciones ni RTTI

Todas las funciones públicas MUST declararse `extern "C"` y la librería
MUST compilarse con `-fno-rtti -fno-exceptions`. Ninguna función pública
SHALL lanzar excepciones ni propagarlas a través del boundary C.

#### Scenario: Llamada desde C puro funciona
- **WHEN** un TU C (no C++) incluye solo las declaraciones `extern "C"`
  y enlaza contra `libvnoise`
- **THEN** el binario compila, enlaza y ejecuta correctamente

#### Scenario: Sin símbolos C++ exportados
- **WHEN** se inspecciona la tabla de símbolos exportados con `nm`
- **THEN** solo aparecen símbolos C no-mangled (más los del runtime C++
  estándar necesarios, sin tipos RTTI de la librería)

### Requirement: Precisión `float` en toda la API pública

Todas las funciones de evaluación pública SHALL aceptar y devolver
`float` (32-bit). El estado interno (`perm[]`, `seed`) MAY usar enteros
sin signo. No se expone ninguna variante `double` en v1.

#### Scenario: Coords con precisión suficiente para terrenos a freq baja
- **WHEN** se llama `fbm2_eval(s, base, 1.0, 1.0, 6, 2.0, 0.5)` con
  multiplicadores de freq en `[1e-3, 1e-2]`
- **THEN** no se observa banding visible en el heightmap resultante