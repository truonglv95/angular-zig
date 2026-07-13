/// JIT Compiler Facade — Just-In-Time compilation entry point
///
/// Port of: compiler/src/jit_compiler_facade.ts (1,100 LoC)
///
/// In AOT mode, the JIT facade is not used. However, for compatibility
/// with Angular's runtime API, we provide the interface and basic
/// compilation functions that would be called in JIT mode.
const std = @import("std");
const output_ast = @import("output/ast.zig");
const output_emitter = @import("output/emitter.zig");

/// Factory target enum (matching Angular's FactoryTarget).
pub const FactoryTarget = enum(u8) {
    Component = 0,
    Directive = 1,
    Injectable = 2,
    Pipe = 3,
    NgModule = 4,
};

/// View encapsulation enum.
pub const ViewEncapsulation = enum(u8) {
    Emulated = 0,
    Native = 1,
    None = 2,
    ShadowDom = 3,
};

/// Change detection strategy enum.
pub const ChangeDetectionStrategy = enum(u8) {
    Default = 0,
    OnPush = 1,
};

/// R3ComponentMetadata — metadata for compiling a component.
pub const R3ComponentMetadata = struct {
    name: []const u8,
    template: []const u8 = "",
    encapsulation: ViewEncapsulation = .Emulated,
    change_detection: ChangeDetectionStrategy = .Default,
    styles: []const []const u8 = &.{},
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    is_standalone: bool = false,
};

/// R3DirectiveMetadata — metadata for compiling a directive.
pub const R3DirectiveMetadata = struct {
    name: []const u8,
    selector: []const u8 = "",
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    is_standalone: bool = false,
};

/// R3PipeMetadata — metadata for compiling a pipe.
pub const R3PipeMetadata = struct {
    name: []const u8,
    pipe_name: []const u8,
    pure: bool = true,
    is_standalone: bool = false,
};

/// R3InjectableMetadata — metadata for compiling an injectable.
pub const R3InjectableMetadata = struct {
    name: []const u8,
    provided_in: ?[]const u8 = null,
};

/// R3NgModuleMetadata — metadata for compiling an NgModule.
pub const R3NgModuleMetadata = struct {
    name: []const u8,
    imports: []const []const u8 = &.{},
    exports: []const []const u8 = &.{},
};

/// Compile a component's JIT definition.
/// In AOT mode, this is not called — the definition is generated at build time.
pub fn compileComponentJIT(allocator: std.mem.Allocator, meta: R3ComponentMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineComponent({{ type: {s}, template: '{s}' }})",
        .{ meta.name, meta.template });
}

/// Compile a directive's JIT definition.
pub fn compileDirectiveJIT(allocator: std.mem.Allocator, meta: R3DirectiveMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineDirective({{ type: {s}, selectors: [['{s}']] }})",
        .{ meta.name, meta.selector });
}

/// Compile a pipe's JIT definition.
pub fn compilePipeJIT(allocator: std.mem.Allocator, meta: R3PipeMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefinePipe({{ name: '{s}', pure: {} }})",
        .{ meta.pipe_name, meta.pure });
}

/// Compile an injectable's JIT definition.
pub fn compileInjectableJIT(allocator: std.mem.Allocator, meta: R3InjectableMetadata) ![]const u8 {
    const provided = meta.provided_in orelse "null";
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineInjectable({{ token: {s}, providedIn: '{s}' }})",
        .{ meta.name, provided });
}

/// Compile an NgModule's JIT definition.
pub fn compileNgModuleJIT(allocator: std.mem.Allocator, meta: R3NgModuleMetadata) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        "ɵɵdefineNgModule({{ type: {s} }})", .{meta.name});
}
