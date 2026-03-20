# The Moontide KAN Philosophy

**Moontide** is a fundamental rejection of the "Discrete Matrix" AI world. It is a high-precision, continuous-parameterization engine designed for the era of **Neurosymbolic Geometry.**

## I. The Core: "Silicon Sculpting"
The Moontide Kernel is a **Geometric Compiler.** 
*   **The Shift:** We move from "Weights" to "Curves." Geometry is not a set of vertices; it is a mathematical field stored in the coefficients of B-splines.
*   **Direct Execution:** The CPU does not "simulate" a model; it "executes" geometry. By unrolling the math into branchless polynomials, we turn the 9950X into a dedicated geometric ALU.

## II. The Standard: "Infinite Continuity"
Traditional 3D is "Discrete" (triangles/voxels). Moontide is **"Inherently Continuous."**
*   **Infinite Resolution:** Because the representation is a function $f(X, Y, Z)$, you can query the surface at any level of detail. 
*   **Mathematical Physics:** We enforce Physicality through the **Eikonal Loss.** A Moontide model doesn't just look like a shape; it behaves like a true distance field, with perfect gradients for lighting and physics.

## III. The Workflow: "Evolutionary Training"
Moontide follows the **Multi-Resolution Path.**
*   **Stabilize Coarse:** Learn the basic volumetric silhouette on sparse grids.
*   **Evolve Fine:** Dynamically double grid density (Grid Extension) to capture high-frequency pores, rivets, and fabric weave without retraining.
*   **Sparsify:** Prune unused spline paths to reach the mathematical limit of compression.

## IV. The Concurrency: "Zero-Copy Parallelism"
We reject monolithic training in favor of **Modular KANs.**
*   **Isolated Synthesis:** Each thread works on a subset of the batch with private memory.
*   **Cache Locality:** By keeping models small and batches localized, we ensure the entire training process happens within the 64MB L3 cache of the Zen 5 CCD.

---

## The Core Mantra: Logic is the Spline, Data is the Grid.
In Moontide, the "Vertex" is dead. State lives in the **Spline Grid** (Continuous), and behavior lives in the **Analytical Activation** (Mathematical). This separation enables a scale of geometric precision and data density that discrete-time systems cannot achieve.
