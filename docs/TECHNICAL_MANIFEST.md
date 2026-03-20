# The Moontide KAN Technical Manifest

**Moontide** is a high-performance runtime for Kolmogorov-Arnold Networks (KAN), separating "Silicon" (Zig host) from "The Grid" (Spline state).

## 1. The Spline Kernel (Zig Core)
The core kernel is a **High-Precision Analytical Evaluator.**
*   **Vectorized SoA:** Evaluating 16 different spline edges simultaneously for a single input using **AVX-512**.
*   **Analytical Cubic Unrolling:** Cubic B-splines are implemented as branchless piecewise polynomials, eliminating recursion overhead.
*   **Analytical Backpropagation:** Hardcoded spatial and coefficient gradients, providing 100x the throughput of dynamic graphs.
*   **Silicon Armor:** Enforces memory protection on Spline Grids using hardware gating.

## 2. Global Spline Grids (SoA)
State lives on raw, page-aligned memory buffers optimized for Zen 5 streaming.
*   **Shared Knot Vectors:** Every spline in a layer shares a single knot vector, maximizing L3 cache efficiency.
*   **Contiguous Coefficients:** Packed flat in memory `[in_dim][num_coeffs][out_dim]` for aligned SIMD loads.
*   **Zero-Copy DataLoader:** High-speed `mmap` interface for binary point sample streaming.

## 3. Parallel Training Pipeline
*   **16-Core Data Parallelism:** The trainer partitions batches across all physical cores of the 9950X.
*   **Per-Thread State:** Pre-allocated scratch buffers (Activations, Jacobians, Gradients) eliminate allocator locks.
*   **Atomic-Free Accumulation:** Threads write to private gradient buffers; a single reduction pass is performed before the Adam update.

## 4. Hardware-Aware Concurrency
Moontide is "Silicon-Aware" for the 9950X:
*   **CCD Pinning:** Threads are kept local to a CCD whenever possible to minimize Infinity Fabric latency.
*   **Peak IPC:** Branchless math and SoA layout allow the CPU to reach theoretical peak instructions per cycle for geometric modeling.

## 5. Summary of the KAN Stack
| Aspect | Mechanism |
| :--- | :--- |
| **Continuity** | Analytical Cubic B-Splines for infinite geometric resolution. |
| **Sampling** | Vulkan-based GPU sampler for milliseconds-per-object ground truth. |
| **Training** | Multi-threaded AVX-512 backprop with analytical Eikonal enforcement. |
| **Scaling** | Multi-resolution Grid Extension for coarse-to-fine detail capture. |

---
*The goal is bit-perfect, deterministic geometric parameterization at the raw speed of the silicon gates.*
