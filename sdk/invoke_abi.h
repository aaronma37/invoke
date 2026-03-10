#ifndef INVOKE_ABI_H
#define INVOKE_ABI_H

#include <stdint.h>
#include <stddef.h>

/**
 * INVOKE ABI v1.0
 * The stable handshake between the Pure Silicon (Kernel) 
 * and the logic runtimes (Extensions).
 */

#define INVOKE_ABI_VERSION 1

typedef enum {
    INVOKE_STATUS_OK = 0,
    INVOKE_STATUS_ERROR = 1,
} invoke_status_t;

/**
 * The Extension's internal representation of a logic unit.
 * Handled as an opaque pointer by the Kernel.
 */
typedef void* invoke_node_h;

/**
 * Function pointers that the Extension MUST export for the Kernel to use.
 */
typedef struct {
    // 1. Lifecycle
    invoke_node_h (*create_node)(const char* name, const char* script_path);
    void (*destroy_node)(invoke_node_h node);

    // 2. Data Wiring
    invoke_status_t (*bind_wire)(invoke_node_h node, const char* name, void* ptr, size_t size);

    // 3. Execution
    invoke_status_t (*tick)(invoke_node_h node);
    invoke_status_t (*reload_node)(invoke_node_h node, const char* script_path);

    // 4. Events (Poke)
    invoke_status_t (*add_trigger)(invoke_node_h node, const char* event_name);
} invoke_extension_t;

/**
 * The entry point for every extension.
 * When the Kernel loads a .so/.dll, it calls this to get the dispatch table.
 */
typedef invoke_extension_t (*invoke_ext_init_fn)(void);

#endif // INVOKE_ABI_H
