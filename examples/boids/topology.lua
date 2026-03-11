return {
  namespaces = {
    swarm = {
      wires = {
        boids_north = "count:i32;px:f32[1000];py:f32[1000];vx:f32[1000];vy:f32[1000]",
        boids_south = "count:i32;px:f32[1000];py:f32[1000];vx:f32[1000];vy:f32[1000]"
      },
      nodes = {
        {
          name = "physics_north",
          type = "wasm",
          mode = "Heartbeat",
          script = "examples/boids/boids.wasm",
          reads = {"boids_north"},
          writes = {"boids_north"}
        },
        {
          name = "physics_south",
          type = "wasm",
          mode = "Heartbeat",
          script = "examples/boids/boids.wasm",
          reads = {"boids_south"},
          writes = {"boids_south"}
        },
        {
          name = "reconciler",
          type = "luajit",
          mode = "Heartbeat",
          script = "examples/boids/reconciler.lua",
          reads = {"boids_north", "boids_south"},
          writes = {"boids_north", "boids_south"}
        }
      }
    },
    debug = {
      wires = {},
      nodes = {
        {
          name = "visualizer",
          type = "hud",
          mode = "Heartbeat",
          script = "none"
        }
      }
    }
  }
}
