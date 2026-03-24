local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local json = require("mc.json")
local Composer = require("composer")

print("--- BRANCH SEPARATION DIAGNOSTIC ---")

local registry = {
    gen_cylinder_v1 = { generator_id = "gen_cylinder_v1", type = "functional", topology = "[2, 32, 32, 6]", topology_type = "periodic_u" },
    gen_fork_v1 = { generator_id = "gen_fork_v1", type = "functional", topology = "[2, 32, 32, 6]", topology_type = "periodic_u" }
}

local recipe = {
    root = {
        id = "trunk", generator = "gen_cylinder_v1",
        children = {
            {
                id = "junction", generator = "gen_fork_v1", child_socket = "bottom", offset_z = 1.0,
                children = {
                    { id = "L", generator = "gen_cylinder_v1", child_socket = "bottom", offset_z = 1.0 },
                    { id = "R", generator = "gen_cylinder_v1", child_socket = "bottom", offset_z = 1.0 }
                }
            }
        }
    }
}

local f = io.open("/tmp/branch_diag.json", "w"); f:write(json.encode(recipe)); f:close()
local graph = Composer.new("/tmp/branch_diag.json", registry)

local res = 16
local v_buf, v_count = graph:evaluate(res)
local points_per_node = res * res

local function get_xyz(node_idx, u_idx, v_idx)
    local idx = (node_idx * points_per_node + (v_idx * res + u_idx)) * 3
    return v_buf[idx], v_buf[idx+1], v_buf[idx+2]
end

print("\n--- ANALYZING BRANCH SEPARATION (U=0.5 SPLIT) ---")
-- In our node list: 1=trunk, 2=junction, 3=L, 4=R
local lx, ly, lz = get_xyz(2, 0, 0) -- Left Branch Base (u=0)
local rx, ry, rz = get_xyz(3, res-1, 0) -- Right Branch Base (u=1)

print(string.format("Left Branch Start (u=0):  %0.6f, %0.6f, %0.6f", lx, ly, lz))
print(string.format("Right Branch End (u=1):   %0.6f, %0.6f, %0.6f", rx, ry, rz))

local dist = math.sqrt((lx-rx)^2 + (ly-ry)^2 + (lz-rz)^2)
print(string.format("Separation Distance:      %0.8f", dist))

if dist < 0.01 then
    print("\n[DIAGNOSIS] BRANCHES ARE MATHEMATICALLY TOUCHING.")
    print("The 'web' is caused by the B-spline grid being continuous across the 0.5 boundary.")
    print("To fix this, the 'Fork' must define two DISCRETE socket coefficient ranges.")
else
    print("\n[DIAGNOSIS] BRANCHES ARE SEPARATED.")
    print("The 'web' is an indexing artifact in the triangle generator.")
end

graph:destroy()
