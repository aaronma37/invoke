# Manifold Composer: Constructive Neurosymbolic Geometry

**Manifold Composer** is a high-precision **Geometric Compiler** that treats Kolmogorov-Arnold Networks (KAN) as **Primitive Generators**. 

Instead of generating static meshes, the engine allows an **LLM Orchestrator** to compose complex, topologically diverse shapes by wiring together continuous mathematical functions.

## 1. Core Vision: The "Generator Registry"
We reject the idea of a library of static assets. Instead:
1.  **The Forge:** An offline training pipeline that produces **Neural Generators** (trained KANs) for organic or complex geometry.
2.  **Functional Generators:** Pure mathematical functions (Lua/GLSL) for precise geometric primitives, which can be pre-defined or generated on-the-fly by the LLM.
3.  **The Registry:** A catalog of both Neural and Functional generators.
4.  **The Composer:** A runtime engine that "Welds" these generators using **Boundary Pinning**, regardless of whether they are neural or functional.

## 2. Key Technology: Boundary Pinning
The "Secret Sauce" of this project. Because our KAN generators use **B-splines**, they possess **Local Support**. This allows us to "pin" the boundaries of one generator to the output of another without distorting the generator's internal learned logic.
*   **Watertight Manifolds:** Bit-perfect, 100% continuous transitions between modular components.
*   **Coefficient Welding:** We weld at the mathematical level, not just snapping vertices.
*   **Infinite Resolution:** Geometry can be evaluated at any density on-the-fly.

## 3. Project Status: HARDENED
As of March 2026, the entire stack is **100% Verified**:
*   [x] **Silicon Math:** AVX-512 kernels verified bit-perfect.
*   [x] **FFI Bridge:** Robust Zig-to-LuaJIT communication.
*   [x] **Orchestration:** Recursive graph compilation and world transforms verified.
*   [x] **Weld Integrity:** 10-level deep chains verified with zero coordinate drift.

## 4. Quick Start
To verify the stack and see the "First Light" pipe:
```bash
# 1. Compile the Silicon Core
zig build install

# 2. Run the Unified Test Suite (100% pass required)
./run_all_tests.sh

# 3. Assemble and Visualize the Test Pipe
./extensions/mooncrust/build/mooncrust projects/manifold_composer/export_pipe.lua
./extensions/mooncrust/build/mooncrust projects/manifold_composer/viewer.lua
```

## 5. High-Level Architecture
*   **Silicon (Zig):** High-performance AVX-512 B-spline kernels and training engine.
*   **Logic (LuaJIT):** Orchestration, Graph compilation, and FFI bridging.
*   **The Grid (Vulkan):** Real-time visualization using MoonCrust.
*   **The Architect (LLM):** Generates JSON recipes to build OOD structures.
