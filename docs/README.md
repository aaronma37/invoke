# Manifold Composer: Constructive Neurosymbolic Geometry

**Manifold Composer** is a high-precision geometric generation engine that treats Kolmogorov-Arnold Networks (KAN) as **Primitive Generators**. 

Instead of generating static meshes, the engine allows an **LLM Orchestrator** to compose complex, topologically diverse shapes by wiring together continuous mathematical functions.

## 1. Core Vision: The "Generator Registry"
We reject the idea of a library of static assets. Instead:
1.  **The Forge:** An offline training pipeline that produces **Neural Generators** (trained KANs) for organic or complex geometry.
2.  **Functional Generators:** Pure mathematical functions (Lua/GLSL) for precise geometric primitives, which can be pre-defined or generated on-the-fly by the LLM.
3.  **The Registry:** A catalog of both Neural and Functional generators.
4.  **The Composer:** A runtime engine that "Welds" these generators using **Boundary Pinning**, regardless of whether they are neural or functional.

## 2. Key Technology: Boundary Pinning
The "Secret Sauce" of this project. Because our KAN generators use **B-splines**, they possess **Local Support**. This allows us to "pin" the boundaries of one generator to the output of another without distorting the generator's internal learned logic.
*   **Watertight Manifolds:** Perfectly continuous transitions between modular components.
*   **Infinite Resolution:** Geometry can be evaluated at any density on-the-fly.

## 3. High-Level Architecture
*   **The Architect (LLM):** Symbolic reasoning to handle Out-Of-Distribution (OOD) structural generation.
*   **The Registry:** Metadata defining the mathematical capabilities of available generators.
*   **The Composer (Zig/Lua):** High-performance execution of the generator graph.
*   **The Forge:** Automated data generation and KAN training pipeline.
