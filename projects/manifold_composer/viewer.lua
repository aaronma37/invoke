local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua;./projects/manifold_composer/ext/?.lua"

local mc = require("mc")
local vk = require("vulkan.ffi")
local pipeline = require("vulkan.pipeline")
local descriptors = require("vulkan.descriptors")
local shader = require("vulkan.shader")
local swapchain = require("vulkan.swapchain")
local command = require("vulkan.command")
local loader = require("loader")

-- --- VULKAN SETUP ---
local instance, physical_device = vulkan.get_instance(), vulkan.get_physical_device()
local device; local queue, graphics_family = vulkan.get_queue()
device = vulkan.get_device()
local sw = swapchain.new(instance, physical_device, device, _G._SDL_WINDOW)

-- 1. Load the Generated OBJ
local mesh_path = "output.obj"
local v_data, vertex_count, has_faces = loader.load(mesh_path)
local v_buffer = mc.gpu.buffer(vertex_count * 9 * 4, "vertex", v_data, true)

-- 2. Shaders
local v_code = io.open("extensions/mooncrust/examples/43_forward_plus/shaders/forward.vert"):read("*a")
-- Minimal fragment shader to avoid clustered lighting dependencies
local f_code = [[
#version 450
layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec2 inUV;
layout(location = 0) out vec4 outColor;
void main() {
    vec3 lightDir = normalize(vec3(1.0, 1.0, 1.0));
    float diff = max(dot(inNormal, lightDir), 0.2);
    outColor = vec4(vec3(0.0, 0.8, 1.0) * diff, 1.0);
}
]]

local v_mod = shader.create_module(device, shader.compile_glsl(v_code, vk.VK_SHADER_STAGE_VERTEX_BIT))
local f_mod = shader.create_module(device, shader.compile_glsl(f_code, vk.VK_SHADER_STAGE_FRAGMENT_BIT))

-- 3. Pipeline
local layout = pipeline.create_layout(device, {}, ffi.new("VkPushConstantRange[1]", {{
    stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, offset = 0, size = 128 -- Push Constant Space
}}))

local v_binding = ffi.new("VkVertexInputBindingDescription[1]", {{ binding = 0, stride = 9 * 4, inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX }})
local v_attribs = ffi.new("VkVertexInputAttributeDescription[3]", {
    { location = 0, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 0 },
    { location = 1, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 3 * 4 },
    { location = 2, binding = 0, format = vk.VK_FORMAT_R32G32_SFLOAT, offset = 6 * 4 }
})

local pipe = pipeline.create_graphics_pipeline(device, layout, v_mod, f_mod, {
    depth_test = true, depth_write = true, color_formats = {sw.format},
    vertex_binding = v_binding, vertex_attributes = v_attribs, vertex_attribute_count = 3,
    topology = has_faces and vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST or vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST
})

-- 4. Context
local cb = command.allocate_buffers(device, command.create_pool(device, graphics_family), 1)[1]
local img_ready = ffi.new("VkSemaphore[1]")
vk.vkCreateSemaphore(device, ffi.new("VkSemaphoreCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO}), nil, img_ready)
img_ready = img_ready[0]

-- Push Constant Struct (Matches forward.vert)
ffi.cdef[[
    typedef struct {
        float view_proj[16];
        float view[16];
        float cam_pos[4];
        float screen_size[2];
        float z_near, z_far;
        uint32_t c_x, c_y, c_z;
        uint32_t albedo_idx;
    } ViewPC;
]]

local rot = 0
print("--- Manifold Viewer: Start Loop ---")
while true do
    local idx = sw:acquire_next_image(img_ready)
    if not idx then break end
    rot = rot + 0.01
    
    local proj = mc.math.mat4_perspective(mc.math.rad(60), sw.extent.width / sw.extent.height, 0.1, 100.0)
    local view = mc.math.mat4_look_at({math.sin(rot)*3, 1.5, math.cos(rot)*3}, {0, 0.5, 0}, {0, 1, 0})
    local vp = mc.math.mat4_multiply(proj, view)

    local pc = ffi.new("ViewPC")
    ffi.copy(pc.view_proj, vp.m, 64)
    ffi.copy(pc.view, view.m, 64)

    vk.vkResetCommandBuffer(cb, 0)
    vk.vkBeginCommandBuffer(cb, ffi.new("VkCommandBufferBeginInfo", { sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO }))

    local barrier = ffi.new("VkImageMemoryBarrier[1]", {{
        sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED, newLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        image = ffi.cast("VkImage", sw.images[idx]), subresourceRange = { aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount = 1, layerCount = 1 },
        srcAccessMask = 0, dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    }})
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, nil, 0, nil, 1, barrier)

    local color_at = ffi.new("VkRenderingAttachmentInfo[1]", {{
        sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, imageView = ffi.cast("VkImageView", sw.views[idx]), imageLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR, storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE, clearValue = {color={float32={0.05, 0.05, 0.1, 1.0}}}
    }})
    vk.vkCmdBeginRendering(cb, ffi.new("VkRenderingInfo", { sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO, renderArea = { extent = sw.extent }, layerCount = 1, colorAttachmentCount = 1, pColorAttachments = color_at }))
    
    vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipe)
    vk.vkCmdSetViewport(cb, 0, 1, ffi.new("VkViewport", { x = 0, y = 0, width = sw.extent.width, height = sw.extent.height, minDepth = 0, maxDepth = 1 }))
    vk.vkCmdSetScissor(cb, 0, 1, ffi.new("VkRect2D", { offset = {0,0}, extent = sw.extent }))
    
    vk.vkCmdPushConstants(cb, layout, bit.bor(vk.VK_SHADER_STAGE_VERTEX_BIT, vk.VK_SHADER_STAGE_FRAGMENT_BIT), 0, 128, pc)
    vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {v_buffer.handle}), ffi.new("VkDeviceSize[1]", {0}))
    vk.vkCmdDraw(cb, vertex_count, 1, 0, 0)
    
    vk.vkCmdEndRendering(cb)

    barrier[0].oldLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    barrier[0].newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    barrier[0].srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    barrier[0].dstAccessMask = 0
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nil, 0, nil, 1, barrier)

    vk.vkEndCommandBuffer(cb)
    vk.vkQueueSubmit(queue, 1, ffi.new("VkSubmitInfo", { sType=vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, waitSemaphoreCount=1, pWaitSemaphores=ffi.new("VkSemaphore[1]", {img_ready}), pWaitDstStageMask=ffi.new("VkPipelineStageFlags[1]", {vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}), commandBufferCount=1, pCommandBuffers=ffi.new("VkCommandBuffer[1]", {cb}), signalSemaphoreCount = 1, pSignalSemaphores=ffi.new("VkSemaphore[1]", {sw.semaphores[idx]}) }), nil)
    sw:present(queue, idx, sw.semaphores[idx])
    
    mc.tick()
end
mc.shutdown()
