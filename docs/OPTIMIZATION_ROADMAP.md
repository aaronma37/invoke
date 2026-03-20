# Moontide KAN: Optimization Roadmap (9950X Edition)

This document outlines the architectural path to achieving maximum throughput for KAN training on Zen 5 (AMD 9950X) hardware.

## Performance Comparison (Estimated)

| Phase | Implementation | Est. Speedup (vs. PyTorch) | Strategy |
| :--- | :--- | :--- | :--- |
| **Phase 1** | PyTorch (Baseline) | **1.0x** | Generic Autograd / Python Overhead |
| **Phase 2** | **Current Moontide (Zig)** | **15x - 20x** | **AVX-512 (16-wide)** + Analytical Backprop |
| **Phase 3** | **SoA Refactor** | **40x - 60x** | Contiguous Cache Lines + Shared Knot Vectors |
| **Phase 4** | **Multi-Threading** | **400x - 600x** | **16 Cores** Data-Parallel Scaling |
| **Phase 5** | **Cubic Unrolling** | **800x - 1000x** | Branchless Polynomials (Zero-Recursion) |
| **Phase 6** | **BF16 / FP16** | **1200x+** | 32-wide SIMD + Zen 5 Dot-Product Path |

---

## The Roadmap

### Phase 3: Structure of Arrays (SoA) Refactor
*   **The Move:** Transition from a `[]SplineGrid` (pointers to random memory) to a single, flat, 64-byte aligned `[]f32` buffer for an entire layer's coefficients.
*   **The Gain:** Eliminates "Pointer Chasing." The CPU can stream coefficients directly into ZMM registers using aligned loads instead of expensive gathers.

### Phase 4: Multi-Threaded Orchestration
*   **The Move:** Split the training batch across all 16 physical cores of the 9950X using a "Fork-Join" or "Work-Stealing" model.
*   **The Gain:** Linear scaling for the forward and backward passes. Zen 5's high-bandwidth L3 cache ensures all threads can access the model coefficients without bottlenecking.

### Phase 5: Analytical Cubic Unrolling
*   **The Move:** Replace the recursive Cox-de Boor algorithm with hardcoded, piecewise cubic polynomial evaluations ($ax^3 + bx^2 + cx + d$).
*   **The Gain:** Zero branches. This prevents branch mispredictions and allows the CPU's out-of-order execution engine to reach peak IPC (Instructions Per Cycle).

### Phase 6: Low-Precision Training (BF16)
*   **The Move:** Quantize the training loop to use Brain Float 16.
*   **The Gain:** Doubles SIMD width (32 values per 512-bit register) and halves the memory footprint, keeping even massive KANs entirely within the 64MB L3 cache.

---

## Hardware Targets (AMD Ryzen 9 9950X)
*   **AVX-512:** Full-width 512-bit ALUs for 16-32 way parallelism.
*   **L3 Cache (64MB):** Keeping the "Liquid" state local to the CCD.
*   **SMT (Simultaneous Multi-Threading):** 32 logical threads for high-throughput batch processing.
