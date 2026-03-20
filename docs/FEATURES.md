# Moontide KAN Feature Set

### The "Wins" (Pros)

*   **Continuous Geometric Infinity (B-Splines):** No more triangles or voxels. Represent 3D volumes as continuous mathematical fields. Query the distance at any scale with perfect smoothness.
*   **Indestructible Simulation (Silicon Armor):** If a specific KAN node crashes or attempts a memory violation, the engine catches it and continues the training pass. One bad spline won't kill the whole trainer.
*   **Data That Never Dies (Eternal Grid):** Your spline coefficients are stored separately from your logic. You can rewrite your entire activation system mid-execution, and your model's shape will stay exactly where it was.
*   **Hardware-Level Security (Gating):** The engine uses your CPU's hardware (`mprotect`) to enforce "who can touch what." This catches sneaky bugs where one system accidentally overwrites another's coefficients.
*   **Grid Extension (Resolution Upscaling):** Need more detail on an armor plate? Mathematically double the spline grid density, and the engine will automatically interpolate your existing data to the new structure while training is running.
*   **Multi-Channel PBR (Surface Priority):** Train SDF, Color, Roughness, and Metallic simultaneously. The engine automatically focuses "learning power" on the surface ($SDF \approx 0$) where it matters most.
*   **Parallel Safety Switch (Double-Buffering):** Safely use all 16 cores of your 9950X for training without ever worrying about race conditions. Nodes read from stable "Front" grids and write updates to "Back" grids.
*   **Eikonal Enforcement:** A built-in loss component that forces the network to learn a mathematically valid Signed Distance Field, ensuring your real-time lighting and rendering work perfectly.

---

### The "Future" (Planned)

*   **Sparsity Watchdog:** Automatically detect and prune logic paths that have collapsed to zero, freeing up CPU cycles for more complex parts of the model.
*   **Curvature-Aware Sampling:** Automatically sample more points in areas with high geometric curvature (e.g., sharp corners, intricate details).
*   **Vulkan Inference Export:** One-click packaging of a trained KAN into a specialized compute shader for real-time Dual Contouring on the GPU.

---

### The "Costs" (Cons)

*   **Memory Cost:** To make training 100% safe and deterministic, the engine uses 2x the memory for coefficients (Front and Back banks).
*   **Topology Definition:** You have to define a "Topology" (a simple JSON/Lua map) that tells the engine how your inputs ($X, Y, Z, Latent$) connect to your spline edges.
*   **Analytical Complexity:** Writing custom activation functions requires hand-deriving the analytical gradient to maintain Moontide's performance edge.
*   **Fixed Domain Size:** Because splines are defined on a grid, you generally have to decide the bounding box of your geometry before you start training.
