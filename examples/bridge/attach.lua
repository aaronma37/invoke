local ffi = require("ffi")

-- 1. Define the Moontide Host ABI
ffi.cdef[[
    typedef void* moontide_orch_h;
    typedef void* moontide_wire_h;

    moontide_orch_h moontide_orch_create();
    void moontide_orch_destroy(moontide_orch_h orch);

    moontide_orch_h moontide_orch_add_wire(moontide_orch_h orch, const char* name, const char* schema, size_t size, bool buffered);
    void* moontide_wire_get_ptr(moontide_wire_h wire);
    void moontide_wire_set_access(moontide_wire_h wire, uint32_t prot);
    void moontide_wire_swap(moontide_wire_h wire);

    // Memory protection flags (standard POSIX)
    enum {
        MOONTIDE_PROT_NONE  = 0x0,
        MOONTIDE_PROT_READ  = 0x1,
        MOONTIDE_PROT_WRITE = 0x2,
        MOONTIDE_PROT_EXEC  = 0x4
    };
]]

-- 2. Define our Data Schema
ffi.cdef[[
    typedef struct {
        float x, y;
        int hp;
        char name[16];
    } player_state_t;
]]

-- 3. Load the Moontide Library
local mt = ffi.load("zig-out/lib/libmoontide.so")

print("--- Moontide Bridge Example ---")

-- 4. Create an Orchestrator (owned by Moontide)
local orch = mt.moontide_orch_create()
if orch == nil then
    print("Failed to create Moontide Orchestrator")
    return
end

-- 5. Add a Wire for player data
-- Moontide allocates this using mmap + guard pages
local wire = mt.moontide_orch_add_wire(orch, "player_state", "x:f32;y:f32;hp:i32;name:char[16]", ffi.sizeof("player_state_t"), false)
local ptr = mt.moontide_wire_get_ptr(wire)
local player = ffi.cast("player_state_t*", ptr)

-- 6. Direct Memory Manipulation (Normal access)
mt.moontide_wire_set_access(wire, mt.MOONTIDE_PROT_READ + mt.MOONTIDE_PROT_WRITE)

player.x = 100.5
player.y = 200.5
player.hp = 100
ffi.copy(player.name, "MoontidePlayer")

print(string.format("Player: %s | Pos: %.1f, %.1f | HP: %d", 
    ffi.string(player.name), player.x, player.y, player.hp))

-- 7. Silicon Gating: Set to READ ONLY
print("\nActivating Silicon Gating: Setting wire to READ ONLY...")
mt.moontide_wire_set_access(wire, mt.MOONTIDE_PROT_READ)

print("Reading HP safely: " .. player.hp)

-- 8. Demonstrating protection (Simulated)
-- If we tried to write here, it would trigger a SIGSEGV (handled by Moontide if we were running in its sandbox,
-- but since we are a standalone LuaJIT process, we'd crash unless we setup our own handler).
-- For this example, we'll just show we can set it back to write.

print("\nDisabling Silicon Gating: Setting wire back to READ/WRITE...")
mt.moontide_wire_set_access(wire, mt.MOONTIDE_PROT_READ + mt.MOONTIDE_PROT_WRITE)
player.hp = 95
print("HP updated: " .. player.hp)

-- 9. Cleanup
mt.moontide_orch_destroy(orch)
print("\nOrchestrator destroyed. Memory unmapped.")
