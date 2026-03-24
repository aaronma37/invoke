# Universal Pipelines (LuaJIT)

This directory contains the universal execution pipelines for the Manifold Composer. These scripts abstract away the underlying bash/zig/c++ commands into simple, declarative interfaces for the LLM.

## `pipelines/forge/forge.lua`
The pipeline for creating new **Neural Generators** (KANs) from mathematical definitions.
**Usage:**
```bash
luajit pipelines/forge/forge.lua --definition=definitions/cylinder.lua --name=gen_cylinder_v1
```
This automatically:
1. Samples the mathematical definition into a point cloud.
2. Trains a high-speed KAN.
3. Adds the resulting `.kan` file and its metadata to the **Primitive Generator Registry**.

## `pipelines/assembly/compose.lua`
The pipeline for building objects out of Neural and Functional Generators.
**Usage:**
```bash
luajit pipelines/assembly/compose.lua --recipe=recipes/tree.json
```
This automatically:
1. Parses the JSON graph.
2. Looks up the generators in the registry.
3. Calculates the mathematical boundary pins (Welds).
4. Evaluates the full mesh for rendering or export.
