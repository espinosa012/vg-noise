## ADDED Requirements

### Requirement: Escritura directa a `ImageData` RGBA8

La librería SHALL exponer
`void fbm2_fill_imagedata_rgba8(const noise_state_t*, int base, uint8_t* out, int w, int h, float ox, float oy, float freq, int octaves, float lac, float gain, float lo, float hi, uint8_t r, uint8_t g, uint8_t b, uint8_t a)`
y equivalentes para `ridge2` y `turb2`. La función evalúa el sampler
fractal, mapea `v ∈ [lo, hi]` a un factor `t ∈ [0, 1]` (clamping), y
escribe `(r,g,b,a) * t` por componente en `out` como RGBA8 row-major.
Variantes 3D zurdo buffer de volumen RGBA8 quedan fuera de v1.

#### Scenario: Mapeo de ruido a byte
- **WHEN** se llama fill_imagedata con `lo=-1, hi=1, r=255, g=255, b=255, a=255`
  y la salida del sampler en una celda es `0.0`
- **THEN** el pixel correspondiente en `out` es `(127, 127, 127, 255)`
  (factor t=0.5 aplicado)

#### Scenario: Clamping por fuera de rango
- **WHEN** el sampler produce `2.0` (fuera de `[-1, 1]`) y `lo=-1, hi=1`
- **THEN** el pixel se satura a `(255, 255, 255, 255)` (t=1.0)
- **WHEN** el sampler produce `-2.0`
- **THEN** el pixel se satura a `(0, 0, 0, 255)` (t=0.0)

#### Scenario: Rellena todos los píxeles
- **WHEN** se llama con `w=4, h=4`
- **THEN** se escriben 64 bytes (16 pixels × 4 componentes) en `out`

### Requirement: Sin validación de puntero nulo

Para preservar performance, las funciones `*_fill_imagedata*` MUST no
verificar `out == NULL`. Caller es responsable. Llamar con `out == NULL`
es undefined behavior.

#### Scenario: Documentación del contrato
- **WHEN** un caller Lua pasa `ffi.cast("uint8_t*", img:getPointer())`
  donde `img` es un `love.image.ImageData` válido de dimensiones `w×h`
- **THEN** la llamada tiene comportamiento definido y modifica los
  datos de la imagen en sitio

### Requirement: Origen y offset en coords (ox, oy)

`fill_imagedata` MUST aceptar `ox, oy` (origen) y `freq` (frecuencia)
tales que la celda `(i, j)` evalúa el sampler en
`(ox + i*freq, oy + j*freq)` (en 2D). El stride entre pixels es `freq`,
no 1.0 — para permitir muestreo a frecuencia arbitraria.

#### Scenario: Offset cero y freq unitaria
- **WHEN** se llama con `ox=0, oy=0, freq=1, w=2, h=2`
- **THEN** se muestrean los puntos `(0,0), (1,0), (0,1), (1,1)`

#### Scenario: Offset shiftea la ventana
- **WHEN** se llama con `ox=100, oy=100, freq=0.01, w=10, h=10`
- **THEN** se muestrean los puntos `(100+i*0.01, 100+j*0.01)` para
  `i,j in [0, 10)`