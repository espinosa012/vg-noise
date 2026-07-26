## 1. Estructura del proyecto y headers

- [x] 1.1 Crear `cpp/` con subcarpetas: `include/vnoise/` (headers públicos) y `src/` (implementación).
- [x] 1.2 Escribir `cpp/include/vnoise/vnoise.h` con la macro `VNOISE_API`, la definición de `noise_state_t`, constantes `BASE_*`, y todas las declaraciones de funciones públicas (init, evaluación por punto, fractales, fill_grid, fill_imagedata).
- [x] 1.3 Verificar que el header compila standalone con un TU C (`extern "C"` guard).

## 2. Núcleo de ruido: hash y estado

- [x] 2.1 Implementar `cpp/src/hash.cpp` con splitmix64 + xorshift32 seedable.
- [x] 2.2 Implementar `noise_init` en `cpp/src/state.cpp`: Fisher-Yates sobre `perm[0..255]` usando el PRNG, duplicar a `perm[256..511]`, guardar `seed`.
- [x] 2.3 Test manual: dos `noise_init` con misma semilla producen perm bit-idéntico.

## 3. Generadores base por punto

- [x] 3.1 Implementar `cpp/src/perlin.cpp` con `perlin2_eval`, `perlin3_eval` (improved gradient, interpolación fade f=6t^5-15t^4+10t^3).
- [x] 3.2 Implementar `cpp/src/simplex.cpp` con OpenSimplex2S (`simplex2_eval`, `simplex3_eval`) usando `perm[]` y la constante `ROTCONST2`/`ROTCONST3` de K.jpg.
- [x] 3.3 Implementar `cpp/src/white.cpp` con `white2_eval`, `white3_eval` (hash entero → float en [-1,1]).
- [x] 3.4 Verificar rangos `[-1, 1]` (con margen) sobre grilla regular de muestras para cada generador.

## 4. Samplers fractales por punto

- [x] 4.1 Implementar `cpp/src/fbm.cpp` con `fbm2_eval`, `fbm3_eval` (dispatch por `base`, suma de octavas con `lac`/`gain`).
- [x] 4.2 Implementar `cpp/src/fractal.cpp` con `ridge2_eval`, `ridge3_eval`, `turb2_eval`, `turb3_eval` reutilizando el dispatcher de octavas de fBm.
- [x] 4.3 Verificar que `base` inválido devuelve `0.0f` sin excepción.
- [x] 4.4 Verificar que fBm 1-octava con `BASE_PERLIN2` equivale a `perlin2_eval`.

## 5. Batch `fill_grid` y `fill_imagedata`

- [x] 5.1 Implementar `cpp/src/fill_grid.cpp` con `fbm2_fill_grid`, `ridge2_fill_grid`, `turb2_fill_grid` (loop cerrado, `out` restrict).
- [x] 5.2 Implementar `fbm3_fill_volume`, `ridge3_fill_volume`, `turb3_fill_volume` (buffer `w*h*d`).
- [x] 5.3 Implementar `cpp/src/fill_imagedata.cpp` con `fbm2_fill_imagedata_rgba8` y equivalentes ridge/turb; mapeo `[lo,hi]→[0,1]` con clamping y escritura RGBA8 row-major.
- [x] 5.4 Verificar: salida batch coincide con evaluaciones por punto a las mismas coords.
- [x] 5.5 Verificar: clamping correcto para v=2.0 (satura a 255) y v=-2.0 (satura a 0).

## 6. Punto deentrada `api.cpp`

- [x] 6.1 Exportaciones `VNOISE_API` con `extern "C"` distribuidas por TU; confirmado ABI sin mangle (`nm -gU` muestra 22 símbolos C no-mangled, ningún símbolo C++ interno).

## 7. Makefile cross-platform

- [x] 7.1 Escribir `Makefile` raíz con detección `uname -s` (Darwin/Linux/MINGW→MSYS), extensión `.dylib`/`.so`/`.dll`, `CXXFLAGS=-O3 -ffast-math -fno-rtti -fno-exceptions -fPIC -fvisibility=hidden -Wall -std=c++17`.
- [x] 7.2 Añadir `-march=native` por defecto, desactivable con `make NATIVE=0`.
- [x] 7.3 Definir `VNOISE_LIBRARY` al compilar la lib para que `VNOISE_API` expanda a `dllexport` en Windows.
- [x] 7.4 Añadir targets `all`, `clean`, `test` (placeholder).
- [x] 7.5 Verificar build en macOS (darwin): se produce `libvnoise.dylib`.
- [x] 7.6 Verificar `nm -gU libvnoise.dylib` muestra solo símbolos C no-mangled relevantes.

## 8. Módulo Lua `vnoise.lua`

- [x] 8.1 Escribir `lua/vnoise.lua`: `ffi.cdef` con toda la API C, `ffi.load("vnoise")` (nombre sin extensión), tabla `vnoise` con `BASE_*` constantes.
- [x] 8.2 Implementar `vnoise.new(seed)` → crea `noise_state_t` FFI, retorna wrapper Lua con métodos.
- [x] 8.3 Implementar métodos del estado: `:perlin2/:perlin3/:simplex2/:simplex3/:white2/:white3`.
- [x] 8.4 Implementar métodos fractales con defaults `lac=2.0, gain=0.5`: `:fbm2/:fbm3/:ridge2/:ridge3/:turb2/:turb3`.
- [x] 8.5 Implementar `vnoise.fill_grid(state, kind, opts)` (y fill_volume para 3D) creando/aceptando buffer float.
- [x] 8.6 Implementar `vnoise.fill_imagedata(state, kind, img, opts)` usando `ffi.cast("unsigned char*", img:getPointer())`.

## 9. Ejemplo Love2D

- [x] 9.1 Crear `examples/love2d/conf.lua` con ventana 1024×768.
- [x] 9.2 Crear `examples/love2d/main.lua` que cargue `vnoise`, genere heightmap fBm con `fill_imagedata`, dibuje la textura.
- [x] 9.3 Añadir al ejemplo: generar mesh 3D básico a partir del heightmap (`love.graphics.newMesh`) y proyectar ortográficamente (proyección isométrica en los vértices).
- [x] 9.4 Verificar `love examples/love2d` corre sin error y muestra la textura.
- [x] 9.5 Verificar determinismo: dos ejecuciones con misma semilla producen la misma textura (pixel-comparable).

## 10. README mínimo

- [x] 10.1 Escribir `README.md` raíz con instrucciones: `make`, copiar lib + `vnoise.lua` al proyecto Love2D, setear `package.cpath`, llamar a `vnoise.new(seed)`.
- [x] 10.2 Documentar flags `NATIVE=0`, `CXX=...`, y limitaciones (no bit-identidad cross-platform, undefined con NULL).

## 11. Verificación final

- [x] 11.1 `make clean && make` desde cero funciona en macOS.
- [x] 11.2 `love examples/love2d` corre end-to-end.
- [x] 11.3 Revisar specs con `openspec validate add-noise-library`.
- [x] 11.4 Confirmar que todos los tasks listados se completaron marca en `tasks.md`.