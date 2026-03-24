local ffi = require("ffi")

-- AUTO-PATH
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua;./projects/manifold_composer/?.lua"

local mc = require("mc")
local vk = require("vulkan.ffi")
local pipeline = require("vulkan.pipeline")
local descriptors = require("vulkan.descriptors")
local shader = require("vulkan.shader")
local swapchain = require("vulkan.swapchain")
local command = require("vulkan.command")
local Composer = require("composer")

-- --- FFI API ---
local lib = ffi.load("ext/libmanifold_ext.so")
ffi.cdef[[
    typedef void* ManifoldNetwork_t;
    ManifoldNetwork_t manifold_init(const size_t* layer_dims, size_t num_layers, size_t num_coeffs);
    void manifold_deinit(ManifoldNetwork_t handle);
    void manifold_set_socket(ManifoldNetwork_t handle, uint32_t socket_type, const float* points, size_t num_points);
    void manifold_forward_pinned(ManifoldNetwork_t handle, const float* inputs, float** activations, float* outputs, size_t batch_size);
    float* manifold_get_coeffs(ManifoldNetwork_t handle);
]]

-- 1. Hardcoded Registry
local registry = {
    gen_cylinder_v1 = {
        generator_id = "gen_cylinder_v1",
        type = "functional",
        topology = "[2, 32, 32, 6]"
    }
}

-- 2. Vulkan Setup
local instance, physical_device = vulkan.get_instance(), vulkan.get_physical_device()
local device; local queue, graphics_family = vulkan.get_queue()
device = vulkan.get_device()
local sw = swapchain.new(instance, physical_device, device, _G._SDL_WINDOW)

-- 3. Pipelines
local v_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/manifold_composer/shaders/manifold.vert"):read("*a"), vk.VK_SHADER_STAGE_VERTEX_BIT))
local f_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/manifold_composer/shaders/manifold.frag"):read("*a"), vk.VK_SHADER_STAGE_FRAGMENT_BIT))
local c_mod = shader.create_module(device, shader.compile_glsl(io.open("projects/manifold_composer/shaders/mesher.comp"):read("*a"), vk.VK_SHADER_STAGE_COMPUTE_BIT))

local comp_ds_layout = descriptors.create_layout(device, {
    { binding = 0, type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages = vk.VK_SHADER_STAGE_COMPUTE_BIT },
    { binding = 1, type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, stages = vk.VK_SHADER_STAGE_COMPUTE_BIT },
})
local comp_layout = pipeline.create_layout(device, {comp_ds_layout}, ffi.new("VkPushConstantRange[1]", {{ stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT, offset = 0, size = 12 }}))
local comp_pipe = pipeline.create_compute_pipeline(device, comp_layout, c_mod)

local gfx_layout = pipeline.create_layout(device, {}, ffi.new("VkPushConstantRange[1]", {{ stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT, offset = 0, size = 64 }}))
local v_bind = ffi.new("VkVertexInputBindingDescription[1]", {{ binding = 0, stride = 12, inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX }})
local v_attr = ffi.new("VkVertexInputAttributeDescription[1]", {{ location = 0, binding = 0, format = vk.VK_FORMAT_R32G32B32_SFLOAT, offset = 0 }})
local gfx_pipe = pipeline.create_graphics_pipeline(device, gfx_layout, v_mod, f_mod, {
    depth_test = true, depth_write = true, color_formats = {sw.format},
    vertex_binding = v_bind, vertex_attributes = v_attr, vertex_attribute_count = 1,
    topology = vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST
})

-- 4. Graph & Buffers
local graph = Composer.new("recipes/simple_pipe.json", registry)
local res = 64
local total_verts = #graph.nodes * res * res
local gpu_v_buffer = mc.gpu.buffer(total_verts * 12, "vertex")
local ds_pool = descriptors.create_pool(device, {{ type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, count = #graph.nodes * 2 }})
local node_sets = {}

for i, node in ipairs(graph.nodes) do
    local coeffs = lib.manifold_get_coeffs(node.handle)
    local coeff_buf = mc.gpu.buffer(32 * 32 * 3 * 4, "storage", coeffs, true)
    local set = descriptors.allocate_sets(device, ds_pool, {comp_ds_layout})[1]
    descriptors.update_buffer_set(device, set, 0, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, coeff_buf.handle, 0, vk.VK_WHOLE_SIZE, 0)
    descriptors.update_buffer_set(device, set, 1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, gpu_v_buffer.handle, (i-1) * res * res * 12, res * res * 12, 0)
    node_sets[i] = set
end

-- 5. Loop
local cb = command.allocate_buffers(device, command.create_pool(device, graphics_family), 1)[1]
local img_ready = ffi.new("VkSemaphore[1]")
vk.vkCreateSemaphore(device, ffi.new("VkSemaphoreCreateInfo", {sType=vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO}), nil, img_ready)
img_ready = img_ready[0]

local rot = 0
while true do
    local idx = sw:acquire_next_image(img_ready)
    if not idx then break end
    rot = rot + 0.01
    
    local vp = mc.math.mat4_multiply(mc.math.mat4_perspective(mc.math.rad(60), sw.extent.width/sw.extent.height, 0.1, 100), mc.math.mat4_look_at({math.sin(rot)*5, 2, math.cos(rot)*5}, {0,0.5,0}, {0,1,0}))

    vk.vkResetCommandBuffer(cb, 0)
    vk.vkBeginCommandBuffer(cb, ffi.new("VkCommandBufferBeginInfo", { sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO }))

    vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, comp_pipe)
    for i = 1, #graph.nodes do
        local pc = ffi.new("struct { uint32_t u, v, res; }", 32, 32, res)
        vk.vkCmdPushConstants(cb, comp_layout, vk.VK_SHADER_STAGE_COMPUTE_BIT, 0, 12, pc)
        vk.vkCmdBindDescriptorSets(cb, vk.VK_PIPELINE_BIND_POINT_COMPUTE, comp_layout, 0, 1, ffi.new("VkDescriptorSet[1]", {node_sets[i]}), 0, nil)
        vk.vkCmdDispatch(cb, res/16, res/16, 1)
    end

    local bar_v = ffi.new("VkBufferMemoryBarrier[1]", {{ sType=vk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER, srcAccessMask=vk.VK_ACCESS_SHADER_WRITE_BIT, dstAccessMask=vk.VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT, buffer=gpu_v_buffer.handle, offset=0, size=vk.VK_WHOLE_SIZE }})
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, 0, 0, nil, 1, bar_v, 0, nil)

    local bar_i = ffi.new("VkImageMemoryBarrier[1]", {{ sType=vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, oldLayout=vk.VK_IMAGE_LAYOUT_UNDEFINED, newLayout=vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, image=ffi.cast("VkImage", sw.images[idx]), subresourceRange={aspectMask=vk.VK_IMAGE_ASPECT_COLOR_BIT, levelCount=1, layerCount=1}, srcAccessMask=0, dstAccessMask=vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT }})
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, 0, 0, nil, 0, nil, 1, bar_i)

    local color_at = ffi.new("VkRenderingAttachmentInfo[1]", {{ sType=vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO, imageView=ffi.cast("VkImageView", sw.views[idx]), imageLayout=vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, loadOp=vk.VK_ATTACHMENT_LOAD_OP_CLEAR, storeOp=vk.VK_ATTACHMENT_STORE_OP_STORE, clearValue={color={float32={0.05,0.05,0.1,1}}} }})
    vk.vkCmdBeginRendering(cb, ffi.new("VkRenderingInfo", { sType=vk.VK_STRUCTURE_TYPE_RENDERING_INFO, renderArea={extent=sw.extent}, layerCount=1, colorAttachmentCount=1, pColorAttachments=color_at }))
    vk.vkCmdBindPipeline(cb, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, gfx_pipe)
    vk.vkCmdSetViewport(cb, 0, 1, ffi.new("VkViewport", { x=0, y=0, width=sw.extent.width, height=sw.extent.height, minDepth=0, maxDepth=1 }))
    vk.vkCmdSetScissor(cb, 0, 1, ffi.new("VkRect2D", { offset={0,0}, extent=sw.extent }))
    vk.vkCmdPushConstants(cb, gfx_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, vp.m)
    vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {gpu_v_buffer.handle}), ffi.new("VkDeviceSize[1]", {0}))
    vk.vkCmdDraw(cb, total_verts, 1, 0, 0)
    vk.vkCmdEndRendering(cb)

    bar_i[0].oldLayout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    bar_i[0].newLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    bar_i[0].srcAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
    bar_i[0].dstAccessMask = 0
    vk.vkCmdPipelineBarrier(cb, vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nil, 0, nil, 1, bar_i)

    vk.vkEndCommandBuffer(cb)
    vk.vkQueueSubmit(queue, 1, ffi.new("VkSubmitInfo", { sType=vk.VK_STRUCTURE_TYPE_SUBMIT_INFO, waitSemaphoreCount=1, pWaitSemaphores=ffi.new("VkSemaphore[1]", {img_ready}), pWaitDstStageMask=ffi.new("VkPipelineStageFlags[1]", {vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT}), commandBufferCount=1, pCommandBuffers=ffi.new("VkCommandBuffer[1]", {cb}), signalSemaphoreCount=1, pSignalSemaphores=ffi.new("VkSemaphore[1]", {sw.semaphores[idx]}) }), nil)
    sw:present(queue, idx, sw.semaphores[idx])
    mc.tick()
end
graph:destroy()
mc.shutdown()
