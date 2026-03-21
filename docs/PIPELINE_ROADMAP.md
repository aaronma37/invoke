# Moontide KAN: Geometric Compiler Roadmap

The end-to-end neurosymbolic pipeline for 3D body parts and armor.

## Current Status (Certified)
1.  **Vulkan SDF Sampler (Mooncrust):** GPU-accelerated point-to-mesh distance calculation.
2.  **Zero-Copy DataLoader:** `mmap`-based binary streaming of point samples.
3.  **16-Core AVX-512 KAN Trainer:** Branchless analytical splines with analytical backprop.

---

## Final Pieces of the Puzzle

### 1. Grid Extension (The Multi-Resolution "Secret Sauce")
*   **Goal:** Coarse-to-Fine training. Start with a 5-point grid for the basic silhouette and mathematically double it to 20+ points for pores, rivets, and fabric weave.
*   **Mechanism:** Knot insertion algorithm that preserves the existing curve during upscaling.

### 2. Sparsification & Pruning (The "Geometric Compressor")
*   **Goal:** Absolute minimum mathematical complexity for real-time inference.
*   **Mechanism:** L1 Regularization on spline coefficients + automatic edge pruning. Any spline path that collapses to zero is deleted from the topology.

### 4. UV Distillation Pipeline (The "Asset Maker")
*   **Goal:** Generate clothing, armor, and body variations that perfectly rig and animate with a standard Base Human Mesh.
*   **Mechanism:** Instead of learning an SDF (which has no topology), the engine distills complex target geometry into a simple UV Displacement map.
    1.  **The Base:** Start with a standard, unwrapped Base Human `.obj`.
    2.  **The Target:** Generate a complex, messy, un-rigged target mesh using TripoSR, Tripo3D, or Objaverse.
    3.  **The Distillation:** The Vulkan Sampler (`uv_sampler.zig`) fires rays from the Base Human's vertices to the Target Mesh, recording the displacement distances into a `.pcb` file.
    4.  **The Model:** A KAN is trained to map `(u, v)` coordinates to the required displacement.
*   **Result:** You can instantly apply a thousand different KAN-generated outfits to a single rigged character in a game engine, with sliders and LoRAs controlling the style.

---

## Performance Targets
*   **Sampling:** < 100ms per high-poly object (100k triangles).
*   **Training:** < 10 seconds per body part (500k samples).
*   **Inference:** < 1ms per million points (Vulkan Dual Contouring).
