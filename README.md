# Moontide: The KAN Geometric Compiler

**Stop training pixels. Start compiling geometry.**

Moontide is a high-performance, **AVX-512 optimized** end-to-end pipeline for training **Kolmogorov-Arnold Networks (KAN)**. It is specifically designed to parameterize **Signed Distance Fields (SDF)** and **PBR Materials** into continuous mathematical splines, enabling a neurosymbolic pipeline for ultra-efficient 3D asset generation and real-time inference.

---

## 🧠 The End-to-End Pipeline
Moontide is no longer just a trainer; it is a full geometric production factory:
1.  **Vulkan Sampler (Mooncrust):** GPU-accelerated mesh-to-SDF sampling (100k+ points in milliseconds).
2.  **Zero-Copy DataLoader:** `mmap`-based binary streaming of point samples at NVMe speeds.
3.  **16-Core AVX-512 Trainer:** Hardcoded analytical backpropagation using branchless cubic splines.
4.  **Multi-Resolution Scaling:** "Grid Extension" logic to upscale resolution mid-training without losing shape.

---

## 💎 Core Architectural Pillars

### 1. 16-Core SIMD Orchestrator (9950X Optimized)
Moontide is built to saturate the **AMD Ryzen 9950X (Zen 5)**.
*   **Data Parallelism:** Batches are partitioned across 16 physical cores with zero allocator contention.
*   **Structure of Arrays (SoA):** Memory layout optimized for 512-bit ZMM register streaming and L3 cache locality.
*   **Analytical Cubic Unrolling:** Recursive math replaced with branchless piecewise polynomials for peak IPC.

### 2. Composite SDF Loss (Eikonal Enforcement)
*   **Analytical Eikonal Loss:** Enforces $||\nabla SDF|| = 1.0$ using second-order analytical derivatives.
*   **Material Surface Priority:** Exponentially weighted loss for R, G, B, Roughness, and Metallic channels ($SDF \approx 0$).

### 3. Grid Extension (Resolution Scaling)
*   **Coarse-to-Fine:** Start with a sparse 4-point grid for "blobby" silhouettes and mathematically upscale to 32+ points for micro-details.
*   **Identity Preservation:** Knot insertion algorithm ensures no "catastrophic forgetting" during resolution jumps.

---

## 🚀 Getting Started

### 1. Initialize Submodules (Mooncrust)
```bash
git submodule update --init --recursive
```

### 2. Generate Ground Truth (GPU)
```bash
cd extensions/mooncrust
SDL_VIDEODRIVER=offscreen ./build/mooncrust examples/54_objaverse_sampler
```

### 3. Train the KAN (CPU)
```bash
# Run the certified benchmark/test suite
zig test src/core/kan_trainer.zig
```

---
*Logic is the Spline, Data is the Grid. The Moontide is Continuous.*
