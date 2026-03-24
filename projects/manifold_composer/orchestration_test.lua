local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local json = require("mc.json")
local Composer = require("composer")

print("--- Lua Orchestration Test: Deep Diagnostic Mode ---")

-- 1. Mock Registry
local registry = {
    gen_cylinder_v1 = {
        generator_id = "gen_cylinder_v1",
        type = "functional",
        topology = "[2, 32, 32, 6]"
    }
}

-- 2. Execution
local graph = Composer.new("recipes/simple_pipe.json", registry)

-- 3. Evaluation
local res = 16
local v_buf, v_count = graph:evaluate(res)
local points_per_node = res * res

local function assert_near(val, target, epsilon, msg)
    if math.abs(val - target) > (epsilon or 1e-4) then
        print(string.format("  [FAIL] %s: Got %0.6f, Expected %0.6f (Diff: %0.6f)", msg, val, target, math.abs(val-target)))
        return false
    end
    return true
end

print("\n--- STEP 1: TRUNK BOUNDARY LOG ---")
local trunk_passed = true
for u = 0, res - 1 do
    local idx = ((res - 1) * res + u) * 3
    local x, y, z = v_buf[idx], v_buf[idx+1], v_buf[idx+2]
    if u == 0 or u == res-1 or u == math.floor(res/2) then
        print(string.format("  Trunk Top UV(%0.2f, 1.0) -> XYZ(%0.6f, %0.6f, %0.6f)", u/(res-1), x, y, z))
    end
end

print("\n--- STEP 2: BRANCH BOUNDARY LOG ---")
local branch_offset = 1 * points_per_node * 3
local weld_passed = true
for u = 0, res - 1 do
    local b_idx = branch_offset + (0 * res + u) * 3
    local bx, by, bz = v_buf[b_idx], v_buf[b_idx+1], v_buf[b_idx+2]
    
    local t_idx = ((res - 1) * res + u) * 3
    local tx, ty, tz = v_buf[t_idx], v_buf[t_idx+1], v_buf[t_idx+2]

    if not assert_near(bx, tx, 1e-5, "Weld Continuity X at u_idx=" .. u) then weld_passed = false end
    if not assert_near(by, ty, 1e-5, "Weld Continuity Y at u_idx=" .. u) then weld_passed = false end
    if not assert_near(bz, tz, 1e-5, "Weld Continuity Z at u_idx=" .. u) then weld_passed = false end
    
    if u == 0 or u == res-1 then
        print(string.format("  Branch Base UV(%0.2f, 0.0) -> XYZ(%0.6f, %0.6f, %0.6f)", u/(res-1), bx, by, bz))
    end
end

-- 4. Cleanup
graph:destroy()

if not weld_passed then
    print("\n--- DIAGNOSTIC RESULT: WELD FAILURE ---")
    print("Likely Cause: Knot multiplicity mapping or basis evaluation at u=1.0 is not hitting the final coefficient.")
    os.exit(1)
else
    print("\n--- DIAGNOSTIC RESULT: SUCCESS ---")
end
