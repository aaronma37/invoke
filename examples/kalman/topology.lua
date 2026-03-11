return {
  namespaces = {
    kalman = {
      wires = {
        raw_signal = {
          -- true_x: ground truth, measured: noisy input
          schema = "true_x:f32;measured:f32;t:f32",
          buffered = true
        },
        filtered_signal = {
          schema = "value:f32",
          buffered = true
        },
        state = {
          -- P: covariance, Q: process noise, R: measurement noise, K: gain
          schema = "p:f32;q:f32;r:f32;k:f32",
          buffered = false
        }
      },
      nodes = {
        {
          name = "sensor",
          type = "luajit",
          script = "examples/kalman/sensor.lua",
          writes = {"raw_signal"}
        },
        {
          name = "filter",
          type = "luajit",
          script = "examples/kalman/filter.lua",
          reads = {"raw_signal", "state"},
          writes = {"filtered_signal", "state"}
        },
        {
          name = "visualizer",
          type = "luajit",
          script = "examples/kalman/plot.lua",
          reads = {"raw_signal", "filtered_signal"}
        }
      }
    }
  }
}
