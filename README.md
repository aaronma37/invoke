# Moontide: The KAN Geometric Compiler

**Stop training pixels. Start compiling geometry.**

Moontide is a high-performance, **AVX-512 optimized** training engine for **Kolmogorov-Arnold Networks (KAN)**. It is specifically designed to parameterize **Signed Distance Fields (SDF)** and **PBR Materials** into continuous mathematical splines, enabling a neurosymbolic pipeline for ultra-efficient 3D asset generation and real-time inference.

---

## 🧠 The Singular Vision
Moontide rejects the "Dense Matrix" paradigm of traditional MLPs. Instead, it treats the CPU as a high-precision **Spline Sculptor**. By placing trainable B-splines directly on the network edges, we enable a **Continuous Geometric Representation** that captures high-frequency details (pores, rivets, fabric) with a fraction of the parameters required by standard neural networks.

---

## 💎 Core Architectural Pillars

### 1. AVX-512 Spline Kernel (Zen 5 Optimized)
Moontide is built from the ground up to exploit the **AMD Ryzen 9950X (Zen 5)** architecture.
*   **Vectorized B-Splines:** Native Zig implementation of the Cox-de Boor algorithm, evaluating 16+ spline points simultaneously in 512-bit ZMM registers.
*   **L3 Cache Locality:** Segmented KAN training ensures the entire model (spline coefficients and knot vectors) stays within the 64MB L3 cache, bypassing the memory bandwidth bottleneck.
*   **Analytical Gradients:** Hardcoded, zero-allocation backpropagation for B-splines, providing 10x the throughput of general-purpose Autodiff engines like PyTorch.

### 2. Composite SDF Loss (Eikonal Enforcement)
Training a KAN for geometry requires more than just MSE. Moontide enforces mathematical "Physicality."
*   **Eikonal Loss:** Penalizes the network if the spatial gradient ($\nabla SDF$) deviates from 1.0, ensuring a mathematically perfect distance field for lighting and physics.
*   **Material Decay:** Exponentially weighted loss for R, G, B, Roughness, and Metallic channels, focusing spline capacity only on the surface ($SDF \approx 0$).

### 3. Grid Extension (Resolution Scaling)
Moontide enables **Multi-Resolution Training**.
*   **Coarse-to-Fine:** Start with a sparse 5-point grid for "blobby" silhouettes and mathematically upscale to 20+ points for high-frequency micro-details without losing the original shape.
*   **Spline Interpolation:** Perfect mathematical continuity during grid expansion—no "catastrophic forgetting" or retraining from scratch.

### 4. Sparsification & Pruning (Geometric Compression)
Prepare your models for real-time GPU inference.
*   **L1 Regularization:** Forces unnecessary spline coefficients to exactly zero.
*   **Edge Pruning:** Automatically strips dead paths from the network topology, exporting a minimal binary blob for Vulkan/CUDA dual-contouring engines.

---

## 🏁 Technical Edge (Why AMD?)
Moontide is a "Silicon-Aware" engine:
*   **AVX-512 Gather/Scatter:** Blistering fast lookup of non-contiguous spline control points.
*   **CCD Pinning:** Keeping the training threads local to a single chiplet to eliminate cross-CCD latency.

---

## 🚀 Getting Started

### 1. Build and Install
```bash
zig build
sudo ./zig-out/bin/moontide sdk install
```

### 2. Run the SDF Training Demo
```bash
# Train a KAN to represent a 3D segmented arm model
moontide train examples/kan/arm_sdf.lua
```

---
*Logic is the Spline, Data is the Grid. The Moontide is Continuous.*
