## ADDED Requirements

### Requirement: Módulo Lua `vnoise.lua` con declaraciones FFI

El proyecto SHALL incluir `lua/vnoise.lua` que declara `ffi.cdef`
completo de la API C de `libvnoise` y expone una tabla `vnoise` con
constructores y wrappers ergonómicos. La carga de la librería MUST
usar `ffi.load` con nombre sin extensión, resuelto dinámicamente según
plataforma Love2D.

#### Scenario: require funciona
- **WHEN** se ejecuta `local vnoise = require("vnoise")` desde Love2D
  y `libvnoise.<EXT>` está en `package.cpath` o cwd
- **THEN** `vnoise` es una tabla no-nula con métodos para crear estado
  y evaluar ruido

### Requirement: Constructor `vnoise.new(seed)`

El módulo SHALL exponer `vnoise.new(seed)` que crea un
`ffi.new("noise_state_t")`, lo inicializa con `noise_init(s, seed)`,
y devuelve una userdata-FFI con métodos asociados (o un objeto Lua
que la envuelve). Soporta ser recolectado por GC de LuaJIT.

#### Scenario: Estado creado y usable
- **WHEN** `local s = vnoise.new(42); local v = s:perlin2(1.0, 2.0)`
- **THEN** `v` es un `float` en `[-1.1, 1.1]`

#### Scenario: Misma semilla en dos estados
- **WHEN** `local a = vnoise.new(42); local b = vnoise.new(42)`
- **THEN** `a:perlin2(1.5, 2.5) == b:perlin2(1.5, 2.5)` con `==` bit-exacto

### Requirement: Métodos convenience por generador

El objeto estado SHALL exponer métodos: `:perlin2(x,y)`, `:perlin3(x,y,z)`,
`:simplex2(x,y)`, `:simplex3(x,y,z)`, `:white2(ix,iy)`, `:white3(ix,iy,iz)`
`:fbm2(x,y,octaves,base)`, `:fbm3(...)`, `:ridge2(...)`, `:ridg3(...)`,
`:turb2(...)`, `:turb3(...)`. Parámetros como `lac` y `gain` DEFAULT
to 2.0 y 0.5 cuando se omiten.

#### Scenario: Default lac/gain
- **WHEN** se llama `s:fbm2(1, 1, 6)` (sin lac/gain)
- **THEN** se usa `lac=2.0, gain=0.5` y la salida es igual a
  `s:fbm2(1, 1, 6, 2.0, 0.5)`

#### Scenario: Constantes base expuestas
- **WHEN** se accede `vnoise.BASE_SIMPLEX2`
- **THEN** devuelve el mismo valor entero que `C.BASE_SIMPLEX2`

### Requirement: Helper `fill_grid` desde Lua

El módulo SHALL exponer `vnoise.fill_grid_fbm2(state, opts)` (y
equivalentes ridge/turb, 2D/3D) donde `opts` es una tabla con
`{w=, h=, ox=, oy=, freq=, octaves=, lac=, gain=, base=}`. La función
crea un `ffi.new("float[?]", w*h)` internamente (o acepta uno pasado),
llama a la función C batch, y devuelve el buffer float para uso del
caller (e.g. construir mesh).

#### Scenario: Devuelve buffer válido
- **WHEN** `local buf = vnoise.fill_grid_fbm2(s, {w=8, h=8, ox=0, oy=0, freq=0.1, octaves=4, base=vnoise.BASE_PERLIN2})`
- **THEN** `buf` es un `float*` FFI con 64 elementos escribibles

### Requirement: Helper `fill_imagedata` desde Lua

El módulo SHALL exponer `vnoise.fill_imagedata_fbm2(state, love_imagedata, opts)`
y equivalentes, donde `opts` adicionalmente incluye `lo=, hi=, r=, g=, b=, a=`.
La función obtiene el puntero crudo vía
`ffi.cast("uint8_t*", img:getPointer())`, llama a la C function, y
modifica la `ImageData` in situ (sin copia).

#### Scenario: Rellena una ImageData
- **WHEN** se crea `local img = love.image.newImageData(8, 8)` y se
  llama `vnoise.fill_imagedata_fbm2(s, img, {freq=0.1, octaves=4, lo=-1, hi=1, r=255, g=255, b=255, a=255})`
- **THEN** al leer img:getPixel(4, 4) los componentes están en `[0, 255]`

### Requirement: Ejemplo Love2D demostrativo

El proyecto SHALL incluir `examples/love2d/` con `main.lua` (y
`conf.lua` mínimo) que carga `libvnoise` + `vnoise.lua`, genera un
heightmap 1024×1024 con fBm, lo dibuja como textura (vía ImageData), y
también construye un mesh 3D básico a partir del heightmap para
visualizar con `love.graphics`. Debe correr con `love examples/love2d`
directamente.

#### Scenario: Corre sin error
- **WHEN** se ejecuta `love examples/love2d` en macOS con `libvnoise.dylib` accesible
- **THEN** abre una ventana y muestra la textura generada sin errores

#### Scenario: Mismos resultados entre runs con misma semilla
- **WHEN** se ejecuta el ejemplo dos veces seguidas con la misma semilla hardcodeada
- **THEN** las dos texturas generadas son visualmente idénticas (pixel-comparable en el mismo build)