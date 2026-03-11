local num_trees = 8
local batch_size = 20000

local namespaces = {
  rf = {
    wires = {
      batch = { schema = string.format("x:f32[%d];y:f32[%d]", batch_size, batch_size), buffered = true },
      final_pred = { schema = string.format("class:i32[%d]", batch_size), buffered = true }
    },
    nodes = {
      { name = "scanner", type = "luajit", script = "examples/forest/scanner.lua", writes = {"batch"} },
    }
  }
}

for i = 1, num_trees do
  namespaces.rf.wires["pred_" .. i] = { schema = string.format("class:i32[%d]", batch_size), buffered = true }
  table.insert(namespaces.rf.nodes, {
    name = "tree_" .. i,
    type = "luajit",
    script = "examples/forest/tree.lua",
    reads = {"batch"},
    writes = {"pred_" .. i}
  })
end

local ensemble_reads = {}
for i = 1, num_trees do table.insert(ensemble_reads, "pred_" .. i) end
table.insert(namespaces.rf.nodes, {
  name = "ensemble",
  type = "luajit",
  script = "examples/forest/ensemble.lua",
  reads = ensemble_reads,
  writes = {"final_pred"}
})

table.insert(namespaces.rf.nodes, {
  name = "visualizer",
  type = "luajit",
  script = "examples/forest/visualizer.lua",
  reads = {"batch", "final_pred"}
})

return { namespaces = namespaces }
