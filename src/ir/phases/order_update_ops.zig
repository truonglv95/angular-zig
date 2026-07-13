/// order_update_ops phase — re-exported from impl.zig
///
/// Port of: template/pipeline/src/phases/order_update_ops.ts
///
/// This file is a thin wrapper that re-exports the phase implementation
/// from impl.zig. The actual logic lives there for now; it will be
/// gradually migrated into this file as the port progresses.
const impl = @import("impl.zig");

pub const run = impl.orderUpdateOps;
