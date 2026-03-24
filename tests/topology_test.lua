return {
  namespaces = {
    test_ns = {
      wires = {
        test_wire = "x:f32;y:f32",
      },
      nodes = {
        {
          name = "test_node",
          type = "luajit",
          mode = "Heartbeat",
          script = "tests/test_script.lua",
          reads = {},
          writes = {"test_wire"}
        }
      }
    }
  }
}
