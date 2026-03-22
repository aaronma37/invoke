local ffi = require("ffi")
local vk = require("vulkan.ffi")
local pipeline = require("vulkan.pipeline")
local descriptors = require("vulkan.descriptors")
local shader = require("vulkan.shader")
local swapchain = require("vulkan.swapchain")
local image = require("vulkan.image")
local command = require("vulkan.command")
package.path = package.path .. ";extensions/mooncrust/?.lua"
local loader = require("examples.27_obj_viewer.loader")
local input = require("mc.input")
local sdl = require("vulkan.sdl")
local imgui = require("imgui")

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end

local M = { 
    cam_dist = 3.0,
    cam_yaw = 0,
    cam_pitch = 0.5,
    target = {0, 0.8, 0},
    latents = ffi.new("float[16]"),
    update_morph = true
}

local device, queue, sw, render_layout, graphics_pipe, compute_layout, compute_pipeline_layout, compute_pipe
local base_vbuf, uv_buf, morph_vbuf, weight_buf
local vertex_count, depth_img, ds_compute
local cb, image_available_sem, frame_fence

function M.init()
    _G.IMGUI_LIB_PATH = "/home/aaron-ma/invoke/projects/imgui/build/mooncrust_imgui.so"
    local model_path = "artifacts/models/vroid_vae_kan.kan"
    local base_obj = "/home/aaron-ma/VRoidDatasetGen/Dataset_Output/vroid_0000.obj"
    print("--- VRoid VAE Viewer ---")
    
    device = vulkan.get_device()
    local physical_device = vulkan.get_physical_device()
    local q, family = vulkan.get_queue()
    queue = q
    sw = swapchain.new(vulkan.get_instance(), physical_device, device, _G._SDL_WINDOW)

    -- Initialize ImGui
    pcall(imgui.init)
    imgui.get_io = function() return imgui._S.ffi_lib.igGetIO_Nil() end

    -- 1. Load Base Mesh and UVs
    local data, count = loader.load(base_obj)
    vertex_count = count
    base_vbuf = mc.buffer(ffi.sizeof(data), "storage", data)
    morph_vbuf = mc.buffer(ffi.sizeof(data), "vertex", nil)

    local pcb_path = "artifacts/datasets/vroid_batch_pcb/vroid_0000.pcb"
    local f = io.open(pcb_path, "rb")
    local pcb_raw = f:read("*all")
    f:close()
    uv_buf = mc.buffer(#pcb_raw, "storage", pcb_raw)

    -- 2. Load KAN Weights
    local wf = io.open(model_path, "rb")
    local w_raw = wf:read("*all")
    wf:close()
    weight_buf = mc.buffer(#w_raw, "storage", w_raw)

    -- 3. Compute Pipeline (Morphing)
    compute_layout = descriptors.create_layout(device, {
        {binding=0, type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages=vk.VK_SHADER_STAGE_COMPUTE_BIT},
        {binding=1, type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages=vk.VK_SHADER_STAGE_COMPUTE_BIT},
        {binding=2, type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages=vk.VK_SHADER_STAGE_COMPUTE_BIT},
        {binding=3, type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages=vk.VK_SHADER_STAGE_COMPUTE_BIT}
    })
    compute_pipeline_layout = pipeline.create_layout(device, {compute_layout}, {{stageFlags=vk.VK_SHADER_STAGE_COMPUTE_BIT, offset=0, size=128}})
    local c_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/vroid_vae_viewer/vae_morph.comp"):read("*all"), vk.VK_SHADER_STAGE_COMPUTE_BIT))
    compute_pipe = pipeline.create_compute_pipeline(device, compute_pipeline_layout, c_mod)
    
    ds_compute = descriptors.allocate_sets(device, descriptors.create_pool(device, {{type=vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, count=4}}), {compute_layout})[1]
    descriptors.update_buffer_set(device, ds_compute, 0, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, base_vbuf.handle, 0, base_vbuf.size)
    descriptors.update_buffer_set(device, ds_compute, 1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, uv_buf.handle, 0, uv_buf.size)
    descriptors.update_buffer_set(device, ds_compute, 2, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, morph_vbuf.handle, 0, morph_vbuf.size)
    descriptors.update_buffer_set(device, ds_compute, 3, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, weight_buf.handle, 0, weight_buf.size)

    -- 4. Graphics Pipeline (Rendering)
    local depth_format = image.find_depth_format(physical_device)
    depth_img = mc.gpu.image(sw.extent.width, sw.extent.height, depth_format, "depth")
    
    render_layout = pipeline.create_layout(device, {}, {{stageFlags=vk.VK_SHADER_STAGE_VERTEX_BIT, offset=0, size=64}})
    local v_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/obj_viewer/viewer.vert"):read("*all"), vk.VK_SHADER_STAGE_VERTEX_BIT))
    local f_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/obj_viewer/viewer.frag"):read("*all"), vk.VK_SHADER_STAGE_FRAGMENT_BIT))
    graphics_pipe = pipeline.create_graphics_pipeline(device, render_layout, v_mod, f_mod, {
        vertex_binding = ffi.new("VkVertexInputBindingDescription[1]", {{ binding = 0, stride = 36, inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX }}),
        vertex_attributes = ffi.new("VkVertexInputAttributeDescription[3]", {
            { location = 0, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 0 },
            { location = 1, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 12 },
            { location = 2, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 24 }
        }),
        depth_test = true, depth_write = true, depth_format = depth_format
    })

    -- Sync
    cb = command.allocate_buffers(device, command.create_pool(device, family), 1)[1]
    frame_fence = ffi.new("VkFence[1]"); vk.vkCreateFence(device, ffi.new("VkFenceCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags=vk.VK_FENCE_CREATE_SIGNALED_BIT}), nil, frame_fence); frame_fence = frame_fence[0]
    image_available_sem = ffi.new("VkSemaphore[1]"); vk.vkCreateSemaphore(device, ffi.new("VkSemaphoreCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO}), nil, image_available_sem); image_available_sem = image_available_sem[0]
end

function M.update()
    vk.vkWaitForFences(device, 1, ffi.new("VkFence[1]", {frame_fence}), vk.VK_TRUE, 0xFFFFFFFFFFFFFFFFULL)
    vk.vkResetFences(device, 1, ffi.new("VkFence[1]", {frame_fence}))
    
    local idx = sw:acquire_next_image(image_available_sem)
    if idx == nil then return end

    -- GUI
    imgui.new_frame()
    local gui = imgui.gui
    if gui.igBegin("VAE Sliders", nil, 0) then
        for i=0, 15 do
            local changed = gui.igSliderFloat("Latent " .. i, M.latents + i, -2.0, 2.0, "%.3f", 1.0)
            if changed then M.update_morph = true end
        end
    end
    gui.igEnd()

    -- Orbit Camera
    local mx, my = input.mouse_pos()
    if input.mouse_down(1) and not imgui.get_io().WantCaptureMouse then
        if M.last_mx then
            M.cam_yaw = M.cam_yaw - (mx - M.last_mx) * 0.01
            M.cam_pitch = clamp(M.cam_pitch + (my - M.last_my) * 0.01, -1.5, 1.5)
        end
    end
    M.last_mx, M.last_my = mx, my
    
    local cam_x = M.target[1] + M.cam_dist * math.cos(M.cam_pitch) * math.sin(M.cam_yaw)
    local cam_y = M.target[2] + M.cam_dist * math.sin(M.cam_pitch)
    local cam_z = M.target[3] + M.cam_dist * math.cos(M.cam_pitch) * math.cos(M.cam_yaw)
    local view = mc.mat4_look_at({cam_x, cam_y, cam_z}, {M.target[1], M.target[2], M.target[3]}, {0, 1, 0})
    local proj = mc.mat4_perspective(mc.rad(60), sw.extent.width/sw.extent.height, 0.01, 100.0)
    proj.m[5] = -proj.m[5]
    local mvp = mc.mat4_multiply(proj, view)

    vk.vkResetCommandBuffer(cb, 0); vk.vkBeginCommandBuffer(cb, ffi.new("VkCommandBufferBeginInfo", { sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO }))
    
    -- 1. Morph Pass
    vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, compute_pipe)
    vk.vkCmdBindDescriptorSets(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, compute_pipeline_layout, 0, 1, ffi.new("VkDescriptorSet[1]", {ds_compute}), 0, nil)
    
    local push = ffi.new("struct { float l[16]; uint32_t count; uint32_t off1; uint32_t off2; uint32_t out1; uint32_t out2; float kmin1; float kmax1; float kmin2; float kmax2; }")
    for i=0,15 do push.l[i] = M.latents[i] end
    push.count = vertex_count
    
    -- Layer 1: 18 -> 64, 8 coeffs. 
    push.off1 = 19
    push.out1 = 64
    push.kmin1 = 0.0 
    push.kmax1 = 1.0
    
    -- Layer 2: 64 -> 3, 8 coeffs.
    push.off2 = 9252
    push.out2 = 16 
    push.kmin2 = -1.0 -- Hidden layer knots
    push.kmax2 = 1.0
    
    vk.vkCmdPushConstants(cb, compute_pipeline_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, 128, push)
    vk.vkCmdDispatch(cb, math.ceil(vertex_count / 256), 1, 1)
    
    local bar = ffi.new("VkBufferMemoryBarrier[1]", {{
        sType = vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
        srcAccessMask = vk.VK_ACCESS_SHADER_WRITE_BIT,
        dstAccessMask = vk.VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT,
        buffer = morph_vbuf.handle, size = morph_vbuf.size
    }})
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, 0, 0, nil, 1, bar, 0, nil)

    -- 2. Render Pass
    local bar_img = ffi.new("VkImageMemoryBarrier[1]", {{ 
        sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, 
        newLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, 
        image = ffi.cast("VkImage", sw.images[idx]), 
        subresourceRange = { aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount = 1, layerCount = 1 }, 
        dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT 
    }})
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, nil, 0, nil, 1, bar_img)

    local color_attach = ffi.new("VkRenderingAttachmentInfo[1]")
    color_attach[0].sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO
    color_attach[0].imageView = ffi.cast("VkImageView", sw.views[idx])
    color_attach[0].imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    color_attach[0].loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR
    color_attach[0].clearValue.color.float32 = {0.1, 0.1, 0.12, 1.0}
    color_attach[0].storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE
    
    local depth_attach = ffi.new("VkRenderingAttachmentInfo[1]")
    depth_attach[0].sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO
    depth_attach[0].imageView = depth_img.view
    depth_attach[0].imageLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    depth_attach[0].loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR
    depth_attach[0].clearValue.depthStencil.depth = 1.0
    depth_attach[0].storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE

    vk.vkCmdBeginRendering(cb, ffi.new("VkRenderingInfo", { sType=vk.VK_STRUCTURE_TYPE_RENDERING_INFO, renderArea={extent=sw.extent}, layerCount=1, colorAttachmentCount=1, pColorAttachments=color_attach, pDepthAttachment=depth_attach }))
    vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipe)
    vk.vkCmdSetViewport(cb, 0, 1, ffi.new("VkViewport", { width=sw.extent.width, height=sw.extent.height, maxDepth=1 }))
    vk.vkCmdSetScissor(cb, 0, 1, ffi.new("VkRect2D", { extent=sw.extent }))
    vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {morph_vbuf.handle}), ffi.new("VkDeviceSize[1]", {0}))
    vk.vkCmdPushConstants(cb, render_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, mvp.m)
    vk.vkCmdDraw(cb, vertex_count, 1, 0, 0)
    
    imgui.render(cb)
    vk.vkCmdEndRendering(cb)

    bar_img[0].oldLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    bar_img[0].newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    bar_img[0].srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nil, 0, nil, 1, bar_img)
    vk.vkEndCommandBuffer(cb)
    
    vk.vkQueueSubmit(queue, 1, ffi.new("VkSubmitInfo", { sType=vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, waitSemaphoreCount=1, pWaitSemaphores=ffi.new("VkSemaphore[1]", {image_available_sem}), pWaitDstStageMask=ffi.new("VkPipelineStageFlags[1]", {vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}), commandBufferCount=1, pCommandBuffers=ffi.new("VkCommandBuffer[1]", {cb}), signalSemaphoreCount=1, pSignalSemaphores=ffi.new("VkSemaphore[1]", {sw.semaphores[idx]}) }), frame_fence)
    sw:present(queue, idx, sw.semaphores[idx])
end

return M
