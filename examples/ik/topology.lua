local num_arms = 20
local segments_per_arm = 15

local namespaces = {
  ik = {
    wires = {
      -- The mouse cursor target
      mouse = { schema = "x:f32;y:f32", buffered = false }
    },
    nodes = {
      {
        name = "input_controller",
        type = "luajit",
        script = "examples/ik/target.lua",
        writes = {"mouse"}
      }
    }
  }
}

-- Dynamically generate 20 arms
for i = 1, num_arms do
  local wire_name = "arm_" .. i
  local node_name = "solver_" .. i
  
  -- Each arm has its own segment positions
  namespaces.ik.wires[wire_name] = {
    schema = string.format("x:f32[%d];y:f32[%d];length:f32", segments_per_arm, segments_per_arm),
    buffered = true
  }
  
  -- Each arm has its own solver node instance
  table.insert(namespaces.ik.nodes, {
    name = node_name,
    type = "luajit",
    script = "examples/ik/ik_solver.lua",
    reads = {"mouse"},
    writes = {wire_name}
  })
end

-- Add the final visualizer that reads EVERYTHING
local visualizer_reads = {"mouse"}
for i = 1, num_arms do table.insert(visualizer_reads, "arm_" .. i) end

table.insert(namespaces.ik.nodes, {
  name = "visualizer",
  type = "luajit",
  script = "examples/ik/render.lua",
  reads = visualizer_reads
})

return { namespaces = namespaces }
