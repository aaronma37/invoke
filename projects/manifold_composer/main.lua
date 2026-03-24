local ffi = require("ffi")

-- AUTO-PATH: Resolve MoonCrust library locations
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua"

local mc = require("mc")
local vk = require("vulkan.ffi")

-- Define the Manifold Extension API
ffi.cdef[[
    typedef void* ManifoldNetwork_t;
    ManifoldNetwork_t manifold_init(const size_t* layer_dims, size_t num_layers, size_t num_coeffs);
    void manifold_deinit(ManifoldNetwork_t handle);
    void manifold_set_socket(ManifoldNetwork_t handle, uint32_t socket_type, const float* points, size_t num_points);
    void manifold_forward_pinned(ManifoldNetwork_t handle, const float* inputs, float** activations, float* outputs, size_t batch_size);
]]

local lib = ffi.load("ext/libmanifold_ext.so")

print("--- Manifold Composer: Functional Test ---")

-- 1. Setup Manifold Logic
local num_coeffs = 16
local dims = ffi.new("size_t[3]", {2, 32, 32})
local trunk = lib.manifold_init(dims, 3, num_coeffs)
local branch_l = lib.manifold_init(dims, 3, num_coeffs)
local branch_r = lib.manifold_init(dims, 3, num_coeffs)

-- Helper: Create a circular socket
local function create_socket(radius, z_pos, points_count)
    local points = ffi.new("float[?][3]", points_count)
    for i = 0, points_count - 1 do
        local a = (i / points_count) * math.pi * 2
        points[i][0] = math.cos(a) * radius
        points[i][1] = math.sin(a) * radius
        points[i][2] = z_pos
    end
    return points
end

-- 2. Setup Data Buffers for Evaluation
local res = 16
local batch_size = res * res
local inputs = ffi.new("float[?]", batch_size * 2)
for v = 0, res - 1 do
    for u = 0, res - 1 do
        local idx = (v * res + u) * 2
        inputs[idx] = u / (res - 1)
        inputs[idx + 1] = v / (res - 1)
    end
end

local function create_acts(net_dims, num_layers, b_size)
    local acts = ffi.new("float*[?]", num_layers)
    for i = 0, num_layers - 1 do
        acts[i] = ffi.new("float[?]", b_size * net_dims[i])
    end
    return acts
end

local trunk_acts = create_acts(dims, 3, batch_size)
local trunk_out  = ffi.new("float[?]", batch_size * 3)

local branch_acts = create_acts(dims, 3, batch_size)
local branch_out  = ffi.new("float[?]", batch_size * 3)

-- 3. PINNING
local base_socket = create_socket(0.5, 0.0, num_coeffs)
local mid_socket  = create_socket(0.3, 1.0, num_coeffs)

lib.manifold_set_socket(trunk, 1, ffi.cast("const float*", base_socket), num_coeffs)
lib.manifold_set_socket(trunk, 0, ffi.cast("const float*", mid_socket), num_coeffs)
lib.manifold_set_socket(branch_l, 1, ffi.cast("const float*", mid_socket), num_coeffs)
lib.manifold_set_socket(branch_r, 1, ffi.cast("const float*", mid_socket), num_coeffs)

print("Status: Objects Welded. Starting Tick.")

-- 4. Main Loop
while true do
    -- Run the math
    lib.manifold_forward_pinned(trunk, inputs, trunk_acts, trunk_out, batch_size)
    lib.manifold_forward_pinned(branch_l, inputs, branch_acts, branch_out, batch_size)
    
    -- Print validation occasionally
    local tx, ty, tz = trunk_out[((res-1)*res)*3], trunk_out[((res-1)*res)*3+1], trunk_out[((res-1)*res)*3+2]
    print(string.format("Trunk Top Sample: %0.3f, %0.3f, %0.3f", tx, ty, tz))

    mc.tick()
end
