## Context

El proyecto `vg-noise` nace vacío. El usuario desarrolla un juego en
**Love2D** (queATEON LuaJIT) sobre macOS (Apple Silicon / x86_64) y quiere
generar terreno procedural y texturas ruidosas en tiempo real. LuaJIT expone
**FFI**, lo que permite llamar a una librería C compartida con overhead
prácticamente nulo y sin dependencias externas de binding (sin `sol2`, sin
Lua glue generado). La librería se escribe en C++17 (cabeceras + un par de
TUs) y se compila con `make` a `.dylib`/`.so`/`.dll`.

No hay specs previos, no hay API que preservar. Prioridad absoluta:
**eficiencia**, segunda: **simplicidad de uso desde Lua**.

## Goals / Non-Goals

**Goals:**

- API C `extern "C"` simple, sin RTTI ni excepciones, con estado opaco
  `noise_state_t` (perm table 512 ints + semilla).
- Generadores base en 2D y 3D: Perlin (improved gradient), OpenSimplex2S,
  White noise — deterministas por semilla.
- Samplers fractales por punto (fBm, Ridge, Turbulence) parametrizables.
- Batch `*_fill_grid(out, ox, oy, w, h, freq, oct, lac, gain)` que rellena
  un buffer `float*` en una sola llamada C (evita round-trip por pixel).
- `*_fill_imagedata(rgba8_ptr, w, h, ...)` que escribe directamente un
  puntero crudo RGBA8 (compatible con `love.image.ImageData`).
- Módulo Lua `vnoise.lua` con `ffi.cdef` + API ergonómica (constructores
  de estado, wrap de fill_grid, helpers para ImageData).
- Makefile cross-platform, `-O3 -ffast-math -march=native` por defecto.
- Ejemplo Love2D demostrando uso end-to-end.

**Non-Goals:**

- 4D (postergado a futuro; diseño deja hueco pero no se implementa).
- Worley/Voronoi, Cellular, Domain Warp como samplers aparte (fuera v1).
- Intrínsecos SIMD escritos a mano (se confía en autovectorización con
  `-O3 -ffast-math`; revisable con profiling sirecated).
- Binding para PUC-Lua 5.x (solo LuaJIT/FFI vía Love2D).
- Calidad bit-identica entre plataformas (ruido visual, no netcode).
- `double` en API pública (se usa `float`).
- CMake / Meson (solo Make).
- Distribución como paquete (`luarocks`, etc.) — el usuario enlazará
  manualmente copiando la librería y el `.lua`.

## Decisions

### D1. Binding: LuaJIT FFI en vez de Lua C API / `sol2`

FFI declara `extern "C"` directamente; cada llamada C es un `ffi.C.foo()`
con overhead ~ns. Alternativas requieren wrappers, tablas registry y
upvalues, todas más lentas y con dependencias.

- *Alternativa descartada*: `sol2` — header-only pero genera wrappers
  por función y añade dependencia heavy header.
- *Alternativa descartada*: Lua C API a mano — correcto pero verboso
  y más lento que FFI.

### D2. Estado: `noise_state_t` compartido, no por-generador

```c
typedef struct {
    uint32_t perm[512];   // tabla de permutación (Perlin-style)
    uint64_t seed;
} noise_state_t;
```

Una sola struct, una sola `noise_init(s, seed)`. Perlin, OpenSimplex2 y
White leen `perm[]` sin requerir estados separados. Desde Lua: el
usuario crea `ffi.new("noise_state_t")` y la pasa por puntero a todas
las funciones. Sin `userdata`/`__gc` — la lifetime la maneja Lua vía FFI.

- *Alternativa descartada*: una struct por tipo de noise — más código,
  más campos metatable, sin beneficio.
- *Alternativa descartada*: estado global singleton — impediría tener
  varios generadores simultáneos (e.g. terreno +_texturas con semillas
  distintas).

### D3. OpenSimplex2S (no Simplex clásico, no Perlin en su lugar)

Tomado de la obra de K.jpg (dominio público). Determinista, sin patentes
(patrón Simplex original expira 2021+ pero el temor persiste), mejor
calidad visual que Perlin, y más rápido en 3D. Se expone como
`simplex2_eval` / `simplex3_eval`.

- *Alternativa descartada*: Simplex clásico de Gustavson — calidad
  similar pero peor definición de dominio (más propenso a artefactos
  direccionales).
- *Alternativa descartada*: solo Perlin — sería más simple pero el
  usuario pidió simplex explícitamente.

### D4. `float` + `-ffast-math` + `-march=native` por defecto

- `float`: mitad de ancho de banda, doble vectorización potencial.
  Para coordenadas de terreno escaladas por una freq baja (≈0.001–
  0.01), `float` da precisión suficiente sin banding visible.
- `-ffast-math`: permite al compiler reordenar/eliminar FP ops. En
  ruido visual, diferencias bit-level no se perciben.
- `-march=native`: óptimo para el Mac de desarrollo. Se desactiva con
  `make NATIVE=0` para builds portables que se distribuyan a CPUs
  sin extensiones específicas.

- *Alternativa descartada*: `double` — innecesario para este uso.
- *Alternativa descartada*: intrínsecos AVX/NEON a mano — prematuro,
  saltos por plataforma, complejidad.

### D5. Batch `fill_grid` como primitive principal

```c
void fbm2_fill_grid(const noise_state_t* s, int base,
                    float* out, float ox, float oy,
                    int w, int h, float freq,
                    int octaves, float lac, float gain);
```

El caller Lua crea `ffi.new("float[?]", w*h)`, llama una vez, y usa el
buffer. Para terrenos de 1024×1024 elimina ~1M round-trips. La
implementación C++ hace el loop anidado y permite al compiler
autovectorizar el cuerpo.

### D6. `fill_imagedata` escribe RGBA8 directo

Love2D expone `ImageData:getPointer()` (vía `ffi.cast`), que devuelve un
`uint8_t*` al buffer RGBA8 crudo. La función C mapea
`v ∈ [lo, hi] → byte ∈ [0, 255]` y escribe 4 bytes por pixel (RGBA).
Una sola llamada rellena la textura entera, lista para subir a GPU.

```c
void fbm2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                               uint8_t* out, int w, int h,
                               float ox, float oy, float freq,
                               int octaves, float lac, float gain,
                               float lo, float hi,
                               uint8_t r, uint8_t g, uint8_t b, uint8_t a);
```

Colores fijos por llamada (r,g,b,a) para v1 — escalado de gradiente es
trivial post-hoc desde Lua. Alternativa (gradient LUT)queda fuera.

### D7. Hash seedable estilo splitmix64 para `perm[]`

`noise_init` rellena `perm[256]` con `0..255` y aplica un Fisher-Yates
shuffle usando un PRNG xorshift32 seeding-adopor `seed` (splitmix64 →
xorshift32). Luego duplica a `perm[256..511]` (patrón Perlin clásico).

- *Alternativa descartada*: `srand(seed)` — no portable, no determinista
  entre libc.
- *Alternativa descartada*: tabla hardcodeada — no permitiría semillas
  arbitrarias.

### D8. Makefile cross-platform con `uname`

```make
UNAME := $(shell uname -s)
ifeq ($(UNAME),Darwin)        EXT := dylib ; ...
else ifeq ($(UNAME),Linux)    EXT := so   ; ...
else                          EXT := dll   ; ...   # MinGW en Windows
endif
```

Sin CMake, sin dependencias. Detecta `clang++`/`g++` vía `CXX` env o
fallback. Targets: `all`, `clean`, `test` (opcional), `example`.

### D9. Sin RTTI ni excepciones

Se compila con `-fno-rtti -fno-exceptions`. La API C no lanza; errores
de parámetros (p.ej. `octaves <= 0`) se devuelven como salida
degenerada (output zeros / noop), no como excepciones. Mantener ABI
simple y reducir overhead de tablas EH.

## Risks / Trade-offs

- **[Auto-vectorización ineficiente]** → Mitigación: perfiles con
  `perf`/Instruments en `(fbm2_fill_grid)`. Si el cuerpo no vectoriza,
  reescribir ayudando al compiler (loop tiling, restrict pointers) o
  añadir intrínsecos en v2. *No intrínsecos en v1* — prematuro.
- **[-ffast-math produce NaN/Inf no detectados]** → Aceptado: entrada
  es coords finitas de usuario. Se documenta que NaN no está soportado.
- **[-march=native produce binaries no portables]** → Mitigación: flag
  `NATIVE=0` para builds distribuidos. Documentado en README del módulo.
- **[Violación de puntero en fill_imagedata si w*h no coincide]** →
  Mitigación: caller Lua responsable; se documenta. v1 sin validación
  para no penalizar performance.
- **[Apple Silicon vs x86_64 macs]** → `-march=native` cubre ambos.
  Makefile no asume arquitectura.
- **[Windows MinGW vs MSVC]** → Solo se garantiza MinGW (g++) donde
  `extern "C"` + `__declspec(dllexport)` se manejan con macro
  `VNOISE_API`. MSVC se deja como posibilidad no probada.
- **[LuaJIT FFI no libera `noise_state_t` automáticamente al recolectar
  userdata]** → FFI SÍ libera `ffi.new` structs por GC. Es `userdata` C
  externo pero LuaJIT lo gestiona. Verificado — no hay leak.

## Open Questions

- **¿Exponer `noise_state_t` por valor o solo por puntero?** Decidido:
  siempre por puntero (`const noise_state_t*` en evaluación, mut en init).
  Reduce copies y permite crecer la struct sin romper ABI.
- **¿Soporte para `ImageData` stride/pitch custom?** v1: asume row-major
  contiguo (lo que produce Love2D). Pitch custom se posterga.
- **¿Ejemplo demo en 2D-only o también 3D mesh?** v1: 2D heightmap
  visualizado como textura + un mesh 3D simple extraído del heightmap
  via `love.graphics.Mesh`.