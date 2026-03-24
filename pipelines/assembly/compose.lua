local ffi = require("ffi")

-- AUTO-PATH: Resolve MoonCrust library locations
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local json = require("mc.json")
local mc = require("mc")
local Composer = require("composer")

-- CLI Arguments
local function get_args()
    local result = {}
    local raw = _ARGS or arg or {}
    for i = 0, 100 do
        local v = raw[i]
        if not v then break end
        local k, val = v:match("%-%-([^=]+)=(.*)")
        if k then result[k] = val end
    end
    return result
end

local args = get_args()

if not args.recipe then
    print("Usage: ./mooncrust pipelines/assembly/compose.lua --recipe=recipes/tree.json")
    os.exit(1)
end

-- Load Registry
local function load_registry()
    local registry = {}
    local registry_dir = "projects/manifold_composer/registry/entries"
    local p = io.popen("ls " .. registry_dir .. "/*.json")
    for file_path in p:lines() do
        local f = io.open(file_path, "r")
        if f then
            local entry = json.decode(f:read("*a"))
            f:close()
            registry[entry.generator_id] = entry
        end
    end
    p:close()
    return registry
end

local registry = load_registry()

-- 1. Build the Graph
local graph = Composer.new(args.recipe, registry)

-- 2. Evaluate the entire object
local res = 32
local v_buffer, vertex_count = graph:evaluate(res)

print("Assembly Engine Result:")
print("  Total Vertices Generated: " .. vertex_count)
print("  Memory Footprint: " .. (ffi.sizeof("float") * vertex_count * 3) / 1024 .. " KB")

-- 3. Validation sample
local last_z = v_buffer[(vertex_count - 1) * 3 + 2]
print(string.format("  Final Vertex Z-Coordinate: %0.3f", last_z))

graph:destroy()
print("Pipeline complete.")
