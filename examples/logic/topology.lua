return {
  namespaces = {
    breadboard = {
      wires = {
        -- External Inputs
        a = "val:i32",
        b = "val:i32",
        cin = "val:i32",
        -- External Outputs
        sum = "val:i32",
        cout = "val:i32",
        -- Internal Traces (Temporary signals)
        xor1_out = "val:i32",
        and1_out = "val:i32",
        and2_out = "val:i32"
      },
      nodes = {
        { name = "clock", type = "luajit", script = "examples/logic/input.lua", writes = {"a", "b", "cin"} },
        
        -- The Circuit
        { name = "xor1", type = "luajit", script = "examples/logic/xor.lua", reads = {in1="a", in2="b"}, writes = {out="xor1_out"} },
        { name = "xor2", type = "luajit", script = "examples/logic/xor.lua", reads = {in1="xor1_out", in2="cin"}, writes = {out="sum"} },
        
        { name = "and1", type = "luajit", script = "examples/logic/and.lua", reads = {in1="a", in2="b"}, writes = {out="and1_out"} },
        { name = "and2", type = "luajit", script = "examples/logic/and.lua", reads = {in1="xor1_out", in2="cin"}, writes = {out="and2_out"} },
        
        { name = "or1",  type = "luajit", script = "examples/logic/or.lua",  reads = {in1="and1_out", in2="and2_out"}, writes = {out="cout"} },

        -- The UI
        { name = "visualizer", type = "luajit", script = "examples/logic/display.lua", reads = {"a", "b", "cin", "sum", "cout"} }
      }
    }
  }
}
