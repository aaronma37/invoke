local ffi = require("ffi")
local vk = require("vulkan.ffi")
local descriptors = require("vulkan.descriptors")
local command = require("vulkan.command")
local pipeline = require("vulkan.pipeline")
local shader = require("vulkan.shader")
package.path = package.path .. ";projects/uv_sampler_gpu/?.lua"
local loader = require("loader")

local M = {}

ffi.cdef[[
    typedef struct { float v0[4], v1[4], v2[4], unused[4]; } Triangle;
    typedef struct { float u, v, z_zero, sdf, r, g, b, roughness, metallic; } PointSample;
    typedef struct { float origin[4]; float direction[4]; } RayQuery;
]]

function M.init()
    local target_path = _ARGS[2] or "artifacts/raw/bunny_target.obj"
    local output_path = _ARGS[3] or "artifacts/datasets/bunny_gpu.pcb"
    local base_path = _ARGS[4] or "artifacts/raw/base_sphere_05.obj"
    
    print("--- GPU UV Sampler ---")
    print("Target: " .. target_path)
    print("Base:   " .. base_path)

    -- 1. Load Meshes
    local target_tris_raw = loader.load(target_path)
    local num_target_tris = #target_tris_raw / 3
    
    local base_verts_raw = loader.load(base_path)
    local num_queries = #base_verts_raw
    
    print("Target triangles: " .. num_target_tris)
    print("Base vertices (queries): " .. num_queries)

    local d = vulkan.get_device(); local q, family = vulkan.get_queue()
    
    -- 2. Prepare Buffers
    local tri_buf = mc.buffer(num_target_tris * 64, "storage", nil, false)
    local query_buf = mc.buffer(num_queries * 32, "storage", nil, false)
    local sample_buf = mc.buffer(num_queries * 36, "storage", nil, false)
    local down_buf = mc.buffer(num_queries * 36, "storage", nil, true)
    
    -- Upload target triangles
    local tri_data = ffi.new("Triangle[?]", num_target_tris)
    for i=0, num_target_tris-1 do
        for v=0,2 do
            local vert = target_tris_raw[i*3 + v + 1]
            tri_data[i]["v"..v][0] = vert.pos[1]
            tri_data[i]["v"..v][1] = vert.pos[2]
            tri_data[i]["v"..v][2] = vert.pos[3]
            tri_data[i]["v"..v][3] = 1.0
        end
    end
    tri_buf:upload(tri_data)

    -- Upload queries and initial samples
    local query_data = ffi.new("RayQuery[?]", num_queries)
    local sample_data = ffi.new("PointSample[?]", num_queries)
    for i=0, num_queries-1 do
        local vert = base_verts_raw[i+1]
        
        query_data[i].origin[0] = vert.pos[1]
        query_data[i].origin[1] = vert.pos[2]
        query_data[i].origin[2] = vert.pos[3]
        query_data[i].origin[3] = 1.0
        
        -- Ray direction is the vertex normal (or normalized position for sphere)
        local nx, ny, nz = vert.normal[1], vert.normal[2], vert.normal[3]
        local mag = math.sqrt(nx*nx + ny*ny + nz*nz)
        if mag < 1e-6 then 
            -- Fallback to normalized position
            nx, ny, nz = vert.pos[1], vert.pos[2], vert.pos[3]
            mag = math.sqrt(nx*nx + ny*ny + nz*nz)
        end
        query_data[i].direction[0] = nx / mag
        query_data[i].direction[1] = ny / mag
        query_data[i].direction[2] = nz / mag
        query_data[i].direction[3] = 0.0
        
        sample_data[i].u = vert.uv[1]
        sample_data[i].v = vert.uv[2]
        sample_data[i].z_zero = 0.0
        sample_data[i].sdf = 0.0
        sample_data[i].r, sample_data[i].g, sample_data[i].b = 0.5, 0.5, 0.5
        sample_data[i].roughness = 0.5
        sample_data[i].metallic = 0.0
    end
    query_buf:upload(query_data)
    sample_buf:upload(sample_data)

    -- 3. Pipeline Setup
    local l = descriptors.create_layout(d, {
        {binding=0, type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages=vk.VK_SHADER_STAGE_COMPUTE_BIT},
        {binding=1, type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages=vk.VK_SHADER_STAGE_COMPUTE_BIT},
        {binding=2, type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages=vk.VK_SHADER_STAGE_COMPUTE_BIT}
    })
    local ly = pipeline.create_layout(d, {l}, {{stageFlags=vk.VK_SHADER_STAGE_COMPUTE_BIT, offset=0, size=8}})
    
    local comp_src = io.open("projects/uv_sampler_gpu/uv_sampler.comp"):read("*all")
    local p = pipeline.create_compute_pipeline(d, ly, shader.create_module(d, shader.compile_glsl(comp_src, vk.VK_SHADER_STAGE_COMPUTE_BIT)))
    
    local ds = descriptors.allocate_sets(d, descriptors.create_pool(d, {{type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, count=3}}), {l})[1]
    descriptors.update_buffer_set(d, ds, 0, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, tri_buf.handle, 0, tri_buf.size)
    descriptors.update_buffer_set(d, ds, 1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, query_buf.handle, 0, query_buf.size)
    descriptors.update_buffer_set(d, ds, 2, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, sample_buf.handle, 0, sample_buf.size)

    -- 4. Dispatch
    local cb = command.allocate_buffers(d, command.create_pool(d, family), 1)[1]
    command.encode(cb, function(cmd)
        vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, p)
        vk.vkCmdBindDescriptorSets(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, ly, 0, 1, ffi.new("VkDescriptorSet[1]", {ds}), 0, nil)
        vk.vkCmdPushConstants(cb, ly, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, ffi.new("uint32_t[2]", {num_target_tris, num_queries}))
        vk.vkCmdDispatch(cb, math.ceil(num_queries / 256), 1, 1)
        
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nil, 1, ffi.new("VkBufferMemoryBarrier[1]", {{
            sType=vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, 
            srcAccessMask=vk.VK_ACCESS_SHADER_WRITE_BIT, 
            dstAccessMask=vk.VK_ACCESS_TRANSFER_READ_BIT, 
            buffer=sample_buf.handle, 
            size=sample_buf.size
        }}), 0, nil)
        
        vk.vkCmdCopyBuffer(cb, sample_buf.handle, down_buf.handle, 1, ffi.new("VkBufferCopy", {size=sample_buf.size}))
    end)
    
    print("Dispatching Compute Shader...")
    local start_time = os.clock()
    command.end_and_submit(cb, q, d); vk.vkDeviceWaitIdle(d)
    print(string.format("GPU Time: %.3f seconds", os.clock() - start_time))

    -- 5. Save Result
    local f = io.open(output_path, "wb")
    f:write(ffi.string(down_buf.allocation.ptr, down_buf.size))
    f:close()
    print("Saved samples to " .. output_path)
    
    os.exit(0)
end

function M.update() end
return M
