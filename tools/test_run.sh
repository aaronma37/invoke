#!/bin/bash
set -e

# 1. Download Test Model (Stanford Bunny)
if [ ! -f "bunny.obj" ] || grep -q "404" bunny.obj; then
    echo "Downloading Stanford Bunny OBJ..."
    curl -L https://raw.githubusercontent.com/alecjacobson/common-3d-test-models/master/bunny.obj -o bunny.obj
fi

# 2. Run Mooncrust GPU Sampler
echo "Running Mooncrust GPU Sampler..."
cd extensions/mooncrust
SDL_VIDEODRIVER=offscreen timeout 15s ./build/mooncrust examples/54_objaverse_sampler ../../bunny.obj ../../bunny_sample.pcb
cd ../..

# 3. Run Moontide KAN Trainer (using a new test script)
echo "Running Moontide KAN Trainer on sampled data..."
# We'll use the benchmark test as a template for a training run
zig test -O ReleaseFast src/core/benchmark_test.zig --test-filter "Objaverse Real-World Train"
