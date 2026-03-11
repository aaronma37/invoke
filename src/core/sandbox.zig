const std = @import("std");

pub const c = @cImport({
    @cInclude("signal.h");
    @cInclude("setjmp.h");
});

pub threadlocal var jump_buffer: c.jmp_buf = undefined;
pub threadlocal var is_recovering: bool = false;
pub threadlocal var must_abort: bool = false;

pub fn segfault_handler(sig: c_int) callconv(.C) void {
    _ = sig;
    if (is_recovering) {
        c.longjmp(&jump_buffer, 1);
    } else {
        std.debug.print("\n[CRITICAL] Unrecoverable Segfault outside of Node execution.\n", .{});
        std.process.exit(1);
    }
}

pub fn timeout_handler(sig: c_int) callconv(.C) void {
    _ = sig;
    if (is_recovering) {
        c.longjmp(&jump_buffer, 2); // Force jump out of loop
    }
}

pub fn checkPoints() void {
    if (must_abort) {
        must_abort = false;
        c.longjmp(&jump_buffer, 2); // 2 = Timeout code
    }
}

pub fn initSignalHandler() void {
    // 1. Segfault
    var sa_segv: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    sa_segv.__sigaction_handler.sa_handler = segfault_handler;
    sa_segv.sa_flags = 0; 
    _ = c.sigaction(c.SIGSEGV, &sa_segv, null);

    // 2. Timeout (User Signal 1)
    var sa_usr1: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    sa_usr1.__sigaction_handler.sa_handler = timeout_handler;
    sa_usr1.sa_flags = 0;
    _ = c.sigaction(c.SIGUSR1, &sa_usr1, null);
}
