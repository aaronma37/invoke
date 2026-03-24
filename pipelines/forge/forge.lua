local ffi = require("ffi")

-- AUTO-PATH: Resolve MoonCrust library locations
package.path = package.path .. ";./extensions/mooncrust/src/lua/?.lua;./extensions/mooncrust/src/lua/?/init.lua"

-- Helper for running system commands
local function run_cmd(cmd)
    print("Executing: " .. cmd)
    local success = os.execute(cmd)
    if not success then
        print("Error executing command: " .. cmd)
        os.exit(1)
    end
end

-- Simple CLI Argument Parser
local args = {}
for i = 1, #arg do
    local k, v = arg[i]:match("%-%-([^=]+)=(.*)")
    if k then args[k] = v end
end

if not args.definition or not args.name then
    print("Usage: luajit pipelines/forge/forge.lua --definition=path/to/def.lua --name=primitive_name [--epochs=1000] [--samples=100000]")
    os.exit(1)
end

local epochs = args.epochs or "1000"
local samples_count = args.samples or "100000"
print("--- The Forge: Universal Manifold Generator ---")

-- 1. Setup Directories
local model_dir = "projects/manifold_composer/registry/models"
local entry_dir = "projects/manifold_composer/registry/entries"
os.execute("mkdir -p " .. model_dir .. " " .. entry_dir)

local pcb_path = "/tmp/" .. args.name .. "_samples.pcb"
local model_path = model_dir .. "/" .. args.name .. ".kan"
local registry_path = entry_dir .. "/" .. args.name .. ".json"

-- 2. Phase 1: Sampling
print("\n--- Phase 1: Sampling ---")
run_cmd(string.format("luajit pipelines/forge/sampler.lua --definition=%s --output=%s --count=%s", 
    args.definition, pcb_path, samples_count))

-- 3. Phase 2: Training
print("\n--- Phase 2: Training (Zig AVX-512) ---")
-- Format: kan-train <pcb_path> <epochs> <batch_size> <lr> <task> --output <model_path>
run_cmd(string.format("./zig-out/bin/kan-train %s %s 1024 0.001 generic --output %s", 
    pcb_path, epochs, model_path))

-- 4. Phase 3: Registration
print("\n--- Phase 3: Registration ---")
-- Load definition to get metadata
local def = dofile(args.definition)

local json_content = string.format([[
{
  "generator_id": "%s",
  "type": "neural",
  "topology_type": "%s",
  "definition": "%s",
  "topology": "[2, 32, 32, 6]",
  "sockets": {
    "bottom": { "type": "input", "uv_edge": "v=0" },
    "top": { "type": "output", "uv_edge": "v=1" }
  },
  "forge_params": {
    "definition": "%s",
    "epochs": %s,
    "samples": %s,
    "timestamp": "%s"
  }
}
]], args.name, def.topology_type or "open", model_path, args.definition, epochs, samples_count, os.date("!%Y-%m-%dT%H:%M:%SZ"))

local f = io.open(registry_path, "w")
if f then
    f:write(json_content)
    f:close()
    print("Forge Complete! Registered at " .. registry_path)
else
    print("Failed to write registry entry.")
end
