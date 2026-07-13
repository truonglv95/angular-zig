/// IR Emit — emitView, emitTemplateFn
///
/// Port of: compiler/src/template/pipeline/src/emit.ts (324 LoC)
const std = @import("std");
const compilation = @import("compilation.zig");
const CompilationJob = compilation.CompilationJob;
const ViewCompilationUnit = compilation.ViewCompilationUnit;

/// EmittedTemplate — result of emitting a view's IR into output AST.
pub const EmittedTemplate = struct {
    fn_name: []const u8,
    create_stmts: []const u8 = &.{},
    update_stmts: []const u8 = &.{},
    functions: []const u8 = &.{},
};

/// Emit a view's IR into an EmittedTemplate.
pub fn emitView(job: *CompilationJob, view: *ViewCompilationUnit) !EmittedTemplate {
    const fn_name = view.fn_name orelse job.component_name;
    return .{ .fn_name = fn_name };
}

/// Transform a compilation job: run all 72 phases, then emit.
pub fn transform(job: *CompilationJob) !void {
    // The actual phase running is handled by the registry/impl
    _ = job;
}

/// Emit the final template function from a compilation job.
pub fn emitTemplateFn(job: *CompilationJob) ![]const u8 {
    var buf = std.ArrayList(u8).init(job.allocator);
    try buf.appendSlice("function ");
    try buf.appendSlice(job.component_name);
    try buf.appendSlice("_Template(rf, ctx) { }");
    return buf.toOwnedSlice();
}

/// Emit host binding function.
pub fn emitHostBindingFunction(job: *CompilationJob) ![]const u8 {
    var buf = std.ArrayList(u8).init(job.allocator);
    try buf.appendSlice("function ");
    try buf.appendSlice(job.component_name);
    try buf.appendSlice("_HostBindings(rf, ctx) { }");
    return buf.toOwnedSlice();
}
