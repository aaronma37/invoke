local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua;./projects/manifold_composer/ext/?.lua"

local mc = require("mc")
local vk = require("vulkan.ffi")
local pipeline = require("vulkan.pipeline")
local shader = require("vulkan.shader")
local swapchain = require("vulkan.swapchain")
local image = require("vulkan.image")
local command = require("vulkan.command")
local input = require("mc.input")
local bit = require("bit")
local sdl = require("vulkan.sdl")
local loader = require("loader")

local M = { 
    orbit_radius = 5,
    orbit_yaw = 0,
    orbit_pitch = 0.3,
    target_pos = {0, 1, 0},
    last_frame_time = 0
}

local device, queue, sw, graphics_pipe, pipe_layout
local depth_img, vbuf, vertex_count, has_faces
local cbs, image_available_sem, frame_fence

function M.init()
    print("--- Manifold Composer: Hardened Viewer ---")
    
    local instance = vulkan.get_instance()
    local physical_device = vulkan.get_physical_device()
    device = vulkan.get_device()
    local q, family = vulkan.get_queue()
    queue = q
    sw = swapchain.new(instance, physical_device, device, _G._SDL_WINDOW)

    local depth_format = image.find_depth_format(physical_device)
    depth_img = mc.gpu.image(sw.extent.width, sw.extent.height, depth_format, "depth")

    -- 1. Load the Generated OBJ
    local mesh_path = "output.obj"
    local v_data, v_count, faces_present = loader.load(mesh_path)
    vertex_count = v_count
    has_faces = faces_present
    vbuf = mc.gpu.buffer(vertex_count * 9 * 4, "vertex", v_data, true)

    -- 2. Debug Shaders (Clamped Heatmap)
    local v_src = [[
#version 450
layout(location = 0) in vec3 inPos;
layout(location = 1) in vec3 inNormal;
layout(push_constant) uniform PC { mat4 vp; } pc;
layout(location = 0) out float z_val;
layout(location = 1) out vec3 normal;
void main() {
    gl_Position = pc.vp * vec4(inPos, 1.0);
    gl_PointSize = 4.0;
    z_val = inPos.z;
    normal = inNormal;
}
]]
    local f_src = [[
#version 450
layout(location = 0) in float z_val;
layout(location = 1) in vec3 normal;
layout(location = 0) out vec4 outColor;
void main() {
    vec3 light = normalize(vec3(1.0, 1.0, 1.0));
    float diff = max(dot(normalize(normal), light), 0.3);
    vec3 base = vec3(0.0, 0.8, 1.0); // Neon Blue
    if (z_val > 0.98 && z_val < 1.02) base = vec3(1.0, 0.2, 0.0); // Red weld marker
    outColor = vec4(base * diff, 1.0);
}
]]

    -- 3. Pipeline
    pipe_layout = pipeline.create_layout(device, {}, { { stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, offset = 0, size = 64 } })
    graphics_pipe = pipeline.create_graphics_pipeline(device, pipe_layout, 
        shader.create_module(device, shader.compile_glsl(v_src, vk.VK_SHADER_STAGE_VERTEX_BIT)),
        shader.create_module(device, shader.compile_glsl(f_src, vk.VK_SHADER_STAGE_FRAGMENT_BIT)), { 
        vertex_binding = ffi.new("VkVertexInputBindingDescription[1]", {{ binding = 0, stride = 9 * 4, inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX }}),
        vertex_attributes = ffi.new("VkVertexInputAttributeDescription[2]", {
            { location = 0, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 0 },
            { location = 1, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 3 * 4 }
        }),
        vertex_attribute_count = 2, depth_test = true, depth_write = true, depth_format = depth_format,
        topology = has_faces and vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST or vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
        cull_mode = vk.VK_CULL_MODE_NONE
    })

    cbs = command.allocate_buffers(device, command.create_pool(device, family), sw.image_count)
    frame_fence = ffi.new("VkFence[1]"); vk.vkCreateFence(device, ffi.new("VkFenceCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, flags=vk.VK_FENCE_CREATE_SIGNALED_BIT}), nil, frame_fence); frame_fence = frame_fence[0]
    image_available_sem = ffi.new("VkSemaphore[1]"); vk.vkCreateSemaphore(device, ffi.new("VkSemaphoreCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO}), nil, image_available_sem); image_available_sem = image_available_sem[0]
    M.last_frame_time = tonumber(sdl.SDL_GetTicks())
end

function M.update()
    vk.vkWaitForFences(device, 1, ffi.new("VkFence[1]", {frame_fence}), vk.VK_TRUE, 0xFFFFFFFFFFFFFFFFULL)
    vk.vkResetFences(device, 1, ffi.new("VkFence[1]", {frame_fence}))
    local idx = sw:acquire_next_image(image_available_sem)
    if idx == nil then return end

    -- Camera Logic
    if _G._MOUSE_L then
        local dx, dy = input.mouse_delta()
        M.orbit_yaw, M.orbit_pitch = M.orbit_yaw - dx * 0.01, math.max(-math.pi/2+0.1, math.min(math.pi/2-0.1, M.orbit_pitch + dy * 0.01))
    end
    local cam_x = M.target_pos[1] + math.sin(M.orbit_yaw) * math.cos(M.orbit_pitch) * M.orbit_radius
    local cam_y = M.target_pos[2] + math.sin(M.orbit_pitch) * M.orbit_radius
    local cam_z = M.target_pos[3] + math.cos(M.orbit_yaw) * math.cos(M.orbit_pitch) * M.orbit_radius
    local view = mc.mat4_look_at({cam_x, cam_y, cam_z}, M.target_pos, {0, 1, 0})
    local proj = mc.mat4_perspective(mc.rad(60), sw.extent.width/sw.extent.height, 0.1, 100.0)
    local vp = mc.mat4_multiply(proj, view)

    local cb = cbs[idx+1]
    vk.vkResetCommandBuffer(cb, 0); vk.vkBeginCommandBuffer(cb, ffi.new("VkCommandBufferBeginInfo", { sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO }))

    local barriers = ffi.new("VkImageMemoryBarrier[2]")
    barriers[0].sType, barriers[0].oldLayout, barriers[0].newLayout = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    barriers[0].image, barriers[0].subresourceRange = ffi.cast("VkImage", sw.images[idx]), { aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount = 1, layerCount = 1 }
    barriers[0].dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    barriers[1].sType, barriers[1].oldLayout, barriers[1].newLayout = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    barriers[1].image, barriers[1].subresourceRange = depth_img.handle, { aspectMask = vk.VK_IMAGE_ASPECT_DEPTH_BIT, levelCount = 1, layerCount = 1 }
    barriers[1].dstAccessMask = bit.bor(vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT, vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT)
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, bit.bor(vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT), 0, 0, nil, 0, nil, 2, barriers)

    local color_attach = ffi.new("VkRenderingAttachmentInfo[1]")
    color_attach[0].sType, color_attach[0].imageView, color_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, ffi.cast("VkImageView", sw.views[idx]), vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    color_attach[0].loadOp, color_attach[0].storeOp, color_attach[0].clearValue.color.float32 = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, vk.VK_ATTACHMENT_STORE_OP_STORE, {0.02, 0.02, 0.05, 1.0}
    local depth_attach = ffi.new("VkRenderingAttachmentInfo[1]")
    depth_attach[0].sType, depth_attach[0].imageView, depth_attach[0].imageLayout = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, depth_img.view, vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    depth_attach[0].loadOp, depth_attach[0].storeOp, depth_attach[0].clearValue.depthStencil.depth = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, vk.VK_ATTACHMENT_STORE_OP_STORE, 1.0
    
    vk.vkCmdBeginRendering(cb, ffi.new("VkRenderingInfo", { sType=vk.VK_STRUCTURE_TYPE_RENDERING_INFO, renderArea={extent=sw.extent}, layerCount=1, colorAttachmentCount=1, pColorAttachments=color_attach, pDepthAttachment=depth_attach }))
    vk.vkCmdSetViewport(cb, 0, 1, ffi.new("VkViewport", { x=0, y=0, width=sw.extent.width, height=sw.extent.height, minDepth=0, maxDepth=1 }))
    vk.vkCmdSetScissor(cb, 0, 1, ffi.new("VkRect2D", { extent=sw.extent }))
    vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipe)
    
    vk.vkCmdPushConstants(cb, pipe_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, vp.m)
    vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {vbuf.handle}), ffi.new("VkDeviceSize[1]", {0}))
    vk.vkCmdDraw(cb, vertex_count, 1, 0, 0)
    
    vk.vkCmdEndRendering(cb)

    local present_bar = ffi.new("VkImageMemoryBarrier[1]", {{ sType=vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, oldLayout=vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, newLayout=vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, image=ffi.cast("VkImage", sw.images[idx]), subresourceRange={ aspectMask=vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount=1, layerCount=1 }, srcAccessMask=vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT, dstAccessMask=0 }})
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nil, 0, nil, 1, present_bar)
    vk.vkEndCommandBuffer(cb)
    vk.vkQueueSubmit(queue, 1, ffi.new("VkSubmitInfo", { sType=vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, waitSemaphoreCount = 1, pWaitSemaphores = ffi.new("VkSemaphore[1]", {image_available_sem}), pWaitDstStageMask = ffi.new("VkPipelineStageFlags[1]", {vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}), commandBufferCount = 1, pCommandBuffers = ffi.new("VkCommandBuffer[1]", {cb}), signalSemaphoreCount = 1, pSignalSemaphores = ffi.new("VkSemaphore[1]", {sw.semaphores[idx]}) }), frame_fence)
    sw:present(queue, idx, sw.semaphores[idx])
end

return M
