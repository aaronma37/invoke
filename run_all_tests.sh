#!/bin/bash
set -e

echo "===================================================="
echo "   MANIFOLD COMPOSER: UNIFIED TEST SUITE (HARDENED)"
echo "===================================================="

# 1. ZIG SILICON TESTS
echo -e "\n[1/3] Running Zig Math & FFI Unit Tests..."
zig build test

# 2. LUA ORCHESTRATION TESTS
echo -e "\n[2/3] Running Lua Orchestration (Graph Compilation)..."
./extensions/mooncrust/build/mooncrust projects/manifold_composer/orchestration_test.lua

# 3. LUA TOPOLOGY & STRESS TESTS
echo -e "\n[3/3] Running Lua Topology & Depth Integrity..."
./extensions/mooncrust/build/mooncrust projects/manifold_composer/topology_integrity_test.lua

# 4. DATA EXHAUSTIVE DIAGNOSTIC
echo -e "\n[BONUS] Running Exhaustive Weld Diagnostic (Bit-Precision)..."
./extensions/mooncrust/build/mooncrust projects/manifold_composer/exhaustive_weld_test.lua

echo -e "\n===================================================="
echo "   ALL SYSTEMS VERIFIED: 100% BIT-PERFECT STACK"
echo "===================================================="
