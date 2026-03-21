local ffi = require("ffi")
local vk = require("vulkan.ffi")
local descriptors = require("vulkan.descriptors")
local command = require("vulkan.command")
local swapchain = require("vulkan.swapchain")
local pipeline = require("vulkan.pipeline")
local shader = require("vulkan.shader")
local image = require("vulkan.image")
local bit = require("bit")

local ok_imgui, imgui = pcall(require, "imgui")

local M = {
    orbit_yaw = 0,
    orbit_pitch = 0.3,
    orbit_radius = 2.5,
    target_pos = {0, 0, 0},
    last_time = 0,
    last_fps_print = 0,
    dt = 0.016,
    sdf_threshold = 0.05,
    initialized = false
}

ffi.cdef[[
    typedef struct {
        float x, y, z;
        float sdf;
        float r, g, b;
        float roughness;
        float metallic;
    } PointSample;

    typedef struct {
        float mvp[16];
        float threshold;
        float padding[3];
    } RenderPC;
]]

local device, queue, family, sw, cb, pool
local image_available_sem, render_finished_sem, frame_fence
local pbuf, point_count, depth_img
local render_pipe, pipe_layout

function M.init()
    print("PCB Viewer: Validating SDF Point Cloud")
    
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

    -- 1. Load PCB
    local pcb_path = _ARGS[2] or "current_dataset.pcb"
    if not os.exists(pcb_path) then pcb_path = "bunny_sample.pcb" end
    
    local f = io.open(pcb_path, "rb")
    if not f then
        print("Error: Could not open PCB file: " .. pcb_path)
        return
    end
    local data = f:read("*all")
    f:close()
    
    point_count = #data / ffi.sizeof("PointSample")
    print(string.format("Loaded %d points from %s", point_count, pcb_path))
    pbuf = mc.buffer(#data, "vertex", data, true)

    -- 2. Depth Buffer
    local depth_format = image.find_depth_format(physical_device)
    depth_img = mc.image(sw.extent.width, sw.extent.height, depth_format, "depth")

    -- 3. Pipeline
    local get_shader_path = function(name) return "projects/pcb_viewer/" .. name end
    
    pipe_layout = pipeline.create_layout(device, {}, { { stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, offset = 0, size = ffi.sizeof("RenderPC") } })
    local v_src = io.open(get_shader_path("point.vert")):read("*all")
    local f_src = io.open(get_shader_path("point.frag")):read("*all")
    
    render_pipe = pipeline.create_graphics_pipeline(device, pipe_layout, shader.create_module(device, shader.compile_glsl(v_src, vk.VK_SHADER_STAGE_VERTEX_BIT)), shader.create_module(device, shader.compile_glsl(f_src, vk.VK_SHADER_STAGE_FRAGMENT_BIT)), { 
        topology = vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
        vertex_binding = ffi.new("VkVertexInputBindingDescription[1]", {{ binding = 0, stride = ffi.sizeof("PointSample"), inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX }}),
        vertex_attributes = ffi.new("VkVertexInputAttributeDescription[3]", {
            { location = 0, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 0 }, -- x, y, z
            { location = 1, binding = 0, format = vk.VK_FORMAT_R32_SFLOAT, offset = 12 },    -- sdf
            { location = 2, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 16 } -- r, g, b
        }),
        vertex_attribute_count = 3, depth_test = true, depth_write = true, depth_format = depth_format
    })

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
        M.orbit_radius = math.max(0.1, M.orbit_radius - _G._MOUSE_WHEEL * 0.2)
        _G._MOUSE_WHEEL = 0
    end

    -- Keyboard Fallback for threshold (using reliable arrow keys)
    local input = mc.input
    local old_thresh = M.sdf_threshold
    if input.key_down(input.SCANCODE_UP) then M.sdf_threshold = math.min(1, M.sdf_threshold + 0.01) end
    if input.key_down(input.SCANCODE_DOWN) then M.sdf_threshold = math.max(0, M.sdf_threshold - 0.01) end
    if input.key_down(input.SCANCODE_RIGHT) then M.sdf_threshold = math.min(1, M.sdf_threshold + 0.001) end
    if input.key_down(input.SCANCODE_LEFT) then M.sdf_threshold = math.max(0, M.sdf_threshold - 0.001) end
    
    if M.sdf_threshold ~= old_thresh then
        print(string.format("Threshold: %.4f", M.sdf_threshold))
    end

    -- ImGui Frame
    if ok_imgui then
        imgui.new_frame()
        local gui = imgui.gui
        gui.igSetNextWindowPos(ffi.new("ImVec2_c", {10, 10}), 1, ffi.new("ImVec2_c", {0, 0}))
        gui.igSetNextWindowSize(ffi.new("ImVec2_c", {350, 180}), 1)
        if gui.igBegin("PCB Viewer", nil, 0) then
            gui.igText(string.format("FPS: %.1f", 1.0 / math.max(M.dt, 0.0001)))
            gui.igText(string.format("Points: %d", point_count))
            gui.igText(string.format("Threshold: %.4f", M.sdf_threshold))
            gui.igText("Use Arrows to adjust threshold")
            gui.igText("Up/Down (0.01) | Left/Right (0.001)")
            local p_val = ffi.new("float[1]", {M.sdf_threshold})
            if gui.igSliderFloat("SDF Threshold", p_val, 0.0, 0.5, "%.4f", 0) then
                M.sdf_threshold = p_val[0]
            end
        end
        gui.igEnd()
    else
        if now - M.last_fps_print > 1.0 then
            print(string.format("FPS: %.1f | Points: %d", 1.0 / math.max(M.dt, 0.0001), point_count))
            M.last_fps_print = now
        end
    end

    vk.vkResetCommandBuffer(cb, 0)
    command.encode(cb, function(cmd)
        local color_attach = ffi.new("VkRenderingAttachmentInfo[1]")
        color_attach[0].sType, color_attach[0].imageView, color_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, ffi.cast("VkImageView", sw.views[img_idx]), vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        color_attach[0].loadOp, color_attach[0].storeOp, color_attach[0].clearValue.color.float32 = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, vk.VK_ATTACHMENT_STORE_OP_STORE, {0.01, 0.01, 0.01, 1.0}
        
        local depth_attach = ffi.new("VkRenderingAttachmentInfo[1]")
        depth_attach[0].sType, depth_attach[0].imageView, depth_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, depth_img.view, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        depth_attach[0].loadOp, depth_attach[0].storeOp, depth_attach[0].clearValue.depthStencil.depth = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, vk.VK_ATTACHMENT_STORE_OP_STORE, 1.0

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
        
        local pc = ffi.new("RenderPC")
        for i=0,15 do pc.mvp[i] = mvp.m[i] end
        pc.threshold = M.sdf_threshold
        vk.vkCmdPushConstants(cb, pipe_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, ffi.sizeof("RenderPC"), pc)
        
        vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {pbuf.handle}), ffi.new("VkDeviceSize[1]", {0}))
        vk.vkCmdDraw(cb, point_count, 1, 0, 0)
        
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

function os.exists(name)
   local f = io.open(name, "r")
   if f ~= nil then io.close(f) return true else return false end
end

return M
