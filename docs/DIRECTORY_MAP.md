# Directory Map: Manifold Composer

To maintain high architectural focus, this branch follows a strict directory convention.

## **1. The Core Engine (Silicon)**
*   `src/core/`: The AVX-512 KAN kernels and math primitives.
    *   `tensor_spline.zig`: The 2D Tensor Product Surface logic.
    *   `kan_layer.zig`: Highly optimized spline edge evaluators.
*   `src/tools/`: Production-grade Silicon tools.
    *   `kan-train`: The high-performance training executable.
    *   `manifold-to-obj`: The bit-perfect OBJ mesher.

## **2. The Orchestrator (Logic)**
*   `projects/manifold_composer/`: The active development workspace.
    *   `composer.lua`: The primary Graph Compiler class.
    *   `viewer.lua`: The Vulkan real-time visualizer.
*   `pipelines/`: Universal execution scripts.
    *   `forge/`: Scripts for sampling and training new generators.
    *   `assembly/`: Scripts for building objects from recipes.

## **3. The Metadata (Symbolic)**
*   `definitions/`: Mathematical shape ideals (Lua).
*   `recipes/`: Structural graph schemas (JSON).
*   `registry/`: The catalog of available Primitive Generators.

## **4. The Bridge (FFI)**
*   `sdk/`: C headers for FFI communication.
*   `ext/`: Compiled shared libraries (`.so`).
*   `extensions/mooncrust/`: The Vulkan + LuaJIT runtime environment.

## **5. Verification (Safety)**
*   `run_all_tests.sh`: The master test orchestrator.
*   `projects/manifold_composer/*_test.*`: Layer-specific unit and integrity tests.
