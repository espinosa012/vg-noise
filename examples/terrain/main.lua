-- Terrain plan preview: a continent with mountain belts, eroded, with rivers
-- and lakes, rendered with hillshading. Run from the repository root after
-- `make`: love examples/terrain
--   R      new seed            1/2/3  view: terrain / flow / channel distance
--   M      toggle meanders     E      toggle erosion
package.path = package.path .. ";../../lua/?.lua;./lua/?.lua"

local vnoise = require("vnoise")

local WORLD = 1024 -- extent in cells
local MACRO = 8 -- macro node spacing
local SEA = 0.3
local BLOCK = 128

local seed = 7
local view = 1
local meanders = true
local erosion = true
local image, info

local function buildPlan(state)
  local belts = vnoise.presets.mountain_belts({ seed = seed + 2, freq = 1 / 90, belt_freq = 1 / 380 })
  return vnoise.terrain_plan(state, {
    width = WORLD,
    height = WORLD,
    macro_cell = MACRO,
    sea_level = SEA,
    elevation = {
      "add",
      vnoise.presets.continent({ width = WORLD, height = WORLD, seed = seed + 1 }),
      belts,
      weights = { 0.75, 0.35 },
      ops = { { "clamp", 0, 1 } },
    },
    uplift = belts,
    erosion = { iterations = erosion and 100 or 0 },
    rivers = { min_flow = 24, width = 1.5, max_width = 8, meander_amp = meanders and 4 or 0, valley_min = 6 },
    detail = { source = { "damped", freq = 1 / 40, octaves = 5, damping = 2 }, amplitude = 0.02 },
  })
end

-- Hypsometric tint of a land height t in 0..1.
local function landColor(t)
  if t < 0.35 then
    return 0.27 + 0.47 * t, 0.51 + 0.39 * t, 0.24 + 0.16 * t
  elseif t < 0.7 then
    return 0.55 + 0.24 * (t - 0.35), 0.55 - 0.16 * (t - 0.35), 0.31
  end
  return 0.59 + 0.98 * (t - 0.7), 0.55 + 1.18 * (t - 0.7), 0.51 + 1.49 * (t - 0.7)
end

local function render()
  local state = vnoise.new(seed)
  local t0 = love.timer.getTime()
  local plan = buildPlan(state)
  local build_ms = (love.timer.getTime() - t0) * 1000
  t0 = love.timer.getTime()
  local data = love.image.newImageData(WORLD, WORLD)
  local outputs = { "elevation", "river", "lake", "flow", "channel_distance" }
  local B2 = BLOCK + 2
  for by = 0, WORLD - 1, BLOCK do
    for bx = 0, WORLD - 1, BLOCK do
      -- One extra cell on each side for the hillshade gradient.
      local res = vnoise.fill_terrain(state, plan, { c0 = bx - 1, r0 = by - 1, w = B2, h = B2, outputs = outputs })
      local e = res.elevation
      for j = 1, BLOCK do
        for i = 1, BLOCK do
          local k = j * B2 + i
          local r, g, b
          if view == 2 then
            local f = res.flow[k]
            r, g, b = f * f, f, 0.3 + 0.7 * f
          elseif view == 3 then
            local d = res.channel_distance[k]
            r, g, b = d, d, d
          else
            local h = e[k]
            if h < SEA then
              local t = h / SEA
              r, g, b = 0.08 + 0.12 * t, 0.2 + 0.27 * t, 0.43 + 0.35 * t
            else
              local shade = 0.85 + ((e[k - 1] - e[k + 1]) + (e[k + B2] - e[k - B2])) * 25
              shade = math.max(0.3, math.min(1.2, shade))
              r, g, b = landColor((h - SEA) / (1 - SEA))
              r, g, b = r * shade, g * shade, b * shade
            end
            local water = math.max(res.river[k], res.lake[k])
            r, g, b = r + (0.16 - r) * water, g + (0.4 - g) * water, b + (0.86 - b) * water
          end
          data:setPixel(bx + i - 1, by + j - 1, math.min(r, 1), math.min(g, 1), math.min(b, 1), 1)
        end
      end
    end
  end
  image = love.graphics.newImage(data)
  info = ("seed %d  %d x %d cells, macro %d  plan %.0f ms, fill+color %.0f ms  %d rivers  erosion %s  meanders %s"):format(
    seed,
    WORLD,
    WORLD,
    MACRO,
    build_ms,
    (love.timer.getTime() - t0) * 1000,
    #plan:rivers(),
    erosion and "on" or "off",
    meanders and "on" or "off"
  )
  print(info)
end

function love.load()
  render()
end

function love.keypressed(key)
  if key == "r" then
    seed = seed + 1
  elseif key == "1" or key == "2" or key == "3" then
    view = tonumber(key)
  elseif key == "m" then
    meanders = not meanders
  elseif key == "e" then
    erosion = not erosion
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
  local scale = math.min(w, h - 24) / WORLD
  love.graphics.clear(0.08, 0.08, 0.1)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(image, (w - WORLD * scale) / 2, 24, 0, scale, scale)
  love.graphics.print(info .. "   [R] seed [1-3] view [E] erosion [M] meanders", 8, 4)
end
