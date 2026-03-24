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
    if v1 ~= v2 then
        error(string.format("ASSERTION FAILED: %s (Got %0.8f, Expected %0.8f, Diff %0.8f)", msg, v1, v2, math.abs(v1-v2)))
    end
end

-- --- TEST 1: Horizontal Seam Closure (periodic_u) ---
print("  Running Test 1: Horizontal Seam Closure...")
-- For a cylinder, the point at u=0.0 must exactly match u=1.0 for every v.
local res = 32
local recipe = {
    root = { id = "tube", generator = "gen_cylinder_v1" }
}
-- Write temp recipe
local f = io.open("/tmp/seam_test.json", "w")
f:write(json.encode(recipe))
f:close()

local graph = Composer.new("/tmp/seam_test.json", registry)
local v_buf, v_count = graph:evaluate(res)

for v = 0, res - 1 do
    local idx_start = (v * res + 0) * 3
    local idx_end   = (v * res + (res - 1)) * 3
    
    for axis = 0, 2 do
        local msg = string.format("Horizontal Seam axis %d at v_idx %d", axis, v)
        assert_bit_perfect(v_buf[idx_start + axis], v_buf[idx_end + axis], msg)
    end
end
print("    Success: 100% Bit-Perfect Seam Closure.")
graph:destroy()

-- --- TEST 2: Depth-10 Stress Test (Accumulation check) ---
print("  Running Test 2: Deep Chain Accumulation...")

local function build_deep_chain(depth)
    if depth == 0 then return nil end
    return {
        id = "node_" .. depth,
        generator = "gen_cylinder_v1",
        child_socket = "bottom",
        children = { build_deep_chain(depth - 1) }
    }
end

local deep_recipe = { root = build_deep_chain(10) }
local f2 = io.open("/tmp/deep_test.json", "w")
f2:write(json.encode(deep_recipe))
f2:close()

local deep_graph = Composer.new("/tmp/deep_test.json", registry)
local v_buf_deep, v_count_deep = deep_graph:evaluate(res)

print("    Deep graph evaluated: " .. v_count_deep .. " vertices across 10 levels.")

-- Sample the very last vertex of the 10th node
local last_node_offset = 9 * (res * res) * 3
local last_z = v_buf_deep[last_node_offset + (res*res - 1)*3 + 2]
print(string.format("    Final depth Z coordinate: %0.4f", last_z))

-- Z should be exactly 10.0 if every 1.0 height manifold welded perfectly
assert_bit_perfect(last_z, 10.0, "Deep Chain Cumulative Z")

deep_graph:destroy()
print("    Success: No error accumulation through 10-level weld hierarchy.")

print("\n--- ALL INTEGRITY TESTS PASSED ---")
