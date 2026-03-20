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

### 3. Objaverse-XL CLI (The "Asset Factory")
*   **Goal:** Automated massive-scale training.
*   **Mechanism:** A command-line tool that orchestrates:
    *   Downloading a mesh from Objaverse-XL.
    *   Invoking Mooncrust for GPU sampling.
    *   Invoking Moontide for 9950X-optimized KAN training.
    *   Exporting the trained `.kan` binary for the GPU renderer.

---

## Performance Targets
*   **Sampling:** < 100ms per high-poly object (100k triangles).
*   **Training:** < 10 seconds per body part (500k samples).
*   **Inference:** < 1ms per million points (Vulkan Dual Contouring).
