/// Injectable Compiler 2 — Compiles @Injectable decorators
///
/// Port of: compiler/src/injectable_compiler_2.ts (188 LoC)
///
/// Compiles @Injectable() decorated classes into ɵɵdefineInjectable calls.
const std = @import("std");

/// R3InjectableMetadata — metadata for compiling an injectable.
pub const R3InjectableMetadata = struct {
    name: []const u8,
    provided_in: ?[]const u8 = null,
    use_existing: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    deps: []const []const u8 = &.{},
};

/// Compile an @Injectable into ɵɵdefineInjectable code.
pub fn compileInjectable(allocator: std.mem.Allocator, meta: R3InjectableMetadata) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("ɵɵdefineInjectable({ ");

    // Token
    try buf.appendSlice("token: ");
    try buf.appendSlice(meta.name);

    // ProvidedIn
    if (meta.provided_in) |pi| {
        try buf.appendSlice(", providedIn: '");
        try buf.appendSlice(pi);
        try buf.append(''');
    }

    // UseExisting
    if (meta.use_existing) |ue| {
        try buf.appendSlice(", useExisting: ");
        try buf.appendSlice(ue);
    }

    // UseFactory
    if (meta.use_factory) |uf| {
        try buf.appendSlice(", useFactory: ");
        try buf.appendSlice(uf);
    }

    // UseValue
    if (meta.use_value) |uv| {
        try buf.appendSlice(", useValue: ");
        try buf.appendSlice(uv);
    }

    // UseClass
    if (meta.use_class) |uc| {
        try buf.appendSlice(", useClass: ");
        try buf.appendSlice(uc);
    }

    // Factory
    try buf.appendSlice(", factory: () => new ");
    try buf.appendSlice(meta.name);
    try buf.appendSlice("()");

    try buf.appendSlice(" })");
    return buf.toOwnedSlice();
}

test "compileInjectable basic" {
    const allocator = std.testing.allocator;
    const result = try compileInjectable(allocator, .{
        .name = "MyService",
        .provided_in = "root",
    });
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "ɵɵdefineInjectable") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "MyService") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "root") != null);
}
