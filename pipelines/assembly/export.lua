local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local Composer = require("composer")

local function get_args()
    local result = {}
    local raw = _ARGS or arg or {}
    for i = 0, 10 do
        local v = raw[i]
        if not v then break end
        local k, val = v:match("%-%-([^=]+)=(.*)")
        if k then result[k] = val end
    end
    return result
end

local args = get_args()
if not args.recipe or not args.output then
    print("Usage: ./mooncrust pipelines/assembly/export.lua --recipe=recipes/tree.json --output=my_tree.obj")
    os.exit(1)
end

local res = tonumber(args.res) or 32

-- 1. Build Graph
local registry = {}
local p = io.popen("ls projects/manifold_composer/registry/entries/*.json")
for path in p:lines() do
    local f = io.open(path, "r")
    if f then
        local entry = require("mc.json").decode(f:read("*a"))
        f:close()
        registry[entry.generator_id] = entry
    end
end
p:close()

local graph = Composer.new(args.recipe, registry)

-- --- HARDENED LOCAL-FIRST EXPORTER (WITH SANITY CHECK) ---
print("--- Universal Object Exporter (Hardened Isolation) ---")

local global_vertices = {}
local global_faces = {}
local vertex_offset = 0

local batch_size = res * res
local inputs = ffi.new("float[?]", batch_size * 2)
for v = 0, res - 1 do
    for u = 0, res - 1 do
        local idx = (v * res + u) * 2
        inputs[idx], inputs[idx + 1] = u / (res - 1), v / (res - 1)
    end
end

for i, node in ipairs(graph.nodes) do
    local acts = ffi.new("float*[?]", #node.topology)
    for l = 1, #node.topology do acts[l-1] = ffi.new("float[?]", batch_size * node.topology[l]) end
    local local_v_buf = ffi.new("float[?]", batch_size * 3)
    
    local lib = ffi.load("ext/libmanifold_ext.so")
    lib.manifold_forward_pinned(node.handle, inputs, acts, local_v_buf, batch_size)
    
    local m = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
    
    -- SANITY: Audit this node's vertices
    local origin_count = 0
    for b = 0, batch_size - 1 do
        local lx, ly, lz = local_v_buf[b*3], local_v_buf[b*3+1], local_v_buf[b*3+2]
        local wx = m[1]*lx + m[5]*ly + m[9]*lz  + m[13]
        local wy = m[2]*lx + m[6]*ly + m[10]*lz + m[14]
        local wz = m[3]*lx + m[7]*ly + m[11]*lz + m[15]
        
        if math.abs(wx) < 1e-6 and math.abs(wy) < 1e-6 and math.abs(wz) < 1e-6 then
            origin_count = origin_count + 1
        end
        table.insert(global_vertices, {wx, wy, wz})
    end
    
    print(string.format("  Node %d (%s): %d total vertices, %d at origin (Sanity check)", i, node.id, batch_size, origin_count))
    
    -- Face Gen
    local is_fork = node.generator == "gen_fork_v1"
    if is_fork then
        local half_res = math.floor(res / 2)
        for island = 0, 1 do
            local u_start = island * half_res
            for v = 0, res - 2 do
                for u = 0, half_res - 2 do
                    local g_u = u_start + u
                    local i1 = vertex_offset + (v * res + g_u) + 1
                    local i2 = vertex_offset + (v * res + (g_u + 1)) + 1
                    local i3 = vertex_offset + ((v + 1) * res + (g_u + 1)) + 1
                    local i4 = vertex_offset + ((v + 1) * res + g_u) + 1
                    table.insert(global_faces, {i1, i2, i3})
                    table.insert(global_faces, {i1, i3, i4})
                end
            end
        end
    else
        for v = 0, res - 2 do
            for u = 0, res - 1 do
                local next_u = (u + 1) % res
                local i1 = vertex_offset + (v * res + u) + 1
                local i2 = vertex_offset + (v * res + next_u) + 1
                local i3 = vertex_offset + ((v+1) * res + next_u) + 1
                local i4 = vertex_offset + ((v+1) * res + u) + 1
                table.insert(global_faces, {i1, i2, i3})
                table.insert(global_faces, {i1, i3, i4})
            end
        end
    end
    vertex_offset = vertex_offset + batch_size
end

local f = io.open(args.output, "w")
f:write("# Manifold Composer Seamless Mesh\n")
for _, v in ipairs(global_vertices) do f:write(string.format("v %f %f %f\n", v[1], v[2], v[3])) end
for _, face in ipairs(global_faces) do f:write(string.format("f %d %d %d\n", face[1], face[2], face[3])) end
f:close()

print("Export Successful.")
graph:destroy()
os.exit(0)
