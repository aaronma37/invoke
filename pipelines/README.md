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
The pipeline for building and validating objects out of Neural and Functional Generators.
**Usage:**
```bash
./extensions/mooncrust/build/mooncrust pipelines/assembly/compose.lua --recipe=recipes/tree.json
```
This automatically parses the JSON graph and applies the mathematical welds in memory.

## `pipelines/assembly/export.lua`
The pipeline for compiling a recipe into a seamless, watertight OBJ file.
**Usage:**
```bash
./extensions/mooncrust/build/mooncrust pipelines/assembly/export.lua --recipe=recipes/tree.json --output=my_tree.obj
```
This performs bit-perfect vertex welding to ensure the output is a single continuous manifold.
