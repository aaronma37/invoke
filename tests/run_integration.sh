#!/bin/bash
set -e

echo "[Integration] Building Moontide..."
zig build

echo "[Integration] Running Moontide with topology_test.lua..."
# Start Moontide in background
./zig-out/bin/moontide run tests/topology_test.lua > test_run.log 2>&1 &
MOONTIDE_PID=$!

# Wait for it to start
sleep 1

echo "[Integration] Checking for initial ticks..."
if grep -q "Test Node Ticked!" test_run.log; then
    echo "[Integration] SUCCESS: Initial ticks found."
else
    echo "[Integration] FAILURE: Initial ticks not found."
    kill $MOONTIDE_PID
    cat test_run.log
    exit 1
fi

echo "[Integration] Testing HOT-RELOAD..."
# Modify the script to print something else
sed -i 's/Test Node Ticked!/Node HOT-RELOADED!/' tests/test_script.lua

# Wait for hot-reload to trigger
sleep 1

if grep -q "Node HOT-RELOADED!" test_run.log; then
    echo "[Integration] SUCCESS: Hot-reload detected."
else
    echo "[Integration] FAILURE: Hot-reload not detected."
    kill $MOONTIDE_PID
    # Restore script for next run
    sed -i 's/Node HOT-RELOADED!/Test Node Ticked!/' tests/test_script.lua
    cat test_run.log
    exit 1
fi

# Restore script
sed -i 's/Node HOT-RELOADED!/Test Node Ticked!/' tests/test_script.lua

echo "[Integration] Testing TOXIC TOPOLOGY (Syntax Error)..."
# Inject a syntax error into the topology
sed -i 's/namespaces/namespace_error/' tests/topology_test.lua

sleep 1

if grep -q "Failed to reload topology" test_run.log; then
    echo "[Integration] SUCCESS: Kernel rejected the toxic topology."
else
    echo "[Integration] FAILURE: Kernel did not report error for toxic topology."
    kill $MOONTIDE_PID
    sed -i 's/namespace_error/namespaces/' tests/topology_test.lua
    cat test_run.log
    exit 1
fi

# Restore topology
sed -i 's/namespace_error/namespaces/' tests/topology_test.lua
sleep 1

# Verify it's still ticking
if grep -q "Test Node Ticked!" test_run.log; then
    echo "[Integration] SUCCESS: Kernel recovered and is still ticking."
else
    echo "[Integration] FAILURE: Kernel stopped ticking after toxic event."
    kill $MOONTIDE_PID
    cat test_run.log
    exit 1
fi

kill $MOONTIDE_PID
echo "[Integration] Integration tests (Hot-Reload + Resilience) PASSED!"
rm test_run.log
