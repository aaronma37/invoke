local ffi = require("ffi")
local vk = require("vulkan.ffi")
local descriptors = require("vulkan.descriptors")
local command = require("vulkan.command")
local pipeline = require("vulkan.pipeline")
local shader = require("vulkan.shader")
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
    local obj_path = _ARGS[2] or "extensions/mooncrust/examples/27_obj_viewer/Sponza/sponza.obj"
    local output_path = _ARGS[3] or "objaverse_sample.pcb"
    
    print("Example 54: Objaverse GPU Sampler")
    print("Loading mesh: " .. obj_path)
    
    -- 1. Load OBJ
    local raw_data, vertex_count
    local ok, err = pcall(function() 
        raw_data, vertex_count = loader.load(obj_path) 
    end)

    if not ok or vertex_count == 0 then
        print("OBJ Load failed, using cube...")
        vertex_count = 36
        raw_data = ffi.new("float[?]", vertex_count * 9)
    end
    local num_tris = vertex_count / 3
    print("Mesh ready: " .. num_tris .. " triangles")

    local d = vulkan.get_device()
    local q, family = vulkan.get_queue()
    local physical_device = vulkan.get_physical_device()
    
    -- 2. Create GPU Buffers
    local num_samples = 100000 -- Reduced to avoid system freeze
    local tri_buf = mc.buffer(num_tris * ffi.sizeof("Triangle"), "storage", nil, false)
    local sample_buf = mc.buffer(num_samples * ffi.sizeof("PointSample"), "storage", nil, false)
    local download_buf = mc.buffer(num_samples * ffi.sizeof("PointSample"), "storage", nil, true)
    local count_buf = mc.buffer(8, "uniform", ffi.new("uint32_t[2]", {num_tris, num_samples}), true)
    
    -- 3. Prepare and Normalize Triangle Data
    local tri_data = ffi.new("Triangle[?]", num_tris)
    local raw_ptr = ffi.cast("float*", raw_data)
    local min_p = {1e10, 1e10, 1e10}
    local max_p = {-1e10, -1e10, -1e10}

    for i=0, num_tris-1 do
        for v=0, 2 do
            local base = (i * 3 + v) * 9
            local p = {raw_ptr[base+0], raw_ptr[base+1], raw_ptr[base+2]}
            local target_v = (v == 0) and tri_data[i].v0 or (v == 1 and tri_data[i].v1 or tri_data[i].v2)
            target_v[0], target_v[1], target_v[2], target_v[3] = p[1], p[2], p[3], 1.0
            for axis=1, 3 do
                min_p[axis] = math.min(min_p[axis], p[axis])
                max_p[axis] = math.max(max_p[axis], p[axis])
            end
        end
        local c_base = i * 3 * 9 + 6
        tri_data[i].color[0], tri_data[i].color[1], tri_data[i].color[2], tri_data[i].color[3] = raw_ptr[c_base+0], raw_ptr[c_base+1], raw_ptr[c_base+2], 1.0
    end

    local center = { (min_p[1] + max_p[1]) / 2, (min_p[2] + max_p[2]) / 2, (min_p[3] + max_p[3]) / 2 }
    local max_extent = math.max((max_p[1] - min_p[1]) / 2, (max_p[2] - min_p[2]) / 2, (max_p[3] - min_p[3]) / 2, 1e-6)
    local norm_scale = 0.9 / max_extent

    for i=0, num_tris-1 do
        for v=0, 2 do
            local target_v = (v == 0) and tri_data[i].v0 or (v == 1 and tri_data[i].v1 or tri_data[i].v2)
            target_v[0] = (target_v[0] - center[1]) * norm_scale
            target_v[1] = (target_v[1] - center[2]) * norm_scale
            target_v[2] = (target_v[2] - center[3]) * norm_scale
        end
    end
    tri_buf:upload(tri_data)

    -- 4. Prepare Samples
    local host_samples = ffi.new("PointSample[?]", num_samples)
    for i=0, num_samples-1 do
        if math.random() > 0.5 then
            host_samples[i].x, host_samples[i].y, host_samples[i].z = math.random()*2-1, math.random()*2-1, math.random()*2-1
        else
            local t = tri_data[math.random(0, num_tris-1)]
            local u, v = math.random(), math.random()
            if u + v > 1 then u, v = 1-u, 1-v end
            local w = 1 - u - v
            host_samples[i].x = u*t.v0[0] + v*t.v1[0] + w*t.v2[0] + (math.random()-0.5)*0.05
            host_samples[i].y = u*t.v0[1] + v*t.v1[1] + w*t.v2[1] + (math.random()-0.5)*0.05
            host_samples[i].z = u*t.v0[2] + v*t.v1[2] + w*t.v2[2] + (math.random()-0.5)*0.05
        end
    end
    sample_buf:upload(host_samples)

    -- 5. Manual Pipeline Setup (to avoid bindless mismatch)
    local bindings = {
        { binding = 0, type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages = vk.VK_SHADER_STAGE_COMPUTE_BIT },
        { binding = 1, type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages = vk.VK_SHADER_STAGE_COMPUTE_BIT },
        { binding = 2, type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, stages = vk.VK_SHADER_STAGE_COMPUTE_BIT }
    }
    local ds_layout = descriptors.create_layout(d, bindings)
    local pipe_layout = pipeline.create_layout(d, {ds_layout})
    
    local shader_src = io.open("projects/objaverse_sampler/sampler.comp"):read("*all")
    local shader_mod = shader.create_module(d, shader.compile_glsl(shader_src, vk.VK_SHADER_STAGE_COMPUTE_BIT))
    local pipe_handle = pipeline.create_compute_pipeline(d, pipe_layout, shader_mod)

    local ds_pool = descriptors.create_pool(d, {
        { type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, count = 2 },
        { type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, count = 1 }
    })
    local ds = descriptors.allocate_sets(d, ds_pool, {ds_layout})[1]
    descriptors.update_buffer_set(d, ds, 0, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, tri_buf.handle, 0, tri_buf.size)
    descriptors.update_buffer_set(d, ds, 1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, sample_buf.handle, 0, sample_buf.size)
    descriptors.update_buffer_set(d, ds, 2, vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, count_buf.handle, 0, count_buf.size)

    -- 6. Execute
    local pool = command.create_pool(d, family)
    local cb = command.allocate_buffers(d, pool, 1)[1]

    print("Sampling " .. num_samples .. " points against " .. num_tris .. " triangles on GPU...")
    local start_time = os.clock()

    command.encode(cb, function(cmd)
        vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipe_handle)
        vk.vkCmdBindDescriptorSets(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipe_layout, 0, 1, ffi.new("VkDescriptorSet[1]", {ds}), 0, nil)
        vk.vkCmdDispatch(cb, math.ceil(num_samples / 256), 1, 1)
        
        local barrier = ffi.new("VkBufferMemoryBarrier[1]", {{
            sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
            srcAccessMask = vk.VK_ACCESS_SHADER_WRITE_BIT,
            dstAccessMask = vk.VK_ACCESS_TRANSFER_READ_BIT,
            buffer = sample_buf.handle, offset = 0, size = sample_buf.size
        }})
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nil, 1, barrier, 0, nil)
        
        local region = ffi.new("VkBufferCopy", { srcOffset = 0, dstOffset = 0, size = sample_buf.size })
        vk.vkCmdCopyBuffer(cb, sample_buf.handle, download_buf.handle, 1, region)
    end)
    command.end_and_submit(cb, q, d)

    print("Sampling complete in " .. string.format("%.3f", os.clock() - start_time) .. "s")

    -- 7. Save
    local results = ffi.cast("PointSample*", download_buf.allocation.ptr)
    print("First 5 samples: " .. string.format("%.6f, %.6f, %.6f, %.6f, %.6f", results[0].sdf, results[1].sdf, results[2].sdf, results[3].sdf, results[4].sdf))
    
    local file = io.open(output_path, "wb")
    file:write(ffi.string(download_buf.allocation.ptr, download_buf.size))
    file:close()
    print("Saved points to " .. output_path)
    os.exit(0)
end

function M.update() end
return M
