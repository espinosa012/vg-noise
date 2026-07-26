## Why

El juego (Love2D/LuaJIT) necesita generar terreno procedural y otras texturas
ruidosas en tiempo real. Lua puro no alcanza el throughput necesario para
rellenar heightmaps y campos de ruido de forma eficiente, y no existe todavía
ninguna librería de ruido enlazada al proyecto. Aprovechar C++ con auto-
vectorización y exponerlo vía FFI elimina el overhead del binding y permite
producir terrenos de gran tamaño a 60 FPS sin sacrificar la simplicidad de
uso desde Lua.

## What Changes

- Se añade una librería C++ **`libvnoise`** que expone una API C (`extern "C"`)
  con generación de ruido determinista por semilla.
- Se implementan los generadores base: **Perlin (improved gradient) 2D/3D**,
  **OpenSimplex2S 2D/3D** y **White noise 2D/3D**.
- Se añaden samplers fractales por punto: **fBm, Ridge, Turbulence**
  (2D y 3D), parametrizables (octavas, lacunarity, gain, base noise).
- Se añaden funciones **batch `*_fill_grid`** que rellenan un buffer `float*`
  en una sola llamada C, eliminando el round-trip Lua↔C por pixel.
- Se añaden funciones **`*_fill_imagedata`** que escriben directamente sobre
  un puntero crudo RGBA8 de Love2D `ImageData`, mapeando `[-1,1]` o `[0,1]`
  a bytes, para uso inmediato como textura.
- Se incluye un **Makefile** cross-platform (macOS `.dylib`, Linux `.so`,
  Windows `.dll`) con `-O3 -ffast-math -fno-rtti -fno-exceptions` y
  `-march=native` activado por defecto (desactivable con `make NATIVE=0`).
- Se incluye un **módulo Lua `vnoise.lua`** que declara los `ffi.cdef` y
  expone una API ergonómica sobre la librería cargada.
- Se incluye un **ejemplo Love2D** (`main.lua` + assets mínimos) que genera
  un terrain mesh/textura usando la librería para validar end-to-end.
- **BREAKING**: ninguno (proyecto nuevo, sin API previa).

## Capabilities

### New Capabilities

- `noise-core`: núcleo C++ de generación de ruido (estado seedable,
  Perlin/OpenSimplex2/White 2D y 3D) y su API C `extern "C"`.
- `noise-fractal`: samplers fractales (fBm, Ridge, Turbulence) sobre el
  núcleo de ruido, en variantes por punto y batch `fill_grid`.
- `noise-imagedata`: helpers de escritura directa a `ImageData` (RGBA8)
  de Love2D para producir texturas desde campos de ruido en una sola
  llamada C.
- `noise-build`: Makefile cross-platform que produce `libvnoise`
  (`.dylib`/`.so`/`.dll`) con flags de optimización y un target `clean`.
- `noise-lua-binding`: módulo `vnoise.lua` con declaraciones FFI y API
  ergonómica consumible desde Love2D, más ejemplo demostrativo.

### Modified Capabilities

(none — proyecto nuevo, no hay specs existentes)

## Impact

- **Nuevo código** en `cpp/` (headers + sources: hash, perlin, simplex,
  white, fbm, ridge, turb, imagedata, api.cpp).
- **Nuevo build** en `Makefile` raíz; no requiere CMake ni dependencias
  externas (solo un compilador C++17).
- **Nuevo módulo Lua** en `lua/vnoise.lua` y ejemplo en `examples/love2d/`.
- **Dependencias**: ninguna nueva (LuaJIT FFI ya viene con Love2D).
- **Plataformas**: desarrollo en macOS (darwin, Apple Silicon / x86_64),
  debe también compilar y correr en Linux y Windows (MinGW) sin cambios
  de código fuente.
- **Determinismo**: misma semilla → mismo resultado dentro de la misma
  build. No se garantiza bit-identidad entre plataformas/compiladores
  (aceptado: el ruido es visual, no se usa para netcode sincronizado).
- **Precisión**: `float` (32-bit) en toda la API pública.