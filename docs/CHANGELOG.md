# Moontide Changelog

## [v0.9.5] - The "Geometric Compiler" Update (CURRENT)
*“The End-to-End Geometric Revolution.”*

### 🚀 Major Architectural Shifts
1.  **16-Core Parallel Trainer:** Fully multi-threaded `trainStep` using direct thread spawning and pre-allocated buffers for zero-contention gradient accumulation.
2.  **Vulkan GPU Sampler (Mooncrust):** Integrated GPU-accelerated mesh-to-SDF sampling, processing 100k+ points in < 1ms.
3.  **Analytical Cubic Unrolling (Phase 5):** Replaced recursive B-spline math with branchless piecewise cubic polynomials for massive performance gains.
4.  **Structure of Arrays (SoA) Refactor:** Flattened memory layout for coefficients and shared knot vectors, optimized for AVX-512 streaming.
5.  **Grid Extension (Multi-Res):** Implemented identity-preserving knot interpolation to upscale KAN resolution mid-training.
6.  **Zero-Copy DataLoader:** Added `mmap`-based binary loader for streaming `.pcb` datasets at NVMe speeds.

---

## [v0.9.0] - The "Geometric Pivot" (COMPLETED)
1.  **Total Pivot to KAN:** Abandoned Spiking Neural Networks (SNN) and Liquid State Machines (LSM).
2.  **AVX-512 B-Spline Kernel:** Initial Cox-de Boor implementation in Zig.
3.  **Analytical Backpropagation:** First-order and second-order (Eikonal) gradient implementation.

---

## [v0.7.0] - The Moontide Shift (LEGACY)
... (rest of history unchanged)
