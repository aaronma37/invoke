# The Moontide KAN Technical Manifest

**Moontide** is a high-performance runtime for Kolmogorov-Arnold Networks (KAN), separating "Silicon" (Zig host) from "The Grid" (Spline state).

## 1. The Spline Kernel (Zig Core)
The core kernel is a **High-Precision Evaluator.**
*   **Vectorized Cox-de Boor:** Evaluating cubic B-splines using **AVX-512** for 16 simultaneous coordinates.
*   **Analytical Backpropagation:** Hardcoded spatial and coefficient gradients for the training loop, eliminating the overhead of dynamic computation graphs.
*   **Silicon Armor:** Enforces memory protection on Spline Grids using `mprotect`.
*   **The Socket (moontide_abi.h):** A permanent C-ABI contract for KAN evaluation and training extensions.

## 2. Eternal Spline Grids (Wires)
State lives on raw, page-aligned memory buffers (Wires) that persist across logic reloads.
*   **Double-Buffer Training:** Grids are "Banks" (Front/Back). Reads come from Front (Model $T$); Updates go to Back (Model $T+1$). The Kernel performs a Pointer Swap after the Adam update step.
*   **Knot Vectors:** Trainable or fixed knot vectors define the resolution and distribution of spline power.
*   **Gather-Scatter Optimized:** Specifically designed to leverage the **AVX-512** path on Zen 5 hardware for non-contiguous coefficient lookups.

## 3. Geometric Logic (KAN Nodes)
Network behavior is isolated into "pluggable" sockets.
*   **The SDF Node:** Predicts a 3D distance field and its spatial gradient ($\nabla SDF$) for Eikonal enforcement.
*   **The Material Node:** Predicts PBR attributes (R, G, B, Roughness, Metallic) with surface-weighted priority.

## 4. Hardware-Aware Concurrency
Moontide is "Silicon-Aware" for the 9950X:
*   **CCD Pinning:** Threads are manually affinity-pinned to specific chiplets to maximize L3 cache hits.
*   **Infinity Fabric Bypass:** Data flow within a KAN (inputs to outputs) is kept local to a CCD whenever possible to eliminate the cross-chiplet latency bottleneck.

## 5. Summary of the KAN Stack
| Aspect | Mechanism |
| :--- | :--- |
| **Continuity** | B-Splines replace discrete weights for infinite resolution. |
| **Performance** | Native AVX-512 "Gather/Scatter" for sparse KAN graphs. |
| **Reliability** | Hardware-level memory protection for every spline coefficient. |
| **Training** | Analytical Eikonal loss and Grid Extension (Upscaling). |

---
*The goal is bit-perfect, deterministic geometric parameterization at the raw speed of the silicon gates.*
