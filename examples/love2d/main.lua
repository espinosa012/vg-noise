package.cpath = package.cpath .. ";../../?.dylib;../../libvnoise.dylib;./?.dylib;./libvnoise.dylib"
package.path  = package.path  .. ";../../lua/?.lua;./lua/?.lua"

local vnoise = require("vnoise")
local ffi = require("ffi")

local SEED = 1337
local TEX_W, TEX_H = 256, 256
local state
local texture
local mesh
local meshImg

local function build_texture()
    local img = love.image.newImageData(TEX_W, TEX_H)
    vnoise.fill_imagedata(state, "fbm", img, {
        w = TEX_W, h = TEX_H, ox = 0, oy = 0, freq = 0.02,
        octaves = 6, lac = 2.0, gain = 0.5,
        base = vnoise.BASE_SIMPLEX2,
        lo = -1, hi = 1,
        r = 255, g = 255, b = 255, a = 255,
    })
    return love.graphics.newImage(img)
end

local MESH_N = 96
local function build_mesh()
    local buf = vnoise.fill_grid(state, "fbm", {
        w = MESH_N + 1, h = MESH_N + 1, ox = 0, oy = 0, freq = 0.03,
        octaves = 6, lac = 2.0, gain = 0.5,
        base = vnoise.BASE_SIMPLEX2,
    })
    local function vert(i, j)
        local h = (buf[j * (MESH_N + 1) + i] + 1) * 0.5
        local gx = (i - MESH_N * 0.5)
        local gz = (j - MESH_N * 0.5)
        local iso_x = (gx - gz)
        local iso_y = h * 70.0 - (gx + gz) * 0.5
        return { iso_x, iso_y, 0, 0, 0, h, h, h * 0.4 + 0.1, 1 }
    end
    local verts = {}
    for j = 0, MESH_N - 1 do
        for i = 0, MESH_N - 1 do
            local a = vert(i,     j)
            local b = vert(i + 1, j)
            local c = vert(i,     j + 1)
            local d = vert(i + 1, j + 1)
            verts[#verts + 1] = a
            verts[#verts + 1] = b
            verts[#verts + 1] = c
            verts[#verts + 1] = b
            verts[#verts + 1] = d
            verts[#verts + 1] = c
        end
    end
    local fmt = {
        { "VertexPosition", "float", 2 },
        { "VertexTextureCoords", "float", 2 },
        { "VertexColor", "float", 4 },
    }
    return love.graphics.newMesh(fmt, verts, "triangles")
end

function love.load()
    state = vnoise.new(SEED)
    texture = build_texture()
    mesh = build_mesh()
    love.graphics.setWireframe(false)
end

local rot = 0
function love.update(dt)
    rot = rot + dt * 0.3
end

function love.draw()
    love.graphics.clear(0.1, 0.12, 0.15, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(texture, 0, 0, 0, 1, 1)

    love.graphics.push("all")
    love.graphics.translate(TEX_W + 280, 480)
    love.graphics.rotate(rot * 0.3)
    love.graphics.scale(1.6, 1.6)
    love.graphics.draw(mesh, 0, 0, 0, 1, 1)
    love.graphics.pop("all")

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("seed=" .. SEED .. "  fbm 6 oct  simplex2  " .. TEX_W .. "x" .. TEX_H, 12, 12)
end