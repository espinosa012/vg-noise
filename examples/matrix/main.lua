-- Step-by-step matrix authoring: a base elevation, two mountain ranges, a
-- volcano and a crater, erosion and random rivers, each step shown on its own.
-- Run from the repository root after `make`: love examples/matrix
--   1-7  show the matrix after that step     R  new seed
package.path = package.path .. ";../../lua/?.lua;./lua/?.lua"

local vnoise = require("vnoise")

local N = 512
local SEA = 0.3
local seed = 3
local shown = 7
local snapshots, rivers_mask, info

local STEPS = { "base", "range 1", "range 2", "volcano", "crater", "erosion", "rivers" }

local function copy(m)
  local c = vnoise.matrix(N, N)
  for k = 0, N * N - 1 do
    c[k] = m[k]
  end
  return c
end

local function build()
  local state = vnoise.new(seed)
  local t0 = love.timer.getTime()
  local times = {}
  local m =
    vnoise.fill_source(state, vnoise.presets.continent({ width = N, height = N, seed = seed }), { w = N, h = N })
  snapshots = { copy(m) }
  local function step(fn)
    local t = love.timer.getTime()
    fn()
    times[#times + 1] = (love.timer.getTime() - t) * 1000
    snapshots[#snapshots + 1] = copy(m)
  end
  step(function()
    vnoise.path_feature(m, N, N, { 80, 330, 200, 220, 330, 250, 430, 150 }, {
      kind = "ridge",
      height = 0.35,
      width = 90,
      spurs = 14,
      roughness = 0.4,
      seed = seed,
    })
  end)
  step(function()
    vnoise.path_feature(m, N, N, { 150, 420, 260, 380, 380, 410 }, {
      kind = "ridge",
      height = 0.25,
      width = 60,
      spurs = 10,
      roughness = 0.4,
      seed = seed + 1,
    })
  end)
  step(function()
    vnoise.stamp(m, N, N, {
      shape = "cone",
      cx = 360,
      cy = 300,
      rx = 45,
      height = 0.35,
      crater = 0.18,
      roughness = 0.5,
      seed = seed,
      blend = "max",
    })
  end)
  step(function()
    vnoise.stamp(m, N, N, {
      shape = "crater",
      cx = 150,
      cy = 150,
      rx = 35,
      height = 0.15,
      rim = 0.3,
      floor = -0.6,
      roughness = 0.4,
      seed = seed,
    })
  end)
  step(function()
    vnoise.erode(m, N, N, { iterations = 60, sea_level = SEA })
  end)
  rivers_mask = vnoise.matrix(N, N)
  step(function()
    for _, src in ipairs(vnoise.river_sources(m, N, N, { count = 6, min_elev = 0.55, min_spacing = 80, seed = seed })) do
      vnoise.river(m, N, N, src[1], src[2], { sea_level = SEA }, rivers_mask)
    end
  end)
  info = ("seed %d  %dx%d  total %.0f ms  (steps: %s ms)"):format(
    seed,
    N,
    N,
    (love.timer.getTime() - t0) * 1000,
    table.concat(
      (function()
        local t = {}
        for i, v in ipairs(times) do
          t[i] = string.format("%.0f", v)
        end
        return t
      end)(),
      " / "
    )
  )
  print(info)
end

local image

local function render()
  local m = snapshots[shown]
  local data = love.image.newImageData(N, N)
  for j = 0, N - 1 do
    for i = 0, N - 1 do
      local k = j * N + i
      local h = m[k]
      local r, g, b
      if h < SEA then
        local t = h / SEA
        r, g, b = 0.08 + 0.12 * t, 0.2 + 0.27 * t, 0.43 + 0.35 * t
      else
        local e1 = m[j * N + math.min(i + 1, N - 1)] - m[j * N + math.max(i - 1, 0)]
        local e2 = m[math.min(j + 1, N - 1) * N + i] - m[math.max(j - 1, 0) * N + i]
        local shade = math.max(0.3, math.min(1.2, 0.85 + (-e1 + e2) * 12))
        local t = (h - SEA) / (1 - SEA)
        r, g, b = (0.3 + 0.5 * t) * shade, (0.55 - 0.1 * t) * shade, (0.25 + 0.3 * t) * shade
      end
      if shown == 7 and rivers_mask[k] > 0 then
        local w = rivers_mask[k]
        r, g, b = r + (0.16 - r) * w, g + (0.4 - g) * w, b + (0.86 - b) * w
      end
      data:setPixel(i, j, math.min(r, 1), math.min(g, 1), math.min(b, 1), 1)
    end
  end
  image = love.graphics.newImage(data)
end

function love.load()
  build()
  render()
end

function love.keypressed(key)
  local n = tonumber(key)
  if n and n >= 1 and n <= #STEPS then
    shown = n
  elseif key == "r" then
    seed = seed + 1
    build()
  elseif key == "escape" then
    love.event.quit()
    return
  else
    return
  end
  render()
end

function love.draw()
  local w, h = love.graphics.getDimensions()
  local scale = math.min(w, h - 24) / N
  love.graphics.clear(0.08, 0.08, 0.1)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(image, (w - N * scale) / 2, 24, 0, scale, scale)
  love.graphics.print(("step %d/%d: %s   %s   [1-7] step [R] seed"):format(shown, #STEPS, STEPS[shown], info), 8, 4)
end
