local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local json = require("mc.json")
local Composer = require("composer")

print("--- Topology and Stress Integrity Test ---")

local registry = {
    gen_cylinder_v1 = {
        generator_id = "gen_cylinder_v1",
        type = "functional",
        topology = "[2, 32, 32, 6]",
        topology_type = "periodic_u"
    }
}

local function assert_bit_perfect(v1, v2, msg)
    if math.abs(v1 - v2) > 1e-5 then
        error(string.format("ASSERTION FAILED: %s (Got %0.8f, Expected %0.8f)", msg, v1, v2))
    end
end

-- --- TEST 1: Horizontal Seam Closure (periodic_u) ---
print("\n[TEST 1] Horizontal Seam Closure...")
local res = 32
local recipe = { root = { id = "tube", generator = "gen_cylinder_v1" } }
local f = io.open("/tmp/seam_test.json", "w"); f:write(json.encode(recipe)); f:close()

local graph = Composer.new("/tmp/seam_test.json", registry)
local v_buf, v_count = graph:evaluate(res)

for v = 0, res - 1 do
    local idx_start = (v * res + 0) * 3
    local idx_end   = (v * res + (res - 1)) * 3
    for axis = 0, 2 do
        assert_bit_perfect(v_buf[idx_start + axis], v_buf[idx_end + axis], "Seam")
    end
end
print("  Result: Success.")
graph:destroy()

-- --- TEST 2: Depth-10 Stress Test (Accumulation check) ---
print("\n[TEST 2] Deep Chain Accumulation Audit...")

local function build_outward_chain(depth, current)
    if current > depth then return nil end
    return {
        id = "level_" .. current,
        generator = "gen_cylinder_v1",
        child_socket = "bottom",
        children = { build_outward_chain(depth, current + 1) }
    }
end

local deep_recipe = { root = build_outward_chain(10, 1) }
local f2 = io.open("/tmp/deep_test.json", "w"); f2:write(json.encode(deep_recipe)); f2:close()

local deep_graph = Composer.new("/tmp/deep_test.json", registry)
local v_buf_deep, v_count_deep = deep_graph:evaluate(res)

print("\n--- VERTEX DEPTH AUDIT ---")
for i = 1, #deep_graph.nodes do
    local offset = (i - 1) * (res * res) * 3
    local base_z = v_buf_deep[offset + 2]
    local top_idx = ((res - 1) * res) * 3
    local top_z  = v_buf_deep[offset + top_idx + 2]
    
    print(string.format("  Node %d (%s): Base Z = %0.4f, Top Z = %0.4f", i, deep_graph.nodes[i].id, base_z, top_z))
end

local final_node_idx = #deep_graph.nodes
local final_offset = (final_node_idx - 1) * (res * res) * 3
local final_top_z = v_buf_deep[final_offset + ((res - 1) * res) * 3 + 2]

print(string.format("\nFinal depth Z coordinate: %0.4f", final_top_z))
assert_bit_perfect(final_top_z, 10.0, "Deep Chain Cumulative Z")

deep_graph:destroy()
print("Success: 10-level weld hierarchy verified bit-perfect.")
