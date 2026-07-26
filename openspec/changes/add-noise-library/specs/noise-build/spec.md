## ADDED Requirements

### Requirement: Build cross-platform con Make

El proyecto MUST proveer un `Makefile` raíz que produzca la librería
compartida `libvnoise.<EXT>` donde `<EXT>` es `dylib` en macOS, `so`
en Linux y `dll` en Windows (MinGW). La detección de plataforma SHALL
basarse en `uname -s` y no requerir configuración manual.

#### Scenario: Build en macOS
- **WHEN** se ejecuta `make` en darwin
- **THEN** se produce `libvnoise.dylib` enlazable

#### Scenario: Build en Linux
- **WHEN** se ejecuta `make` en Linux
- **THEN** se produce `libvnoise.so` enlazable

#### Scenario: Build en Windows (MinGW)
- **WHEN** se ejecuta `make` en MinGW (`uname -s` empieza con `MINGW` o `MSYS`)
- **THEN** se produce `libvnoise.dll` con símbolos exportados (`__declspec(dllexport)` via macro `VNOISE_API`)

### Requirement: Flags de optimización por defecto

El build por defecto SHALL usar `-O3 -ffast-math -fno-rtti -fno-exceptions -fPIC -Wall`.
Además MUST activar `-march=native` por defecto.

#### Scenario: Build con NATIVE=1 (default)
- **WHEN** se ejecuta `make` sin variables extra
- **THEN** el comando de compilación incluye `-march=native`

#### Scenario: Build portable con NATIVE=0
- **WHEN** se ejecuta `make NATIVE=0`
- **THEN** el comando de compilación NO incluye `-march=native`
  (produce un binario portable a CPUs más antiguas / otras arquitecturas)

### Requirement: Target `clean`

El Makefile MUST proveer un target `clean` que elimine todos los
artefactos de build (`.o`, `.dylib`/`.so`/`.dll`).

#### Scenario: clean tras build
- **WHEN** se ejecuta `make && make clean`
- **THEN** no quedan archivos `.o` ni `libvnoise.*` en el directorio

### Requirement: Compilador C++17 sin dependencias externas

El build SHALL compilar con cualquier `clang++` o `g++` que soporte
C++17, sin requerir CMake, Meson, ni dependencias de terceros. `CXX`
MAY sobrescribirse por entorno.

#### Scenario: Compilador custom vía env
- **WHEN** se ejecuta `make CXX=clang++-15`
- **THEN** el build usa ese compilador y produce la librería

### Requirement: Macro `VNOISE_API` para exportación

El header público SHALL definir una macro `VNOISE_API` que expanda a
`__declspec(dllexport)` en Windows (cuando se compila la librería) y
a vacío en macOS/Linux. Las funciones públicas MUST estar prefijadas
con `VNOISE_API`.

#### Scenario: Símbolos visibles en macOS
- **WHEN** se inspecciona el `.dylib` con `nm -g`
- **THEN** las funciones públicas (`noise_init`, `perlin2_eval`, etc.)
  aparecen como símbolos no-definidos-exportados

#### Scenario: Símbolos exportados en Windows
- **WHEN** se compila en MinGW con `VNOISE_LIBRARY` definido (build de la lib)
- **THEN** las funciones públicas aparecen con `__declspec(dllexport)`
  y son visibles a `LoadLibrary`