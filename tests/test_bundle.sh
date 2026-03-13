#!/bin/bash
set -e

echo "[Test] Starting Moontide Bundle Integration Test..."

# 1. Setup clean test environment
rm -rf test_project
mkdir -p test_project/ext
./zig-out/bin/moontide init
mv topology.lua test_project/

# 2. Build the project to ensure we have binaries
zig build

# 3. Run the bundle command
./zig-out/bin/moontide bundle test_project/topology.lua

# 4. Verify distribution folder
echo "[Test] Verifying 'dist/' structure..."
if [ ! -f dist/moontide ]; then echo "FAILED: Kernel missing"; exit 1; fi
if [ ! -d dist/ext ]; then echo "FAILED: Extension dir missing"; exit 1; fi
if [ ! -f dist/topology.lua ]; then echo "FAILED: Topology missing"; exit 1; fi
if [ ! -f dist/run.sh ]; then echo "FAILED: Run script missing"; exit 1; fi

# 5. Verify run.sh is executable
if [ ! -x dist/run.sh ]; then echo "FAILED: run.sh not executable"; exit 1; fi

echo "[Test] Bundle SUCCESS! Integration verified."
rm -rf test_project
