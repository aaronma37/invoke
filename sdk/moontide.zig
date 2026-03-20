const std = @import("std");
pub const orchestrator = @import("core");

pub const abi = @cImport({
    @cInclude("moontide.h");
});

pub const Status = enum(u32) {
    ok = abi.MOONTIDE_STATUS_OK,
    err = abi.MOONTIDE_STATUS_ERROR,
};
