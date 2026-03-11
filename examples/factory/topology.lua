local common = require("examples/factory/common")
local belt_schema = common.schema

return {
  namespaces = {
    factory = {
      wires = {
        -- Level 0 (Raw Belts)
        iron_ore = { schema = belt_schema, buffered = true },
        copper_ore = { schema = belt_schema, buffered = true },
        coal = { schema = belt_schema, buffered = true },
        
        -- Level 1 (Intermediate Belts)
        iron_ingot = { schema = belt_schema, buffered = true },
        copper_wire = { schema = belt_schema, buffered = true },
        
        -- Level 2 (Final Product Belt)
        circuit = { schema = belt_schema, buffered = true }
      },
      nodes = {
        -- Miners
        { name = "miner_iron", type = "luajit", script = "examples/factory/miner.lua", writes = {"iron_ore"} },
        { name = "miner_copper", type = "luajit", script = "examples/factory/miner.lua", writes = {"copper_ore"} },
        { name = "miner_coal", type = "luajit", script = "examples/factory/miner.lua", writes = {"coal"} },
        
        -- Smelters (Requirement: Ore + Coal, but we simplify to just Ore for now)
        { name = "smelter_iron", type = "luajit", script = "examples/factory/smelter.lua", 
          reads = {input="iron_ore"}, writes = {output="iron_ingot"} },
        { name = "smelter_copper", type = "luajit", script = "examples/factory/smelter.lua", 
          reads = {input="copper_ore"}, writes = {output="copper_wire"} },
          
        -- Assembler (Consumes Iron + Copper to make Circuit Board)
        { name = "assembler_circuits", type = "luajit", script = "examples/factory/assembler.lua",
          reads = {in_a="iron_ingot", in_b="copper_wire"}, writes = {output="circuit"} },
          
        -- Dashboard (The Visualizer)
        { name = "visualizer", type = "luajit", script = "examples/factory/dashboard.lua",
          reads = {"iron_ore", "copper_ore", "coal", "iron_ingot", "copper_wire", "circuit"} }
      }
    }
  }
}
