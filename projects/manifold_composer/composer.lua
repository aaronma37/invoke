local ffi = require("ffi")
local json = require("mc.json")

-- Load the Manifold Extension
local lib = ffi.load("ext/libmanifold_ext.so")

ffi.cdef[[
    typedef void* ManifoldNetwork_t;
    ManifoldNetwork_t manifold_init(const size_t* layer_dims, size_t num_layers, size_t num_coeffs);
    void manifold_deinit(ManifoldNetwork_t handle);
    void manifold_set_socket(ManifoldNetwork_t handle, uint32_t socket_type, const float* coeffs, size_t num_points);
    void manifold_forward_pinned(ManifoldNetwork_t handle, const float* inputs, float** activations, float* outputs, size_t batch_size);
    float* manifold_get_coeffs(ManifoldNetwork_t handle);
    void manifold_set_coeffs(ManifoldNetwork_t handle, const float* data, size_t count);
    void manifold_set_topology(ManifoldNetwork_t handle, uint32_t topo_type);
    void manifold_make_identity(ManifoldNetwork_t handle);
]]

-- --- COMPOSER CLASS ---

local Composer = {}
Composer.__index = Composer

function Composer.new(recipe_path, registry)
    local self = setmetatable({}, Composer)
    self.registry = registry
    self.nodes = {}
    recipe_path = recipe_path:gsub("^%-%-recipe=", "")
    local f = io.open(recipe_path, "r")
    if not f then error("Could not open recipe: " .. recipe_path) end
    self.recipe = json.decode(f:read("*a"))
    f:close()
    
    -- Root Identity Transform
    local root_transform = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 }
    self:compile_node(self.recipe.root, nil, root_transform, 0.0)
    return self
end

function Composer:compile_node(node_def, parent_coeffs, world_transform, cumulative_z)
    local gen_info = self.registry[node_def.generator]
    if not gen_info then error("Generator not found: " .. node_def.generator) end
    
    local top_str = gen_info.topology:gsub("[%[%]]", "")
    local top_dims = {}
    for d in top_str:gmatch("%d+") do table.insert(top_dims, tonumber(d)) end
    
    local num_layers = #top_dims - 1
    local dims = ffi.new("size_t[?]", num_layers)
    for i = 1, num_layers do dims[i-1] = top_dims[i] end
    
    local num_coeffs = 32
    local handle = lib.manifold_init(dims, num_layers, num_coeffs)
    
    local topo_map = { open = 0, periodic_u = 1, periodic_uv = 2, capped = 3 }
    lib.manifold_set_topology(handle, topo_map[gen_info.topology_type] or 0)

    -- HARDENED: Functional Injection with Cumulative Height Offset
    if gen_info.type == "functional" then
        lib.manifold_make_identity(handle)
        local def_path = "definitions/" .. gen_info.generator_id:gsub("^gen_", ""):gsub("_v%d+$", "") .. ".lua"
        local def = dofile(def_path)
        local c_data = ffi.new("float[?]", num_coeffs * num_coeffs * 3)
        for v = 0, num_coeffs - 1 do
            for u = 0, num_coeffs - 1 do
                local u_val, v_val = u / (num_coeffs - 1), v / (num_coeffs - 1)
                -- Latents: [Radius, Height, OffsetZ]
                local x, y, z = def.evaluate(u_val, v_val, {0.5, 1.0, cumulative_z})
                local idx = (v * num_coeffs + u) * 3
                c_data[idx], c_data[idx+1], c_data[idx+2] = x, y, z
            end
        end
        lib.manifold_set_coeffs(handle, c_data, num_coeffs * num_coeffs * 3)
    end

    if parent_coeffs then
        lib.manifold_set_socket(handle, 1, ffi.cast("const float*", parent_coeffs), num_coeffs)
    end
    
    local node = { id = node_def.id, handle = handle, topology = top_dims, num_layers = num_layers, world_transform = world_transform }
    table.insert(self.nodes, node)
    
    if node_def.children then
        local my_coeffs = lib.manifold_get_coeffs(handle)
        local top_row_offset = (num_coeffs - 1) * num_coeffs * 3
        local top_row_coeffs = my_coeffs + top_row_offset
        
        for _, child_def in ipairs(node_def.children) do
            -- Increment cumulative height for the next segment
            local next_z = cumulative_z + (child_def.offset_z or 1.0)
            self:compile_node(child_def, top_row_coeffs, world_transform, next_z)
        end
    end
end

function Composer:evaluate(resolution)
    local batch_size = resolution * resolution
    local total_points = #self.nodes * batch_size
    local vertex_buffer = ffi.new("float[?]", total_points * 3)
    local inputs = ffi.new("float[?]", batch_size * 2)
    for v = 0, resolution - 1 do
        for u = 0, resolution - 1 do
            local idx = (v * resolution + u) * 2
            inputs[idx], inputs[idx + 1] = u / (resolution - 1), v / (resolution - 1)
        end
    end
    for i, node in ipairs(self.nodes) do
        local offset = (i - 1) * batch_size * 3
        local acts = ffi.new("float*[?]", #node.topology)
        for l = 1, #node.topology do acts[l-1] = ffi.new("float[?]", batch_size * node.topology[l]) end
        
        local local_buffer = ffi.new("float[?]", batch_size * 3)
        lib.manifold_forward_pinned(node.handle, inputs, acts, local_buffer, batch_size)
        
        -- Since world position is now correctly baked via cumulative_z in coefficients,
        -- the world transform should be Identity for ALL nodes including Root.
        local m = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
        for b = 0, batch_size - 1 do
            local lx, ly, lz = local_buffer[b*3], local_buffer[b*3+1], local_buffer[b*3+2]
            vertex_buffer[offset + b*3 + 0] = lx*m[1] + ly*m[2] + lz*m[3] + m[4]
            vertex_buffer[offset + b*3 + 1] = lx*m[5] + ly*m[6] + lz*m[7] + m[8]
            vertex_buffer[offset + b*3 + 2] = lx*m[9] + ly*m[10] + lz*m[11] + m[12]
        end
    end
    return vertex_buffer, total_points
end

function Composer:destroy()
    for _, node in ipairs(self.nodes) do lib.manifold_deinit(node.handle) end
end

return Composer
