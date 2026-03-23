local ffi = require("ffi")
local vk = require("vulkan.ffi")
local pipeline = require("vulkan.pipeline")
local descriptors = require("vulkan.descriptors")
local shader = require("vulkan.shader")
local swapchain = require("vulkan.swapchain")
local image = require("vulkan.image")
local command = require("vulkan.command")
package.path = package.path .. ";projects/vroid_vae_viewer/?.lua;projects/uv_sampler_gpu/?.lua;extensions/mooncrust/?.lua"
local loader = require("loader")
local input = require("mc.input")
local sdl = require("vulkan.sdl")
local imgui = require("imgui")

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end

-- --- ZIG BRIDGE FFI ---
ffi.cdef[[
    void* moontide_load_model(const char* path);
    void moontide_free_model(void* net);
    void moontide_eval_vae(void* net, uint32_t num_points, const float* uvs, const float* latents, float* outputs);

    typedef struct {
        float px, py, pz;
        float nx, ny, nz;
        float cr, cg, cb;
    } VaeVertex;

    typedef struct {
        float u, v, z_zero, sdf, r, g, b, roughness, metallic;
    } PointSample;
]]

local zig = ffi.load("zig-out/lib/libmoontide_core.so")
local kan_net = nil

local M = { 
    cam_dist = 3.0,
    cam_yaw = 0,
    cam_pitch = 0.5,
    target = {0, 0.8, 0},
    latents = ffi.new("float[16]"),
    update_morph = true
}

local device, queue, sw, render_layout, graphics_pipe
local base_vbuf, uv_pairs, morph_vbuf, morph_results
local v_data_cpu, base_v_data_cpu
local vertex_count, depth_img
local cb, image_available_sem, frame_fence

function M.init()
    _G.IMGUI_LIB_PATH = "/home/aaron-ma/invoke/projects/imgui/build/mooncrust_imgui.so"
    local model_path = _ARGS[2] or "artifacts/models/vroid_vae_100.kan"
    local base_obj = "artifacts/raw/vroid_batch/vroid_0000.obj"
    local pcb_path = "artifacts/datasets/vroid_batch_pcb/vroid_0000.pcb"
    
    print("--- VRoid VAE Viewer (Zig Core Bridge) ---")
    
    -- 1. Load KAN via Zig
    kan_net = zig.moontide_load_model(model_path)
    if kan_net == nil then error("Failed to load KAN model via Zig bridge") end
    print("Zig Core: Model loaded successfully.")

    device = vulkan.get_device()
    local physical_device = vulkan.get_physical_device()
    local q, family = vulkan.get_queue()
    queue = q
    sw = swapchain.new(vulkan.get_instance(), physical_device, device, _G._SDL_WINDOW)

    pcall(imgui.init)

    -- 2. Load Base Mesh
    local raw_verts = loader.load(base_obj)
    vertex_count = #raw_verts
    
    v_data_cpu = ffi.new("VaeVertex[?]", vertex_count)
    base_v_data_cpu = ffi.new("VaeVertex[?]", vertex_count)
    uv_pairs = ffi.new("float[?]", vertex_count * 2)
    morph_results = ffi.new("float[?]", vertex_count * 3)

    -- Load UVs from PCB
    local f_pcb = io.open(pcb_path, "rb")
    local pcb_raw = f_pcb:read("*all")
    f_pcb:close()
    local pcb_data = ffi.cast("PointSample*", pcb_raw)

    for i=1, vertex_count do
        local v = raw_verts[i]
        local pcb_v = pcb_data[i-1]
        
        -- Store Base
        base_v_data_cpu[i-1].px, base_v_data_cpu[i-1].py, base_v_data_cpu[i-1].pz = v.pos[1], v.pos[2], v.pos[3]
        base_v_data_cpu[i-1].nx, base_v_data_cpu[i-1].ny, base_v_data_cpu[i-1].nz = v.normal[1], v.normal[2], v.normal[3]
        base_v_data_cpu[i-1].cr, base_v_data_cpu[i-1].cg, base_v_data_cpu[i-1].cb = 0.8, 0.8, 0.8
        
        -- Store UV Pairs for Zig
        uv_pairs[(i-1)*2 + 0] = pcb_v.u
        uv_pairs[(i-1)*2 + 1] = pcb_v.v
        
        -- Initialize Working Data
        v_data_cpu[i-1] = base_v_data_cpu[i-1]
    end
    
    morph_vbuf = mc.buffer(ffi.sizeof(v_data_cpu), "vertex", v_data_cpu)

    -- 3. Graphics Pipeline
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
        depth_test = true, depth_write = true, depth_format = depth_format,
        color_formats = { sw.format }
    })

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

    imgui.new_frame()
    imgui.gui.igBegin("VAE Controls (Zig Core)", nil, 0)
    imgui.gui.igText("Using moontide_core.so FFI")
    
    local function slider(label, l_idx, min, max)
        if imgui.gui.igSliderFloat(label, M.latents + l_idx, min, max, "%.3f", 0) then
            M.update_morph = true
        end
    end

    slider("Waist/Hip", 0, -1, 1)
    slider("Shoulder", 1, -1, 1)
    slider("Chest Depth", 2, -1, 1)
    slider("Arm Length", 3, 0, 1.5)
    slider("Bust Size", 4, 0, 1.5)
    
    imgui.gui.igEnd()

    -- Morph via Zig if needed
    if M.update_morph then
        -- 1. Call Zig AVX-512 Core
        zig.moontide_eval_vae(kan_net, vertex_count, uv_pairs, M.latents, morph_results)
        
        -- 2. Apply deltas to local CPU buffer
        for i=0, vertex_count-1 do
            v_data_cpu[i].px = base_v_data_cpu[i].px + morph_results[i*3 + 0]
            v_data_cpu[i].py = base_v_data_cpu[i].py + morph_results[i*3 + 1]
            v_data_cpu[i].pz = base_v_data_cpu[i].pz + morph_results[i*3 + 2]
        end
        
        -- 3. Upload to GPU
        morph_vbuf:upload(v_data_cpu)
        M.update_morph = false
    end

    -- Orbit
    local rot_speed = 0.03
    if input.key_down(input.SCANCODE_LEFT) then M.cam_yaw = M.cam_yaw - rot_speed end
    if input.key_down(input.SCANCODE_RIGHT) then M.cam_yaw = M.cam_yaw + rot_speed end
    if input.key_down(input.SCANCODE_UP) then M.cam_pitch = math.min(M.cam_pitch + rot_speed, 1.5) end
    if input.key_down(input.SCANCODE_DOWN) then M.cam_pitch = math.max(M.cam_pitch - rot_speed, -1.5) end
    if input.key_down(input.SCANCODE_W) then M.cam_dist = math.max(M.cam_dist - 0.1, 0.1) end
    if input.key_down(input.SCANCODE_S) then M.cam_dist = M.cam_dist + 0.1 end

    local cam_x = M.target[1] + M.cam_dist * math.cos(M.cam_pitch) * math.sin(M.cam_yaw)
    local cam_y = M.target[2] + M.cam_dist * math.sin(M.cam_pitch)
    local cam_z = M.target[3] + M.cam_dist * math.cos(M.cam_pitch) * math.cos(M.cam_yaw)
    local view = mc.mat4_look_at({cam_x, cam_y, cam_z}, {M.target[1], M.target[2], M.target[3]}, {0, 1, 0})
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
    vk.vkCmdBindVertexBuffers(cb, 0, 1, ffi.new("VkBuffer[1]", {morph_vbuf.handle}), ffi.new("VkDeviceSize[1]", {0}))
    vk.vkCmdPushConstants(cb, render_layout, vk.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, mvp.m)
    vk.vkCmdDraw(cb, vertex_count, 1, 0, 0)
    
    imgui.render(cb)
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
