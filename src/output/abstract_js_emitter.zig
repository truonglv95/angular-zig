/// Abstract JS Emitter — JS-only emitter (strips type annotations)
///
/// Port of: compiler/src/output/abstract_js_emitter.ts (112 LoC)
const std = @import("std");
const abstract_emitter = @import("abstract_emitter.zig");

/// JS emitter — extends AbstractEmitterVisitor for JS output.
pub const AbstractJsEmitterVisitor = struct {
    base: abstract_emitter.Emitter,

    pub fn init(allocator: std.mem.Allocator) AbstractJsEmitterVisitor {
        return .{ .base = abstract_emitter.Emitter.init(allocator) };
    }

    pub fn deinit(self: *AbstractJsEmitterVisitor) void {
        self.base.deinit();
    }
};
