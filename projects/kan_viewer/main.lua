local ffi = require("ffi")
local vk = require("vulkan.ffi")
local descriptors = require("vulkan.descriptors")
local command = require("vulkan.command")
local swapchain = require("vulkan.swapchain")
local pipeline = require("vulkan.pipeline")
local shader = require("vulkan.shader")
local image = require("vulkan.image")
local bit = require("bit")
_G.IMGUI_LIB_PATH = "/home/aaron-ma/invoke/projects/imgui/build/mooncrust_imgui.so"
local ok_imgui, imgui = pcall(require, "imgui")

local M = {
    orbit_yaw = 0,
    orbit_pitch = 0.3,
    orbit_radius = 3.0,
    target_pos = {0, 0, 0},
    last_time = 0,
    last_fps_print = 0,
    dt = 0.016
}

ffi.cdef[[
    typedef struct {
        float pos[4];
        float normal[4];
        float color[4];
        float uv[2];
        float padding[2];
    } Vertex;

    typedef struct {
        uint32_t num_verts;
        float time;
        float scale;
        float padding;
    } MesherPC;

    typedef struct {
        float mvp[16];
        float model[16];
    } RenderPC;
]]

local device, queue, family, sw, cb, pool
local image_available_sem, render_finished_sem, frame_fence
local vbuf, ibuf, idx_count, v_count
local kan_buf, depth_img
local mesher_pipe, render_pipe, pipe_layout, mesher_layout
local ds_pool, ds_mesher

function M.generate_uv_sphere(rows, cols)
    local verts = ffi.new("Vertex[?]", (rows + 1) * (cols + 1))
    local indices = ffi.new("uint32_t[?]", rows * cols * 6)
    
    local v_idx = 0
    for r = 0, rows do
        local theta = r * math.pi / rows
        local sin_theta = math.sin(theta)
        local cos_theta = math.cos(theta)
        
        for c = 0, cols do
            local phi = c * 2 * math.pi / cols
            local sin_phi = math.sin(phi)
            local cos_phi = math.cos(phi)
            
            local x = cos_phi * sin_theta
            local y = cos_theta
            local z = sin_phi * sin_theta
            
            verts[v_idx].pos[0] = x
            verts[v_idx].pos[1] = y
            verts[v_idx].pos[2] = z
            verts[v_idx].pos[3] = 1.0
            
            verts[v_idx].uv[0] = c / cols
            verts[v_idx].uv[1] = r / rows
            
            v_idx = v_idx + 1
        end
    end
    
    local i_idx = 0
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local first = r * (cols + 1) + c
            local second = first + cols + 1
            
            indices[i_idx] = first
            indices[i_idx + 1] = second
            indices[i_idx + 2] = first + 1
            
            indices[i_idx + 3] = second
            indices[i_idx + 4] = second + 1
            indices[i_idx + 5] = first + 1
            
            i_idx = i_idx + 6
        end
    end
    
    return verts, (rows + 1) * (cols + 1), indices, rows * cols * 6
end

function M.init()
    print("Example 55: KAN Mesh Renderer")
    
    device = vulkan.get_device()
    queue, family = vulkan.get_queue()
    local physical_device = vulkan.get_physical_device()
    sw = swapchain.new(vulkan.get_instance(), physical_device, device, _G._SDL_WINDOW)
    
    local sem_info = ffi.new("VkSemaphoreCreateInfo", { sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO })
    local pSem = ffi.new("VkSemaphore[1]")
    vk.vkCreateSemaphore(device, sem_info, nil, pSem); image_available_sem = pSem[0]
    vk.vkCreateSemaphore(device, sem_info, nil, pSem); render_finished_sem = pSem[0]
    
    local fence_info = ffi.new("VkFenceCreateInfo", { sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags = vk.VK_FENCE_CREATE_SIGNALED_BIT })
    local pFence = ffi.new("VkFence[1]")
    vk.vkCreateFence(device, fence_info, nil, pFence); frame_fence = pFence[0]

    M.last_time = os.clock()
    -- Initialize ImGui
    if ok_imgui then
        local status, err = pcall(imgui.init)
        if not status then
            print("Warning: ImGui initialization failed: " .. tostring(err))
            ok_imgui = false
        end
    end
    M.last_fps_print = 0

    -- 1. Load KAN
    local f = io.open("model.kan", "rb")
    if f then
        local data = f:read("*all")
        f:close()
        local l1_start = 8 + 12 + 48 + 1
        local weight_data = data:sub(l1_start, l1_start + 1536 - 1) .. data:sub(l1_start + 1536 + 12 + 48, l1_start + 1536 + 12 + 48 + 512 - 1)
        kan_buf = mc.buffer(#weight_data, "storage", weight_data, true)
    else
        print("Warning: model.kan not found, using empty weights.")
        kan_buf = mc.buffer(2048, "storage", nil, true)
    end

    -- 2. Generate Mesh
    local verts, num_verts, indices, num_indices = M.generate_uv_sphere(128, 128)
    v_count = num_verts
    idx_count = num_indices
    vbuf = mc.buffer(num_verts * ffi.sizeof("Vertex"), "vertex_storage", verts, true)
    ibuf = mc.buffer(num_indices * 4, "index", indices, true)

    -- 3. Depth Buffer
    local depth_format = image.find_depth_format(physical_device)
    depth_img = mc.image(sw.extent.width, sw.extent.height, depth_format, "depth")

    -- 4. Pipelines
    local get_shader_path = function(name) return "projects/kan_viewer/" .. name end
    
    -- Mesher Compute
    local c_bindings = {
        { binding = 0, type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages = vk.VK_SHADER_STAGE_COMPUTE_BIT },
        { binding = 1, type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages = vk.VK_SHADER_STAGE_COMPUTE_BIT }
    }
    local c_ds_layout = descriptors.create_layout(device, c_bindings)
    mesher_layout = pipeline.create_layout(device, {c_ds_layout}, { { stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT, offset = 0, size = ffi.sizeof("MesherPC") } })
    local c_src = io.open(get_shader_path("mesher.comp")):read("*all")
    mesher_pipe = pipeline.create_compute_pipeline(device, mesher_layout, shader.create_module(device, shader.compile_glsl(c_src, vk.VK_SHADER_STAGE_COMPUTE_BIT)))

    -- Render Graphics
    pipe_layout = pipeline.create_layout(device, {}, { { stageFlags = bit.bor(vk.VK_SHADER_STAGE_VERTEX_BIT, vk.VK_SHADER_STAGE_FRAGMENT_BIT), offset = 0, size = ffi.sizeof("RenderPC") } })
    local v_src = io.open(get_shader_path("render.vert")):read("*all")
    local f_src = io.open(get_shader_path("render.frag")):read("*all")
    render_pipe = pipeline.create_graphics_pipeline(device, pipe_layout, shader.create_module(device, shader.compile_glsl(v_src, vk.VK_SHADER_STAGE_VERTEX_BIT)), shader.create_module(device, shader.compile_glsl(f_src, vk.VK_SHADER_STAGE_FRAGMENT_BIT)), { 
        vertex_binding = ffi.new("VkVertexInputBindingDescription[1]", {{ binding = 0, stride = ffi.sizeof("Vertex"), inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX }}),
        vertex_attributes = ffi.new("VkVertexInputAttributeDescription[3]", {
            { location = 0, binding = 0, format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, offset = 0 },
            { location = 1, binding = 0, format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, offset = 16 },
            { location = 2, binding = 0, format = vk.VK_FORMAT_R32G32B32A32_SFLOAT, offset = 32 }
        }),
        vertex_attribute_count = 3, depth_test = true, depth_write = true, depth_format = depth_format, cull_mode = vk.VK_CULL_MODE_BACK_BIT
    })

    -- 5. Descriptor Sets
    ds_pool = descriptors.create_pool(device, {{ type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, count = 2 }})
    ds_mesher = descriptors.allocate_sets(device, ds_pool, {c_ds_layout})[1]
    descriptors.update_buffer_set(device, ds_mesher, 0, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, kan_buf.handle, 0, kan_buf.size)
    descriptors.update_buffer_set(device, ds_mesher, 1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, vbuf.handle, 0, vbuf.size)

    pool = command.create_pool(device, family)
    cb = command.allocate_buffers(device, pool, 1)[1]
    M.initialized = true
end

function M.update()
    if not M.initialized then return end
    local now = os.clock()
    M.dt = now - M.last_time
    M.last_time = now

    vk.vkWaitForFences(device, 1, ffi.new("VkFence[1]", {frame_fence}), vk.VK_TRUE, 0xFFFFFFFFFFFFFFFFULL)
    local img_idx = sw:acquire_next_image(image_available_sem)
    if not img_idx then return end
    vk.vkResetFences(device, 1, ffi.new("VkFence[1]", {frame_fence}))
    
    local input = mc.input
    if _G._MOUSE_L then
        local dx, dy = input.mouse_delta()
        M.orbit_yaw = M.orbit_yaw - dx * 0.01
        M.orbit_pitch = math.max(-math.pi/2+0.1, math.min(math.pi/2-0.1, M.orbit_pitch + dy * 0.01))
    end
    if _G._MOUSE_WHEEL then
        M.orbit_radius = math.max(0.5, M.orbit_radius - _G._MOUSE_WHEEL * 0.2)
        _G._MOUSE_WHEEL = 0
    end

    -- ImGui New Frame
    if ok_imgui then
        imgui.new_frame()
        local gui = imgui.gui
        if gui.igBegin("KAN Stats", nil, 0) then
            gui.igText(string.format("FPS: %.1f", 1.0 / math.max(M.dt, 0.0001)))
            gui.igText(string.format("Vertices: %d", v_count))
        end
        gui.igEnd()
    else
        if now - M.last_fps_print > 1.0 then
            print(string.format("FPS: %.1f (Vertices: %d)", 1.0 / math.max(M.dt, 0.0001), v_count))
            M.last_fps_print = now
        end
    end

    vk.vkResetCommandBuffer(cb, 0)
    command.encode(cb, function(cmd)
        -- 1. Compute Pass: Mesh Deformation
        vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, mesher_pipe)
        vk.vkCmdBindDescriptorSets(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, mesher_layout, 0, 1, ffi.new("VkDescriptorSet[1]", {ds_mesher}), 0, nil)
        local m_pc = ffi.new("MesherPC", { v_count, os.clock(), 1.0, 0 })
        vk.vkCmdPushConstants(cb, mesher_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, ffi.sizeof("MesherPC"), m_pc)
        vk.vkCmdDispatch(cb, math.ceil(v_count / 256), 1, 1)

        -- Barrier for vertex buffer
        local v_barrier = ffi.new("VkBufferMemoryBarrier[1]", {{ 
            sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, 
            srcAccessMask = vk.VK_ACCESS_SHADER_WRITE_BIT, 
            dstAccessMask = vk.VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT, 
            buffer = vbuf.handle, offset = 0, size = vbuf.size 
        }})
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, 0, 0, nil, 1, v_barrier, 0, nil)

        -- 2. Graphics Pass: Forward Rendering
        local color_attach = ffi.new("VkRenderingAttachmentInfo[1]")
        color_attach[0].sType, color_attach[0].imageView, color_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, ffi.cast("VkImageView", sw.views[img_idx]), vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        color_attach[0].loadOp, color_attach[0].storeOp, color_attach[0].clearValue.color.float32 = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, vk.VK_ATTACHMENT_STORE_OP_STORE, {0.02, 0.02, 0.03, 1.0}
        
        local depth_attach = ffi.new("VkRenderingAttachmentInfo[1]")
        depth_attach[0].sType, depth_attach[0].imageView, depth_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, depth_img.view, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        depth_attach[0].loadOp, depth_attach[0].storeOp, depth_attach[0].clearValue.depthStencil.depth = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, depth_attach[0].storeOp, 1.0

        local barriers = ffi.new("VkImageMemoryBarrier[2]")
        barriers[0].sType, barriers[0].oldLayout, barriers[0].newLayout = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        barriers[0].image, barriers[0].subresourceRange = ffi.cast("VkImage", sw.images[img_idx]), { aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount = 1, layerCount = 1 }
        barriers[0].dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
        barriers[1].sType, barriers[1].oldLayout, barriers[1].newLayout = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        barriers[1].image, barriers[1].subresourceRange = depth_img.handle, { aspectMask = vk.VK_IMAGE_ASPECT_DEPTH_BIT, levelCount = 1, layerCount = 1 }
        barriers[1].dstAccessMask = bit.bor(vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT, vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT)
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, bit.bor(vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT), 0, 0, nil, 0, nil, 2, barriers)

        vk.vkCmdBeginRendering(cb, ffi.new("VkRenderingInfo", { sType=vk.VK_STRUCTURE_TYPE_RENDERING_INFO, renderArea={extent=sw.extent}, layerCount=1, colorAttachmentCount=1, pColorAttachments=color_attach, pDepthAttachment=depth_attach }))
        vk.vkCmdSetViewport(cb, 0, 1, ffi.new("VkViewport", { x=0, y=0, width=sw.extent.width, height=sw.extent.height, minDepth=0, maxDepth=1 }))
        vk.vkCmdSetScissor(cb, 0, 1, ffi.new("VkRect2D", { extent=sw.extent }))
        
        vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, render_pipe)
        
        -- Matrix Setup
        local cam_x = M.target_pos[1] + math.sin(M.orbit_yaw) * math.cos(M.orbit_pitch) * M.orbit_radius
        local cam_y = M.target_pos[2] + math.sin(M.orbit_pitch) * M.orbit_radius
        local cam_z = M.target_pos[3] + math.cos(M.orbit_yaw) * math.cos(M.orbit_pitch) * M.orbit_radius
        local view = mc.mat4_look_at({cam_x, cam_y, cam_z}, M.target_pos, {0, 1, 0})
        local proj = mc.mat4_perspective(mc.rad(60), sw.extent.width/sw.extent.height, 0.1, 100.0)
        local mvp = mc.mat4_multiply(proj, view)
        local model = mc.mat4_identity()
        
        local pc = ffi.new("RenderPC")
        for i=0,15 do pc.mvp[i] = mvp.m[i]; pc.model[i] = model.m[i] end
        vk.vkCmdPushConstants(cb, pipe_layout, bit.bor(vk.VK_SHADER_STAGE_VERTEX_BIT, vk.VK_SHADER_STAGE_FRAGMENT_BIT), 0, ffi.sizeof("RenderPC"), pc)
        
        vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {vbuf.handle}), ffi.new("VkDeviceSize[1]", {0}))
        vk.vkCmdBindIndexBuffer(cb, ibuf.handle, 0, vk.VK_INDEX_TYPE_UINT32)
        vk.vkCmdDrawIndexed(cb, idx_count, 1, 0, 0, 0)
        
        -- Render ImGui on top
        if ok_imgui then imgui.render(cb) end
        
        vk.vkCmdEndRendering(cb)

        local present_barrier = ffi.new("VkImageMemoryBarrier[1]", {{ 
            sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, 
            oldLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, 
            newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, 
            image = ffi.cast("VkImage", sw.images[img_idx]), 
            subresourceRange = { aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount = 1, layerCount = 1 }, 
            srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, 
            dstAccessMask = 0 
        }})
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nil, 0, nil, 1, present_barrier)
    end)

    local submit_info = ffi.new("VkSubmitInfo", { 
        sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, 
        waitSemaphoreCount = 1, pWaitSemaphores = ffi.new("VkSemaphore[1]", {image_available_sem}), 
        pWaitDstStageMask = ffi.new("VkPipelineStageFlags[1]", {vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}), 
        commandBufferCount = 1, pCommandBuffers = ffi.new("VkCommandBuffer[1]", {cb}), 
        signalSemaphoreCount = 1, pSignalSemaphores = ffi.new("VkSemaphore[1]", {render_finished_sem}) 
    })
    vk.vkQueueSubmit(queue, 1, submit_info, frame_fence)
    sw:present(queue, img_idx, render_finished_sem)
end

return M
