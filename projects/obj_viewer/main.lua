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
local bit = require("bit")

local M = { 
    cam_dist = 3.0,
    cam_yaw = 0,
    cam_pitch = 0.5
}

local device, queue, sw, pipe_layout, graphics_pipe
local vertex_buffer, vertex_count, depth_img
local cb, image_available_sem, frame_fence

function M.init()
    local obj_path = _ARGS[2] or "artifacts/eval/bunny_gpu_full_displaced.obj"
    print("--- OBJ Viewer ---")
    print("Viewing: " .. obj_path)
    
    local instance = vulkan.get_instance()
    local physical_device = vulkan.get_physical_device()
    device = vulkan.get_device()
    local q, family = vulkan.get_queue()
    queue = q
    sw = swapchain.new(instance, physical_device, device, _G._SDL_WINDOW)

    -- 1. Load Model
    local data, count = loader.load(obj_path)
    vertex_count = count
    vertex_buffer = mc.buffer(ffi.sizeof(data), "vertex", data)

    -- 2. Depth Buffer
    local depth_format = image.find_depth_format(physical_device)
    depth_img = mc.gpu.image(sw.extent.width, sw.extent.height, depth_format, "depth")

    -- 3. Pipelines
    local pc_range = ffi.new("VkPushConstantRange[1]", {{ 
        stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, 
        offset = 0, size = 64 
    }})
    pipe_layout = pipeline.create_layout(device, {}, pc_range)

    local v_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/obj_viewer/viewer.vert"):read("*all"), vk.VK_SHADER_STAGE_VERTEX_BIT))
    local f_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/obj_viewer/viewer.frag"):read("*all"), vk.VK_SHADER_STAGE_FRAGMENT_BIT))

    graphics_pipe = pipeline.create_graphics_pipeline(device, pipe_layout, v_mod, f_mod, { 
        vertex_binding = ffi.new("VkVertexInputBindingDescription[1]", {{ binding = 0, stride = 36, inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX }}),
        vertex_attributes = ffi.new("VkVertexInputAttributeDescription[3]", {
            { location = 0, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 0 },
            { location = 1, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 12 },
            { location = 2, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 24 }
        }),
        depth_test = true, depth_write = true, depth_format = depth_format,
        cull_mode = vk.VK_CULL_MODE_NONE -- Some generated meshes might have flipped normals
    })

    -- 4. Sync
    local pool = command.create_pool(device, family)
    cb = command.allocate_buffers(device, pool, 1)[1]
    frame_fence = ffi.new("VkFence[1]"); vk.vkCreateFence(device, ffi.new("VkFenceCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags=vk.VK_FENCE_CREATE_SIGNALED_BIT}), nil, frame_fence); frame_fence = frame_fence[0]
    image_available_sem = ffi.new("VkSemaphore[1]"); vk.vkCreateSemaphore(device, ffi.new("VkSemaphoreCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO}), nil, image_available_sem); image_available_sem = image_available_sem[0]
end

function M.update()
    vk.vkWaitForFences(device, 1, ffi.new("VkFence[1]", {frame_fence}), vk.VK_TRUE, 0xFFFFFFFFFFFFFFFFULL)
    vk.vkResetFences(device, 1, ffi.new("VkFence[1]", {frame_fence}))
    
    local idx = sw:acquire_next_image(image_available_sem)
    if idx == nil then return end
    
    -- Orbit controls
    local rot_speed = 0.03
    if input.key_down(input.SCANCODE_LEFT) then M.cam_yaw = M.cam_yaw - rot_speed end
    if input.key_down(input.SCANCODE_RIGHT) then M.cam_yaw = M.cam_yaw + rot_speed end
    if input.key_down(input.SCANCODE_UP) then M.cam_pitch = math.min(M.cam_pitch + rot_speed, 1.5) end
    if input.key_down(input.SCANCODE_DOWN) then M.cam_pitch = math.max(M.cam_pitch - rot_speed, -1.5) end
    if input.key_down(input.SCANCODE_W) then M.cam_dist = math.max(M.cam_dist - 0.1, 0.1) end
    if input.key_down(input.SCANCODE_S) then M.cam_dist = M.cam_dist + 0.1 end

    local cam_x = M.cam_dist * math.cos(M.cam_pitch) * math.sin(M.cam_yaw)
    local cam_y = M.cam_dist * math.sin(M.cam_pitch)
    local cam_z = M.cam_dist * math.cos(M.cam_pitch) * math.cos(M.cam_yaw)
    
    local view = mc.mat4_look_at({cam_x, cam_y, cam_z}, {0, 0, 0}, {0, 1, 0})
    local proj = mc.mat4_perspective(mc.rad(60), sw.extent.width/sw.extent.height, 0.01, 100.0)
    proj.m[5] = -proj.m[5]
    local mvp = mc.mat4_multiply(proj, view)

    vk.vkResetCommandBuffer(cb, 0); vk.vkBeginCommandBuffer(cb, ffi.new("VkCommandBufferBeginInfo", { sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO }))
    
    local bar = ffi.new("VkImageMemoryBarrier[1]", {{ 
        sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, 
        oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED, 
        newLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, 
        image = ffi.cast("VkImage", sw.images[idx]), 
        subresourceRange = { aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount = 1, layerCount = 1 }, 
        dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT 
    }})
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, nil, 0, nil, 1, bar)

    local color_attach = ffi.new("VkRenderingAttachmentInfo[1]")
    color_attach[0].sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO
    color_attach[0].imageView = ffi.cast("VkImageView", sw.views[idx])
    color_attach[0].imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    color_attach[0].loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR
    color_attach[0].storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE
    color_attach[0].clearValue.color.float32 = {0.1, 0.1, 0.12, 1.0}
    
    local depth_attach = ffi.new("VkRenderingAttachmentInfo[1]")
    depth_attach[0].sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO
    depth_attach[0].imageView = depth_img.view
    depth_attach[0].imageLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    depth_attach[0].loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR
    depth_attach[0].storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE
    depth_attach[0].clearValue.depthStencil.depth = 1.0

    local render_info = ffi.new("VkRenderingInfo", { 
        sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO, 
        renderArea = { extent = sw.extent }, 
        layerCount = 1, 
        colorAttachmentCount = 1, 
        pColorAttachments = color_attach, 
        pDepthAttachment = depth_attach 
    })

    vk.vkCmdBeginRendering(cb, render_info)
    vk.vkCmdSetViewport(cb, 0, 1, ffi.new("VkViewport", { width=sw.extent.width, height=sw.extent.height, maxDepth=1 }))
    vk.vkCmdSetScissor(cb, 0, 1, ffi.new("VkRect2D", { extent=sw.extent }))
    vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipe)
    
    local offsets = ffi.new("VkDeviceSize[1]", {0})
    vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {vertex_buffer.handle}), offsets)
    vk.vkCmdPushConstants(cb, pipe_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, mvp.m)
    vk.vkCmdDraw(cb, vertex_count, 1, 0, 0)
    
    vk.vkCmdEndRendering(cb)

    bar[0].oldLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    bar[0].newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    bar[0].srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nil, 0, nil, 1, bar)
    vk.vkEndCommandBuffer(cb)
    
    vk.vkQueueSubmit(queue, 1, ffi.new("VkSubmitInfo", { 
        sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, 
        waitSemaphoreCount = 1, 
        pWaitSemaphores = ffi.new("VkSemaphore[1]", {image_available_sem}), 
        pWaitDstStageMask = ffi.new("VkPipelineStageFlags[1]", {vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}), 
        commandBufferCount = 1, 
        pCommandBuffers = ffi.new("VkCommandBuffer[1]", {cb}), 
        signalSemaphoreCount = 1, 
        pSignalSemaphores = ffi.new("VkSemaphore[1]", {sw.semaphores[idx]}) 
    }), frame_fence)
    sw:present(queue, idx, sw.semaphores[idx])
end

return M
