local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local json = require("mc.json")
local Composer = require("composer")

print("--- EXHAUSTIVE WELD DIAGNOSTIC ---")

-- 1. Setup minimal registry for test
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

-- 3. Evaluate Seam
local res = 16
local v_buf, total_points = graph:evaluate(res)
local node_points = res * res

print(string.format("Total Nodes: %d", #graph.nodes))
print(string.format("Points Per Node: %d", node_points))

local function get_node_v(node_idx, u_idx, v_idx)
    local offset = (node_idx) * node_points * 3
    local v_offset = (v_idx * res + u_idx) * 3
    local idx = offset + v_offset
    return v_buf[idx], v_buf[idx+1], v_buf[idx+2]
end

print("\n--- SEAM ANALYSIS (Trunk Top vs Branch Bottom) ---")
print(string.format("%-10s | %-30s | %-30s | %-10s", "U_IDX", "TRUNK_TOP (XYZ)", "BRANCH_BOTTOM (XYZ)", "ERROR"))
print(string.rep("-", 90))

local max_err = 0
for u = 0, res - 1 do
    local tx, ty, tz = get_node_v(0, u, res - 1) -- Trunk Top (node 0, v=res-1)
    local bx, by, bz = get_node_v(1, u, 0)       -- Branch Bottom (node 1, v=0)
    
    local err = math.sqrt((tx-bx)^2 + (ty-by)^2 + (tz-bz)^2)
    if err > max_err then max_err = err end
    
    local t_str = string.format("%0.6f, %0.6f, %0.6f", tx, ty, tz)
    local b_str = string.format("%0.6f, %0.6f, %0.6f", bx, by, bz)
    
    if u % 4 == 0 or u == res - 1 then
        print(string.format("%-10d | %-30s | %-30s | %0.8f", u, t_str, b_str, err))
    end
end

print("\n--- TOPOLOGY ANALYSIS (Periodic U-Closure) ---")
local function check_closure(node_idx, node_name)
    local closure_err = 0
    for v = 0, res - 1 do
        local x0, y0, z0 = get_node_v(node_idx, 0, v)
        local x1, y1, z1 = get_node_v(node_idx, res - 1, v)
        local err = math.sqrt((x0-x1)^2 + (y0-y1)^2 + (z0-z1)^2)
        if err > closure_err then closure_err = err end
    end
    print(string.format("  Node %d (%s) Periodic Error: %0.8f", node_idx, node_name, closure_err))
end

check_closure(0, "Trunk")
check_closure(1, "Branch")

print("\n--- DIAGNOSTIC SUMMARY ---")
print(string.format("Max Weld Gap:     %0.8f", max_err))
if max_err < 1e-5 then
    print("RESULT: MATH IS BIT-PERFECT. Gap is an artifact of Exporter/Viewer.")
else
    print("RESULT: MATH IS BROKEN. Discrepancy found in Kernels/Transforms.")
end

graph:destroy()
