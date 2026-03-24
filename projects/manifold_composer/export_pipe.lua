local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local Composer = require("composer")

print("--- Manifold Composer: Exporting Bit-Perfect Pipe ---")

-- 1. Setup Registry
local registry = {
    gen_cylinder_v1 = {
        generator_id = "gen_cylinder_v1",
        type = "functional",
        topology = "[2, 32, 32, 6]",
        topology_type = "periodic_u"
    }
}

-- 2. Build the Graph
local graph = Composer.new("recipes/simple_pipe.json", registry)

-- 3. Evaluate
local res = 32
local v_buf, total_points = graph:evaluate(res)

-- --- HARDENED VERTEX WELDING ---
print("  Welding Vertices (Precision Mode)...")
local unique_verts = {}
local welded_positions = {}
local index_map = {} 

for i = 0, total_points - 1 do
    local x, y, z = v_buf[i*3], v_buf[i*3+1], v_buf[i*3+2]
    -- Bit-accurate key (no rounding needed since math is now bit-perfect)
    local key = string.format("%0.8f,%0.8f,%0.8f", x, y, z)
    
    if not unique_verts[key] then
        table.insert(welded_positions, {x, y, z})
        unique_verts[key] = #welded_positions
    end
    index_map[i] = unique_verts[key]
end

print(string.format("  Welding Complete: Reduced %d vertices to %d", total_points, #welded_positions))

-- 4. Save to OBJ
local f = io.open("output.obj", "w")
if not f then error("Could not open output.obj") end

f:write("# Manifold Composer Assembled Pipe\n")
for _, p in ipairs(welded_positions) do
    f:write(string.format("v %f %f %f\n", p[1], p[2], p[3]))
end

-- Face Loops
local nodes_count = #graph.nodes
local points_per_node = res * res
for n = 0, nodes_count - 1 do
    local node_offset = n * points_per_node
    for v = 0, res - 2 do
        for u = 0, res - 1 do
            -- Periodic U wrap-around logic for indexing
            local next_u = (u + 1) % res
            
            -- Local Indices
            local i1 = node_offset + (v * res + u)
            local i2 = node_offset + (v * res + next_u)
            local i3 = node_offset + ((v + 1) * res + next_u)
            local i4 = node_offset + ((v + 1) * res + u)
            
            -- Welded Global Indices
            local v1, v2, v3, v4 = index_map[i1], index_map[i2], index_map[i3], index_map[i4]
            
            f:write(string.format("f %d %d %d\n", v1, v2, v3))
            f:write(string.format("f %d %d %d\n", v1, v3, v4))
        end
    end
end

f:close()
print("Successfully saved seamless pipe to output.obj")
graph:destroy()
os.exit(0)
