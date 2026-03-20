#ifndef MOONTIDE_H
#define MOONTIDE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/**
 * MOONTIDE ABI v1.2
 * The stable handshake between the Pure Silicon (Kernel) 
 * and the logic runtimes (Extensions).
 */

#define MOONTIDE_ABI_VERSION 2

#define MOONTIDE_STATUS_OK 0
#define MOONTIDE_STATUS_ERROR 1

typedef uint32_t moontide_status_t;
typedef void* moontide_node_h;

typedef enum {
    MOONTIDE_LOG_DEBUG = 0,
    MOONTIDE_LOG_INFO = 1,
    MOONTIDE_LOG_WARN = 2,
    MOONTIDE_LOG_ERROR = 3,
    MOONTIDE_LOG_FATAL = 4,
} moontide_log_level_t;

/**
 * The Host-side logging callback.
 * Extensions call this to send structured telemetry back to the Motherboard.
 */
typedef void (*moontide_log_fn)(moontide_log_level_t level, const char* node_name, const char* message);

/**
 * The Host-side event trigger (Poke).
 * Nodes call this to signal that something happened on the Wires.
 */
typedef void (*moontide_poke_fn)(const char* event_name);

/**
 * Function pointers that the Extension MUST export for the Kernel to use.
 */
typedef struct {
    uint32_t abi_version; // Must match MOONTIDE_ABI_VERSION

    // 1. Lifecycle
    moontide_node_h (*create_node)(const char* name, const char* script_path);
    void (*destroy_node)(moontide_node_h node);

    // 2. Data Wiring
    moontide_status_t (*bind_wire)(moontide_node_h node, const char* name, void* ptr, const char* schema, size_t access);

    // 3. Execution
    moontide_status_t (*tick)(moontide_node_h node, uint64_t pulse_count);
    moontide_status_t (*reload_node)(moontide_node_h node, const char* script_path);

    // 4. Events (Poke)
    moontide_status_t (*add_trigger)(moontide_node_h node, const char* event_name);

    // 5. Host Services (New in v1.1)
    void (*set_log_handler)(moontide_log_fn log_handler);
    void (*set_poke_handler)(moontide_poke_fn poke_handler);
    void (*set_orchestrator_handler)(void* orch);

    // 6. OS Integration
    bool (*poll_events)(moontide_node_h node);
} moontide_extension_t;

/**
 * The entry point for every extension.
 * When the Kernel loads a .so/.dll, it calls this to get the dispatch table.
 */
typedef moontide_extension_t (*moontide_ext_init_fn)(void);

#endif // MOONTIDE_H
