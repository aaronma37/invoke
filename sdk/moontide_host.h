#ifndef MOONTIDE_HOST_H
#define MOONTIDE_HOST_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* moontide_orch_h;
typedef void* moontide_wire_h;

// 1. Lifecycle
moontide_orch_h moontide_orch_create();
void moontide_orch_destroy(moontide_orch_h orch);

// 2. Wire Management
moontide_wire_h moontide_orch_add_wire(moontide_orch_h orch, const char* name, const char* schema, size_t size, bool buffered);
void* moontide_wire_get_ptr(moontide_wire_h wire);
void moontide_wire_set_access(moontide_wire_h wire, uint32_t prot);
void moontide_wire_swap(moontide_wire_h wire);

// 3. Constants (matching POSIX)
#define MOONTIDE_PROT_NONE  0x0
#define MOONTIDE_PROT_READ  0x1
#define MOONTIDE_PROT_WRITE 0x2
#define MOONTIDE_PROT_EXEC  0x4

#ifdef __cplusplus
}
#endif

#endif // MOONTIDE_HOST_H
