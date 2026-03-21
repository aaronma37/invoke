# Fully Fused Vulkan KAN Strategy

This document outlines the architectural roadmap for porting the optimized Zig CPU KAN implementation into a fully fused Vulkan Compute kernel. The goal is to achieve 1.0 to 2.0+ Billion Points per Second (GPS) by bypassing traditional VRAM bottlenecks and leveraging advanced GPU hardware features, without disrupting the ongoing Zig development.

## The Core Concept: From "On-The-Fly" to "Precalc + Tensor Core"

Standard PyTorch KANs and your baseline Vulkan shader (`mesher.comp`) interleave the non-linear B-spline math with linear weight accumulation. While this is easy to write, it forces the GPU's standard ALUs to do heavy lifting and prevents the use of dedicated matrix-multiplication hardware. 

The strategy is to mirror the "Basis-Precalc Tiling" architecture currently being perfected in Zig (Phase 9) and map it to specific Vulkan extensions.

---

## Roadmap

### Phase 1: Perfecting the Blueprint in Zig (Current)
Zig serves as the high-fidelity laboratory. It is much easier to debug memory corruption, verify numeric stability, and test gradients on the CPU.
* **Goal:** Finalize the complete separation of B-spline evaluation from the Fused-Multiply-Add (FMA) weight loops in `kan_layer.zig`.
* **Outcome:** A mathematically proven architecture that proves "Pre-calculating bases -> Matrix Math" yields massive throughput gains.

### Phase 2: Vulkan Inference Refactor (The Fast Path)
Once the Zig architecture proves out, we will upgrade the existing Vulkan shaders (`kan_viewer/kan_eval.glsl` and `mesher.comp`) without touching the Zig training code.

1. **Decoupled Workgroup Passes:** 
   Instead of a single thread doing all the math for one point, a workgroup cooperatively calculates the B-spline bases for a tile of points and stores them in **Shared Memory (Workgroup Local Memory)**.
2. **Subgroup Operations (Wave32 / Wave64):**
   Utilize `VK_KHR_shader_subgroup` extensions. Threads within a warp can cooperatively calculate spline bases and share them instantly via `subgroupShuffle` or `subgroupBroadcast`, minimizing register pressure and latency.
3. **Cooperative Matrices (Tensor/Matrix Cores):**
   With the spline math separated into its own block, the weight accumulation is now a pure matrix-vector multiplication. We can pipe this directly into `VK_KHR_cooperative_matrix`, activating NVIDIA Tensor Cores or AMD Matrix Cores. This completely bypasses the standard ALU bottleneck.

### Phase 3: Fully Fused Vulkan Training (The Holy Grail)
Currently, Vulkan is only used for rendering (inference). To make training blazingly fast, we will port the Zig backpropagation logic to the GPU.
* PyTorch writes intermediate activations to VRAM, killing performance.
* Our Vulkan training shader will perform the Forward Pass, hold the intermediate activations in Shared Memory, and immediately execute the Backward Pass within the same shader dispatch.
* This is the exact technique used by NVIDIA's `tiny-cuda-nn` (Instant-NGP), applied to KANs.

---

## Execution Constraints & Safety

To ensure we **do not break the current Zig implementation**:

1. **Isolation:** The Zig `src/core/` remains the source of truth for the primary engine, dataloading, and CPU training. 
2. **Vulkan as an Extension:** The Vulkan KAN evaluator will live entirely inside the existing `projects/kan_viewer/` or as a module in `extensions/mooncrust/`. 
3. **Staged Integration:** 
   * First, we make the Vulkan *renderer* infinitely fast using the new shader architecture.
   * Second, we write a Vulkan *training* compute pipeline that mirrors the Zig CPU trainer.
   * Finally, we allow the Zig orchestrator to hot-swap between the CPU KAN (for compatibility/debugging) and the Vulkan KAN (for raw speed).