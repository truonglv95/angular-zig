/// declare_namespaces phase — re-exported from impl.zig
///
/// Port of: template/pipeline/src/phases/declare_namespaces.ts
///
/// This file is a thin wrapper that re-exports the phase implementation
/// from impl.zig. The actual logic lives there for now; it will be
/// gradually migrated into this file as the port progresses.
const impl = @import("impl.zig");

pub const run = impl.declareNamespaces;
