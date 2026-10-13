## ADDED Requirements

### Requirement: Register-only exported signatures
Every function the library exports and the Lua binding declares SHALL take at most 8 integer or pointer arguments and at most 8 floating-point arguments, so that on arm64 and x86-64 SysV every argument is passed in a register. Functions that need more inputs SHALL take them through a pointer to a struct. The reason is that LuaJIT's JIT compiler can place stack-passed FFI arguments in the wrong stack slot on macOS arm64.

#### Scenario: Binding declarations
- **WHEN** the `cdef` declarations of `lua/vnoise.lua` are parsed
- **THEN** no function has more than 8 integer/pointer or 8 float parameters

#### Scenario: JIT-compiled calls
- **WHEN** `fill_domain`, a masked `fill_pipeline` and `fill_imagedata` (with and without ops) run a few hundred times with the JIT off and again with it on
- **THEN** the results are identical

### Requirement: Bounded octave counts
Every octave loop (fractal samplers in 2D and 3D, domain warp, cellular, damped and gullies) SHALL clamp its octave count to `VNOISE_MAX_OCTAVES` (32). Counts at or below the bound SHALL be unchanged.

#### Scenario: Huge count
- **WHEN** `fill_domain` runs with `octaves = 13282480`
- **THEN** it returns quickly and its output equals the output with `octaves = 32`
