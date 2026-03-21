local ffi = require("ffi")
local vk = require("vulkan.ffi")
local descriptors = require("vulkan.descriptors")
local command = require("vulkan.command")
package.path = package.path .. ";extensions/mooncrust/?.lua"
local loader = require("examples.27_obj_viewer.loader")

local M = {}

-- Define structs for FFI
ffi.cdef[[
    typedef struct {
        float v0[4];
        float v1[4];
        float v2[4];
        float color[4];
    } Triangle;

    typedef struct {
        float x, y, z;
        float sdf;
        float r, g, b;
        float roughness;
        float metallic;
    } PointSample;
]]

function M.init()
    -- Mooncrust uses _ARGS global table (0-based)
    -- _ARGS[0] = binary, _ARGS[1] = script, _ARGS[2] = user_arg1...
    local obj_path = _ARGS[2] or "extensions/mooncrust/examples/27_obj_viewer/Sponza/sponza.obj"
    local output_path = _ARGS[3] or "objaverse_sample.pcb"
    
    print("Example 54: Objaverse GPU Sampler")
    print("Loading mesh: " .. obj_path)
    
    -- 1. Load OBJ or Generate Procedural Mesh
    local raw_data, vertex_count
    local ok, err = pcall(function() 
        raw_data, vertex_count = loader.load(obj_path) 
    end)

    if not ok or vertex_count == 0 then
        print("OBJ Load failed or empty (" .. tostring(err) .. "), generating procedural Cube...")
        -- Generate a cube (12 triangles)
        vertex_count = 36
        raw_data = ffi.new("float[?]", vertex_count * 9)
        local cube_verts = {
            {-1,-1,-1}, {1,-1,-1}, {1,1,-1}, {-1,1,-1},
            {-1,-1,1}, {1,-1,1}, {1,1,1}, {-1,1,1}
        }
        local cube_faces = {
            {1,2,3}, {1,3,4}, {5,6,7}, {5,7,8}, -- Back/Front
            {1,5,8}, {1,8,4}, {2,6,7}, {2,7,3}, -- Left/Right
            {1,2,6}, {1,6,5}, {4,3,7}, {4,7,8}  -- Bottom/Top
        }
        for i, face in ipairs(cube_faces) do
            for v=1, 3 do
                local base = ((i-1)*3 + (v-1)) * 9
                local p = cube_verts[face[v]]
                raw_data[base+0] = p[1]; raw_data[base+1] = p[2]; raw_data[base+2] = p[3]
                raw_data[base+3] = 0; raw_data[base+4] = 1; raw_data[base+5] = 0 -- Normal
                raw_data[base+6] = 1; raw_data[base+7] = 0; raw_data[base+8] = 0 -- Color
            end
        end
    end
    local num_tris = vertex_count / 3
    print("Mesh ready: " .. num_tris .. " triangles")

    local d = vulkan.get_device()
    local q, family = vulkan.get_queue()
    
    -- 2. Create GPU Buffers
    local tri_buf = mc.buffer(num_tris * ffi.sizeof("Triangle"), "storage", nil, true)
    local num_samples = 200000 -- Increase for real test
    local sample_buf = mc.buffer(num_samples * ffi.sizeof("PointSample"), "storage", nil, true)
    
    -- 3. Prepare Triangle Data for GPU
    local tris = ffi.cast("Triangle*", tri_buf.allocation.ptr)
    local raw_ptr = ffi.cast("float*", raw_data)
    
    -- Bounding box for sampling
    local min_p = {1e10, 1e10, 1e10}
    local max_p = {-1e10, -1e10, -1e10}

    for i=0, num_tris-1 do
        -- Each triangle has 3 vertices, each vertex has 9 floats [P, N, C]
        for v=0, 2 do
            local base = (i * 3 + v) * 9
            local p = {raw_ptr[base+0], raw_ptr[base+1], raw_ptr[base+2]}
            
            -- Store in Triangle struct
            local target_v = (v == 0) and tris[i].v0 or (v == 1 and tris[i].v1 or tris[i].v2)
            target_v[0] = p[1]; target_v[1] = p[2]; target_v[2] = p[3]; target_v[3] = 1.0
            
            -- Update BB
            for axis=1, 3 do
                min_p[axis] = math.min(min_p[axis], p[axis])
                max_p[axis] = math.max(max_p[axis], p[axis])
            end
        end
        -- Use color from first vertex
        local c_base = i * 3 * 9 + 6
        tris[i].color[0] = raw_ptr[c_base+0]
        tris[i].color[1] = raw_ptr[c_base+1]
        tris[i].color[2] = raw_ptr[c_base+2]
        tris[i].color[3] = 1.0
    end

    -- 4. Fill sample_buf with random positions in Bounding Box
    print(string.format("Bounding Box: (%.2f, %.2f, %.2f) to (%.2f, %.2f, %.2f)", min_p[1], min_p[2], min_p[3], max_p[1], max_p[2], max_p[3]))
    local samples = ffi.cast("PointSample*", sample_buf.allocation.ptr)
    for i=0, num_samples-1 do
        -- Sample near surface (50%) or in box (50%)
        if math.random() > 0.5 then
            -- Random in box
            samples[i].x = min_p[1] + math.random() * (max_p[1] - min_p[1])
            samples[i].y = min_p[2] + math.random() * (max_p[2] - min_p[2])
            samples[i].z = min_p[3] + math.random() * (max_p[3] - min_p[3])
        else
            -- Pick a random triangle and a point on it
            local t_idx = math.random(0, num_tris-1)
            local t = tris[t_idx]
            local u, v = math.random(), math.random()
            if u + v > 1 then u, v = 1-u, 1-v end
            local w = 1 - u - v
            samples[i].x = u*t.v0[0] + v*t.v1[0] + w*t.v2[0] + (math.random()-0.5)*0.1
            samples[i].y = u*t.v0[1] + v*t.v1[1] + w*t.v2[1] + (math.random()-0.5)*0.1
            samples[i].z = u*t.v0[2] + v*t.v1[2] + w*t.v2[2] + (math.random()-0.5)*0.1
        end
    end

    -- 5. Create Compute Pipeline
    local pipe = mc.compute_pipeline("projects/objaverse_sampler/sampler.comp")
    
    -- 6. Bind and Dispatch
    local bindless_set = mc.gpu.get_bindless_set()
    descriptors.update_buffer_set(d, bindless_set, 0, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, tri_buf.handle, 0, tri_buf.size, 0)
    descriptors.update_buffer_set(d, bindless_set, 1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, sample_buf.handle, 0, sample_buf.size, 1)

    local pool = command.create_pool(d, family)
    local cb = command.allocate_buffers(d, pool, 1)[1]

    print("Sampling " .. num_samples .. " points against " .. num_tris .. " triangles on GPU...")
    local start_time = os.clock()

    command.encode(cb, function(cmd)
        local pc_data = ffi.new("uint32_t[2]", {num_tris, num_samples})
        vk.vkCmdPushConstants(cb, pipe.layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, pc_data)
        cmd:bind_pipeline(vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipe.handle)
        cmd:bind_descriptor_sets(vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipe.layout, 0, {bindless_set})
        cmd:dispatch(math.ceil(num_samples / 256), 1, 1)
        
        local barrier = ffi.new("VkMemoryBarrier[1]", {{
            sType = vk.VK_STRUCTURE_TYPE_MEMORY_BARRIER,
            srcAccessMask = vk.VK_ACCESS_SHADER_WRITE_BIT,
            dstAccessMask = vk.VK_ACCESS_HOST_READ_BIT
        }})
        cmd:pipeline_barrier(vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_HOST_BIT, barrier)
    end)
    command.end_and_submit(cb, q, d)

    local end_time = os.clock()
    print("Sampling complete in " .. string.format("%.3f", end_time - start_time) .. "s")

    -- 7. Save to .pcb
    local file = io.open(output_path, "wb")
    local data = ffi.string(sample_buf.allocation.ptr, sample_buf.size)
    file:write(data)
    file:close()
    print("Saved points to " .. output_path)
    
    os.exit(0)
end

function M.update()
end

return M
