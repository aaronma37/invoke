local common = require("examples/ants/common")
local num_ants = 200

local namespaces = {
  multiverse = {
    wires = {
      -- Shared grid
      grid = { schema = common.grid_schema, buffered = true }
    },
    nodes = {
      { name = "visualizer", type = "luajit", script = "examples/ants/render.lua", reads = {"grid"} }
    }
  }
}

-- Spawn 200 parallel ants
for i = 1, num_ants do
  local state_wire = "ant_state_" .. i
  local node_name = "ant_" .. i
  
  namespaces.multiverse.wires[state_wire] = { schema = common.ant_schema, buffered = false }
  
  table.insert(namespaces.multiverse.nodes, {
    name = node_name,
    type = "luajit",
    script = "examples/ants/ant.lua",
    reads = {past="grid", state=state_wire},
    writes = {future="grid", state=state_wire}
  })
end

return { namespaces = namespaces }
