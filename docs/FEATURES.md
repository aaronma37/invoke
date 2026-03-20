# Moontide KAN Feature Set

### The "Wins" (Pros)

*   **Vulkan-to-KAN Pipeline:** Seamless flow from raw meshes (Objaverse-XL) to high-performance GPU sampling, then to Zig-optimized training.
*   **16-Core Parallelism:** Fully saturates the 9950X by partitioning training batches across all physical cores with independent gradient buffers.
*   **Analytical Cubic Unrolling:** Massive performance boost by replacing recursive B-spline math with branchless piecewise cubic polynomials.
*   **SoA Optimized Layout:** Contiguous memory layout for spline coefficients, enabling peak ZMM register throughput and eliminating pointer chasing.
*   **Zero-Copy DataLoader:** Memory-maps binary point clouds (`.pcb`) for instant training startup and NVMe-speed data streaming.
*   **Grid Extension (Multi-Res):** Mathematically upscale spline resolution mid-training to capture high-frequency details without losing existing shape.
*   **Eikonal Enforcement:** Built-in second-order analytical loss component that forces valid Signed Distance Fields ($||\nabla SDF|| = 1.0$).
*   **Indestructible Zero-Allocation Loop:** Pre-allocated per-thread scratch buffers ensure zero heap allocations during the heartbeat of the training loop.

---

### The "Future" (Planned)

*   **Sparsification Watchdog:** Automatically detect and prune spline paths that have collapsed to zero, freeing up cycles for complex details.
*   **BF16 Mixed Precision:** Store coefficients in 16-bit Brain Float to double L3 cache capacity while maintaining FP32 math accuracy.
*   **Curvature-Aware Sampling:** Integrate with Mooncrust to automatically sample more points in areas with high geometric complexity.

---

### The "Costs" (Cons)

*   **Memory Footprint:** Each thread requires its own set of scratch buffers (Activations, Jacobians, Gradients) to avoid contention.
*   **Uniform Grid Assumption:** The current unrolled cubic basis assumes uniform knot spacing for maximum speed.
*   **Analytical Complexity:** Adding new activation functions requires deriving and hardcoding the analytical first and second-order gradients.
