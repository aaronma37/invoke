local ffi = require("ffi")

-- AUTO-PATH: Resolve MoonCrust library locations
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua"

-- Define the PointSample struct to match Zig exactly (AoS / Interleaved)
ffi.cdef[[
    typedef struct {
        float u, v;
        float x, y, z;
        float c1, c2, c3;
    } PointSample_t;
]]

local args = {}
for i = 1, #arg do
    local k, v = arg[i]:match("%-%-([^=]+)=(.*)")
    if k then args[k] = v end
end

if not args.definition or not args.output then
    print("Usage: luajit sampler.lua --definition=path/to/def.lua --output=path/to/output.pcb [--count=100000]")
    os.exit(1)
end

local count = tonumber(args.count) or 100000
print(string.format("--- Forge Sampler (AoS Mode): %s (%d points) ---", args.definition, count))

-- 1. Load the Definition
local def = dofile(args.definition)

-- 2. Allocate sample buffer
local samples = ffi.new("PointSample_t[?]", count)

-- 3. Sample
math.randomseed(os.time())
for i = 0, count - 1 do
    local u = math.random()
    local v = math.random()
    local z = {} -- Latents
    
    local x, y, z_pos, c1, c2, c3 = def.evaluate(u, v, z)
    
    samples[i].u = u
    samples[i].v = v
    samples[i].x = x
    samples[i].y = y
    samples[i].z = z_pos
    samples[i].c1 = c1 or 0
    samples[i].c2 = c2 or 0
    samples[i].c3 = c3 or 0
end

-- 4. Save to Binary (Interleaved AoS write)
local f = io.open(args.output, "wb")
if not f then error("Could not open output file: " .. args.output) end
f:write(ffi.string(samples, ffi.sizeof("PointSample_t") * count))
f:close()

print("Sampling Complete. AoS output saved to: " .. args.output)
