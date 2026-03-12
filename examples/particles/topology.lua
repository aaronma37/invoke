return {
  namespaces = {
    world = {
      wires = {
        -- 1000 particles: each has pos(x,y) and vel(vx,vy)
        particles = {
          schema = "count:i32;x:f32[1000];y:f32[1000];vx:f32[1000];vy:f32[1000]",
          buffered = true
        }
      },
      nodes = {
        {
          name = "sim",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/particles/sim.lua",
          reads = {"particles"},
          writes = {"particles"}
        },
        {
          name = "view",
          type = "hud",
          mode = "Heartbeat",
          script = "none",
          reads = {"particles"}
        }
      }
    }
  }
}
