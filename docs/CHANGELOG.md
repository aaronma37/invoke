# Moontide Changelog

## [v0.9.0] - The "Geometric Pivot" (CURRENT FOCUS)
*“Beyond the Pulse: The Continuous Revolution.”*

### 🚀 Major Architectural Shifts
1.  **Total Pivot to KAN:** Abandoned Spiking Neural Networks (SNN) and Liquid State Machines (LSM). Moontide is now a high-performance Kolmogorov-Arnold Network (KAN) trainer.
2.  **AVX-512 B-Spline Kernel:** Implemented the Cox-de Boor algorithm in Zig, enabling 16-way SIMD evaluation of cubic splines.
3.  **Analytical Backpropagation:** Hardcoded the derivative of B-splines w.r.t coefficients and inputs for zero-allocation training loops.
4.  **Eikonal Enforcement:** Added a dedicated loss module to enforce $||\nabla SDF|| = 1.0$, ensuring mathematically perfect distance fields.
5.  **Multi-Resolution Scaling:** Implemented "Grid Extension" to dynamically upscale spline resolution during training.

---

## [v0.8.0] - The "Deep Water" Update (DEPRECATED)
*“Beyond the Single Host: Global Scaling.”*

### 🚀 Planned Architectural Shifts (Cancelled in favor of v0.9.0)
1.  **"Tide-Pool" Network Extension:** A dedicated I/O socket that manages thousands of concurrent connections and pours packets into Ring Buffer Wires.
2.  **Level Journaling (Persistence):** Background streaming of Wire back-buffers to persistent storage without blocking the Heartbeat.

---

## [v0.7.0] - The Moontide Shift (COMPLETED)
*“Identity, Reliability, and Silicon Armor.”*

### 🚀 Major Architectural Shifts
1.  **Total Rebrand:** Transitioned from "Invoke" to "Moontide," embracing the cosmic rhythm of Double-Buffering.
2.  **Guard Pages (Silicon Armor):** Implemented hardware-level overflow protection by placing PROT_NONE pages between every wire.
3.  **Deterministic Scheduling:** Hardened the DAG builder to strictly enforce write-exclusivity, ensuring bit-perfect parallelism.
4.  **Global SDK Installation:** Added `moontide sdk install` to distribute Moontide as a system-wide platform.
5.  **Circular Dependency Detection:** The Kernel now identifies and rejects impossible Task Graphs.
6.  **Schema Evolution v2:** Added integrity checks to trigger evolution when the schema string changes, even if size remains constant.

---

## [v0.6.0] - The "Nervous System" Update (COMPLETED)
... (rest of history unchanged)
