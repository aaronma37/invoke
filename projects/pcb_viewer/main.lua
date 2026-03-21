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
    orbit_radius = 3.5,
    target_pos = {0, 0, 0},
    last_time = 0,
    initialized = false
}

ffi.cdef[[
    typedef struct { float x, y, z, sdf, r, g, b, roughness, metallic; } PointSample;
    typedef struct { float mvp[16]; } RenderPC;
]]

local device, queue, family, sw, cb
local image_available_sem, render_finished_sem, frame_fence
local pbuf, point_count, depth_img, render_pipe, pipe_layout

function M.init()
    print("PCB Viewer: Final Fix")
    device = vulkan.get_device(); queue, family = vulkan.get_queue(); local pd = vulkan.get_physical_device()
    sw = swapchain.new(vulkan.get_instance(), pd, device, _G._SDL_WINDOW)
    
    local sem_info = ffi.new("VkSemaphoreCreateInfo", { sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO })
    local pSem = ffi.new("VkSemaphore[1]")
    vk.vkCreateSemaphore(device, sem_info, nil, pSem); image_available_sem = pSem[0]
    vk.vkCreateSemaphore(device, sem_info, nil, pSem); render_finished_sem = pSem[0]
    local pFence = ffi.new("VkFence[1]")
    vk.vkCreateFence(device, ffi.new("VkFenceCreateInfo", { sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags = vk.VK_FENCE_CREATE_SIGNALED_BIT }), nil, pFence); frame_fence = pFence[0]

    M.last_time = os.clock()
    if ok_imgui then _G.IMGUI_LIB_PATH = "/home/aaron-ma/invoke/projects/imgui/build/mooncrust_imgui.so"; pcall(imgui.init) end

    local pcb_path = _ARGS[2] or "current_dataset.pcb"
    local f = io.open(pcb_path, "rb"); local data = f:read("*all"); f:close()
    point_count = #data / 36
    pbuf = mc.buffer(#data, "vertex", data, true)
    print("Loaded " .. point_count .. " points.")

    depth_img = mc.image(sw.extent.width, sw.extent.height, image.find_depth_format(pd), "depth")
    pipe_layout = pipeline.create_layout(device, {}, {{stageFlags=vk.VK_SHADER_STAGE_VERTEX_BIT, offset=0, size=64}})
    
    render_pipe = pipeline.create_graphics_pipeline(device, pipe_layout, shader.create_module(device, shader.compile_glsl(io.open("projects/pcb_viewer/point.vert"):read("*all"), vk.VK_SHADER_STAGE_VERTEX_BIT)), shader.create_module(device, shader.compile_glsl(io.open("projects/pcb_viewer/point.frag"):read("*all"), vk.VK_SHADER_STAGE_FRAGMENT_BIT)), { 
        topology = vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
        vertex_binding = ffi.new("VkVertexInputBindingDescription[1]", {{binding=0, stride=36, inputRate=vk.VK_VERTEX_INPUT_RATE_VERTEX}}),
        vertex_attributes = ffi.new("VkVertexInputAttributeDescription[3]", {{location=0, binding=0, format=vk.VK_FORMAT_R32G32B32_SFLOAT, offset=0}, {location=1, binding=0, format=vk.VK_FORMAT_R32_SFLOAT, offset=12}, {location=2, binding=0, format=vk.VK_FORMAT_R32G32B32_SFLOAT, offset=16}}),
        vertex_attribute_count = 3, depth_test = true, depth_write = true, depth_format = image.find_depth_format(pd)
    })

    cb = command.allocate_buffers(device, command.create_pool(device, family), 1)[1]
    M.initialized = true
end

function M.update()
    if not M.initialized then return end
    vk.vkWaitForFences(device, 1, ffi.new("VkFence[1]", {frame_fence}), vk.VK_TRUE, 0xFFFFFFFFFFFFFFFFULL)
    local img_idx = sw:acquire_next_image(image_available_sem); if not img_idx then return end
    vk.vkResetFences(device, 1, ffi.new("VkFence[1]", {frame_fence}))
    
    if _G._MOUSE_L then
        local dx, dy = mc.input.mouse_delta()
        M.orbit_yaw = M.orbit_yaw - dx * 0.01
        M.orbit_pitch = math.max(-math.pi/2+0.1, math.min(math.pi/2-0.1, M.orbit_pitch + dy * 0.01))
    end
    if _G._MOUSE_WHEEL then M.orbit_radius = math.max(0.1, M.orbit_radius - _G._MOUSE_WHEEL * 0.2); _G._MOUSE_WHEEL = 0 end

    if ok_imgui then imgui.new_frame(); if imgui.gui.igBegin("PCB Viewer", nil, 0) then imgui.gui.igText("Points: "..point_count) end imgui.gui.igEnd() end

    vk.vkResetCommandBuffer(cb, 0)
    command.encode(cb, function(cmd)
        local color_attach = ffi.new("VkRenderingAttachmentInfo[1]")
        color_attach[0].sType, color_attach[0].imageView, color_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, ffi.cast("VkImageView", sw.views[img_idx]), vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        color_attach[0].loadOp, color_attach[0].storeOp, color_attach[0].clearValue.color.float32 = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, vk.VK_ATTACHMENT_STORE_OP_STORE, {0.05, 0.05, 0.05, 1.0}
        local depth_attach = ffi.new("VkRenderingAttachmentInfo[1]")
        depth_attach[0].sType, depth_attach[0].imageView, depth_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, depth_img.view, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        depth_attach[0].loadOp, depth_attach[0].storeOp, depth_attach[0].clearValue.depthStencil.depth = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, vk.VK_ATTACHMENT_STORE_OP_STORE, 1.0

        local b = ffi.new("VkImageMemoryBarrier[2]")
        b[0].sType, b[0].oldLayout, b[0].newLayout, b[0].image, b[0].subresourceRange, b[0].dstAccessMask = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, ffi.cast("VkImage", sw.images[img_idx]), {aspectMask=vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount=1, layerCount=1}, vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
        b[1].sType, b[1].oldLayout, b[1].newLayout, b[1].image, b[1].subresourceRange, b[1].dstAccessMask = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL, depth_img.handle, {aspectMask=vk.VK_IMAGE_ASPECT_DEPTH_BIT, levelCount=1, layerCount=1}, bit.bor(vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT, vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT)
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, bit.bor(vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT), 0, 0, nil, 0, nil, 2, b)

        vk.vkCmdBeginRendering(cb, ffi.new("VkRenderingInfo", { sType=vk.VK_STRUCTURE_TYPE_RENDERING_INFO, renderArea={extent=sw.extent}, layerCount=1, colorAttachmentCount=1, pColorAttachments=color_attach, pDepthAttachment=depth_attach }))
        vk.vkCmdSetViewport(cb, 0, 1, ffi.new("VkViewport", { x=0, y=0, width=sw.extent.width, height=sw.extent.height, minDepth=0, maxDepth=1 }))
        vk.vkCmdSetScissor(cb, 0, 1, ffi.new("VkRect2D", { extent=sw.extent }))
        
        vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, render_pipe)
        local cam_x, cam_y, cam_z = math.sin(M.orbit_yaw)*math.cos(M.orbit_pitch)*M.orbit_radius, math.sin(M.orbit_pitch)*M.orbit_radius, math.cos(M.orbit_yaw)*math.cos(M.orbit_pitch)*M.orbit_radius
        local view = mc.mat4_look_at({cam_x, cam_y, cam_z}, {0,0,0}, {0,1,0}); local proj = mc.mat4_perspective(mc.rad(60), sw.extent.width/sw.extent.height, 0.1, 100.0)
        
        local pc = ffi.new("RenderPC"); local mvp = mc.mat4_multiply(proj, view)
        for i=0,15 do pc.mvp[i] = mvp.m[i] end
        vk.vkCmdPushConstants(cb, pipe_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, pc)
        
        vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {pbuf.handle}), ffi.new("VkDeviceSize[1]", {0}))
        vk.vkCmdDraw(cb, point_count, 1, 0, 0)
        
        if ok_imgui then imgui.render(cb) end
        vk.vkCmdEndRendering(cb)

        local b_pres = ffi.new("VkImageMemoryBarrier[1]", {{sType=vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, oldLayout=vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, newLayout=vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, image=ffi.cast("VkImage", sw.images[img_idx]), subresourceRange={aspectMask=vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount=1, layerCount=1}, srcAccessMask=vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, dstAccessMask=0}})
        vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nil, 0, nil, 1, b_pres)
    end)
    vk.vkQueueSubmit(queue, 1, ffi.new("VkSubmitInfo", { sType=vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, waitSemaphoreCount=1, pWaitSemaphores=ffi.new("VkSemaphore[1]", {image_available_sem}), pWaitDstStageMask=ffi.new("VkPipelineStageFlags[1]", {vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}), commandBufferCount=1, pCommandBuffers=ffi.new("VkCommandBuffer[1]", {cb}), signalSemaphoreCount=1, pSignalSemaphores=ffi.new("VkSemaphore[1]", {render_finished_sem}) }), frame_fence); sw:present(queue, img_idx, render_finished_sem)
end
return M
