#ifndef INVOKE_ABI_H
#define INVOKE_ABI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/**
 * INVOKE ABI v1.1
 * The stable handshake between the Pure Silicon (Kernel) 
 * and the logic runtimes (Extensions).
 */

#define INVOKE_ABI_VERSION 1

#define INVOKE_STATUS_OK 0
#define INVOKE_STATUS_ERROR 1

typedef uint32_t invoke_status_t;
typedef void* invoke_node_h;

typedef enum {
    INVOKE_LOG_DEBUG = 0,
    INVOKE_LOG_INFO = 1,
    INVOKE_LOG_WARN = 2,
    INVOKE_LOG_ERROR = 3,
    INVOKE_LOG_FATAL = 4,
} invoke_log_level_t;

/**
 * The Host-side logging callback.
 * Extensions call this to send structured telemetry back to the Motherboard.
 */
typedef void (*invoke_log_fn)(invoke_log_level_t level, const char* node_name, const char* message);

/**
 * The Host-side event trigger (Poke).
 * Nodes call this to signal that something happened on the Wires.
 */
typedef void (*invoke_poke_fn)(const char* event_name);

/**
 * Function pointers that the Extension MUST export for the Kernel to use.
 */
typedef struct {
    // 1. Lifecycle
    invoke_node_h (*create_node)(const char* name, const char* script_path);
    void (*destroy_node)(invoke_node_h node);

    // 2. Data Wiring
    invoke_status_t (*bind_wire)(invoke_node_h node, const char* name, void* ptr, size_t access);

    // 3. Execution
    invoke_status_t (*tick)(invoke_node_h node);
    invoke_status_t (*reload_node)(invoke_node_h node, const char* script_path);

    // 4. Events (Poke)
    invoke_status_t (*add_trigger)(invoke_node_h node, const char* event_name);

    // 5. Host Services (New in v1.1)
    void (*set_log_handler)(invoke_log_fn log_handler);
    void (*set_poke_handler)(invoke_poke_fn poke_handler);
    void (*set_orchestrator_handler)(void* orch);

    // 6. OS Integration
    bool (*poll_events)(invoke_node_h node);
} invoke_extension_t;

/**
 * The entry point for every extension.
 * When the Kernel loads a .so/.dll, it calls this to get the dispatch table.
 */
typedef invoke_extension_t (*invoke_ext_init_fn)(void);

#endif // INVOKE_ABI_H
