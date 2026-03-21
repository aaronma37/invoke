local ffi = require("ffi")
local vk = require("vulkan.ffi")
local descriptors = require("vulkan.descriptors")
local command = require("vulkan.command")
package.path = package.path .. ";extensions/mooncrust/?.lua"
local loader = require("examples.27_obj_viewer.loader")

local M = {}

ffi.cdef[[
    typedef struct { float v0[4], v1[4], v2[4], color[4]; } Triangle;
    typedef struct { float x, y, z, sdf, r, g, b, roughness, metallic; } PointSample;
]]

function M.init()
    local obj_path = _ARGS[2] or "current_model.obj"
    local output_path = _ARGS[3] or "current_dataset.pcb"
    
    print("GPU Sampler: Final Signed-Sandwich Mode")
    local raw_data, vertex_count = loader.load(obj_path)
    local num_tris = vertex_count / 3
    local num_samples = 200000 

    local d = vulkan.get_device(); local q, family = vulkan.get_queue()
    local tri_buf = mc.buffer(num_tris * 64, "storage", nil, true)
    local sample_buf = mc.buffer(num_samples * 36, "storage", nil, true)
    
    -- Normalize
    local raw_ptr = ffi.cast("float*", raw_data)
    local min_p, max_p = {1e10,1e10,1e10}, {-1e10,-1e10,-1e10}
    for i=0, vertex_count-1 do
        for a=1,3 do
            min_p[a] = math.min(min_p[a], raw_ptr[i*9+a-1])
            max_p[a] = math.max(max_p[a], raw_ptr[i*9+a-1])
        end
    end
    local center = {(min_p[1]+max_p[1])/2, (min_p[2]+max_p[2])/2, (min_p[3]+max_p[3])/2}
    local scale = 0.9 / math.max((max_p[1]-min_p[1])/2, (max_p[2]-min_p[2])/2, (max_p[3]-min_p[3])/2)

    local tris = ffi.cast("Triangle*", tri_buf.allocation.ptr)
    for i=0, num_tris-1 do
        for v=0,2 do
            local b = (i*3+v)*9
            tris[i]["v"..v][0] = (raw_ptr[b+0] - center[1]) * scale
            tris[i]["v"..v][1] = (raw_ptr[b+1] - center[2]) * scale
            tris[i]["v"..v][2] = (raw_ptr[b+2] - center[3]) * scale
            tris[i]["v"..v][3] = 1.0
        end
    end

    local samples = ffi.cast("PointSample*", sample_buf.allocation.ptr)
    for i=0, num_samples-1 do
        local r = math.random()
        if r < 0.33 then
            local t = tris[math.random(0, num_tris-1)]
            local u, v = math.random(), math.random()
            if u+v > 1 then u,v = 1-u, 1-v end
            local w = 1-u-v
            samples[i].x = u*t.v0[0] + v*t.v1[0] + w*t.v2[0]
            samples[i].y = u*t.v0[1] + v*t.v1[1] + w*t.v2[1]
            samples[i].z = u*t.v0[2] + v*t.v1[2] + w*t.v2[2]
        elseif r < 0.66 then
            local t = tris[math.random(0, num_tris-1)]
            local u, v = math.random(), math.random()
            if u+v > 1 then u,v = 1-u, 1-v end
            local w = 1-u-v
            samples[i].x = u*t.v0[0] + v*t.v1[0] + w*t.v2[0] + (math.random()-0.5)*0.1
            samples[i].y = u*t.v0[1] + v*t.v1[1] + w*t.v2[1] + (math.random()-0.5)*0.1
            samples[i].z = u*t.v0[2] + v*t.v1[2] + w*t.v2[2] + (math.random()-0.5)*0.1
        else
            samples[i].x, samples[i].y, samples[i].z = math.random()*2-1, math.random()*2-1, math.random()*2-1
        end
        samples[i].sdf = 0
    end

    local pipe = mc.compute_pipeline("projects/objaverse_sampler/sampler.comp", 8)
    local bindless_set = mc.gpu.get_bindless_set()
    descriptors.update_buffer_set(d, bindless_set, 0, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, tri_buf.handle, 0, tri_buf.size, 0)
    descriptors.update_buffer_set(d, bindless_set, 1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, sample_buf.handle, 0, sample_buf.size, 1)

    print("Sampling 200,000 points on GPU...")
    local start_time = os.clock()
    local cb = command.allocate_buffers(d, command.create_pool(d, family), 1)[1]
    command.encode(cb, function(cmd)
        vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipe.handle)
        vk.vkCmdBindDescriptorSets(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, pipe.layout, 0, 1, ffi.new("VkDescriptorSet[1]", {bindless_set}), 0, nil)
        vk.vkCmdPushConstants(cb, pipe.layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, ffi.new("uint32_t[2]", {num_tris, num_samples}))
        vk.vkCmdDispatch(cb, math.ceil(num_samples / 256), 1, 1)
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_HOST_BIT, 0, 0, nil, 1, ffi.new("VkBufferMemoryBarrier[1]", {{sType=vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, srcAccessMask=vk.VK_ACCESS_SHADER_WRITE_BIT, dstAccessMask=vk.VK_ACCESS_HOST_READ_BIT, buffer=sample_buf.handle, size=sample_buf.size}}), 0, nil)
    end)
    command.end_and_submit(cb, q, d); vk.vkDeviceWaitIdle(d)

    print(string.format("Complete in %.3fs", os.clock() - start_time))
    local f = io.open(output_path, "wb"); f:write(ffi.string(sample_buf.allocation.ptr, sample_buf.size)); f:close()
    print("Saved points to " .. output_path)
    os.exit(0)
end
function M.update() end
return M
