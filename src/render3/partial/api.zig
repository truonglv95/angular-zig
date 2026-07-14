/// R3 Partial API — Partial declaration metadata interfaces
///
/// Port of: compiler/src/render3/partial/api.ts (607 LoC)
///
/// Defines the metadata interfaces for partial declarations — the data
/// structures that `ɵɵngDeclareComponent()`, `ɵɵngDeclareDirective()`, etc.
/// accept. These are used by the Angular linker to process compiled libraries.
const std = @import("std");

/// FactoryTarget — the kind of Angular factory being compiled.
/// Direct port of `FactoryTarget` from compiler_facade_interface.ts.
pub const FactoryTarget = enum(u8) {
    Component,
    Directive,
    Injectable,
    Pipe,
    NgModule,
    Factory,
};

/// R3PartialDeclaration — base interface for all partial declarations.
/// Direct port of `R3PartialDeclaration` interface in the TS source.
pub const R3PartialDeclaration = struct {
    /// The minimum version of the compiler that can process this declaration.
    min_version: []const u8,
    /// Version of the Angular compiler used to compile this declaration.
    version: []const u8,
    /// A reference to the `@angular/core` ES module.
    ng_import: []const u8,
    /// Reference to the decorated class.
    type: []const u8,
};

/// R3InputMapping — describes a single input on a directive/component.
/// Direct port of the input mapping type in the TS source.
pub const R3InputMapping = struct {
    class_property_name: []const u8,
    public_name: []const u8,
    is_signal: bool = false,
    is_required: bool = false,
    transform_function: ?[]const u8 = null,
};

/// R3HostBindings — host binding metadata for a directive/component.
/// Direct port of the `host` property in the TS source.
pub const R3HostBindings = struct {
    attributes: ?std.StringHashMap([]const u8) = null,
    listeners: ?std.StringHashMap([]const u8) = null,
    properties: ?std.StringHashMap([]const u8) = null,
    two_way_bindings: ?std.StringHashMap([]const u8) = null,
};

/// R3DeclareDirectiveMetadata — metadata for `ɵɵngDeclareDirective()`.
/// Direct port of `R3DeclareDirectiveMetadata` interface in the TS source.
pub const R3DeclareDirectiveMetadata = struct {
    base: R3PartialDeclaration,
    selector: ?[]const u8 = null,
    inputs: ?std.StringHashMap(R3InputMapping) = null,
    outputs: ?std.StringHashMap([]const u8) = null,
    host: ?R3HostBindings = null,
    export_as: ?[]const []const u8 = null,
    is_standalone: bool = false,
    is_signal: bool = false,
    queries: ?[]const R3QueryMetadata = null,
    view_queries: ?[]const R3QueryMetadata = null,
    uses_inheritance: bool = false,
    uses_on_changes: bool = false,
    ng_module_imports: ?[]const []const u8 = null,
    decorators: ?[]const []const u8 = null,
};

/// R3QueryMetadata — metadata for a content/view query.
pub const R3QueryMetadata = struct {
    property_name: []const u8,
    predicate: []const u8,
    descendants: bool = false,
    first: bool = false,
    read: ?[]const u8 = null,
    static: bool = false,
    is_signal: bool = false,
};

/// R3DeclareComponentMetadata — metadata for `ɵɵngDeclareComponent()`.
/// Direct port of `R3DeclareComponentMetadata` interface in the TS source.
pub const R3DeclareComponentMetadata = struct {
    base: R3PartialDeclaration,
    selector: ?[]const u8 = null,
    inputs: ?std.StringHashMap(R3InputMapping) = null,
    outputs: ?std.StringHashMap([]const u8) = null,
    host: ?R3HostBindings = null,
    export_as: ?[]const []const u8 = null,
    is_standalone: bool = false,
    is_signal: bool = false,
    queries: ?[]const R3QueryMetadata = null,
    view_queries: ?[]const R3QueryMetadata = null,
    uses_inheritance: bool = false,
    uses_on_changes: bool = false,
    ng_module_imports: ?[]const []const u8 = null,
    decorators: ?[]const []const u8 = null,
    template: []const u8 = "",
    decls: u32 = 0,
    vars: u32 = 0,
    encapsulation: u8 = 0,
    styles: ?[]const []const u8 = null,
    // Additional component-specific fields
    dependencies: ?[]const []const u8 = null,
    change_detection: u8 = 0,
    animations: ?[]const []const u8 = null,
    preserve_whitespaces: bool = false,
};

/// R3DeclarePipeMetadata — metadata for `ɵɵngDeclarePipe()`.
/// Direct port of `R3DeclarePipeMetadata` interface in the TS source.
pub const R3DeclarePipeMetadata = struct {
    base: R3PartialDeclaration,
    name: []const u8,
    pure: bool = true,
    is_standalone: bool = false,
};

/// R3DeclareInjectableMetadata — metadata for `ɵɵngDeclareInjectable()`.
/// Direct port of `R3DeclareInjectableMetadata` interface in the TS source.
pub const R3DeclareInjectableMetadata = struct {
    base: R3PartialDeclaration,
    token: ?[]const u8 = null,
    provided_in: ?[]const u8 = null,
    use_factory: ?[]const u8 = null,
    use_value: ?[]const u8 = null,
    use_class: ?[]const u8 = null,
    use_existing: ?[]const u8 = null,
    deps: ?[]const []const u8 = null,
};

/// R3DeclareNgModuleMetadata — metadata for `ɵɵngDeclareNgModule()`.
/// Direct port of `R3DeclareNgModuleMetadata` interface in the TS source.
pub const R3DeclareNgModuleMetadata = struct {
    base: R3PartialDeclaration,
    declarations: ?[]const []const u8 = null,
    imports: ?[]const []const u8 = null,
    exports: ?[]const []const u8 = null,
    bootstrap: ?[]const []const u8 = null,
    schemas: ?[]const []const u8 = null,
    is_standalone: bool = false,
};

// ─── Tests ──────────────────────────────────────────────────

test "FactoryTarget values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(FactoryTarget.Component));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(FactoryTarget.Directive));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(FactoryTarget.Pipe));
}

test "R3PartialDeclaration defaults" {
    const decl = R3PartialDeclaration{
        .min_version = "14.0.0",
        .version = "16.0.0",
        .ng_import = "@angular/core",
        .type = "MyComp",
    };
    try std.testing.expectEqualStrings("14.0.0", decl.min_version);
    try std.testing.expectEqualStrings("MyComp", decl.type);
}

test "R3InputMapping defaults" {
    const input = R3InputMapping{
        .class_property_name = "myProp",
        .public_name = "myProp",
    };
    try std.testing.expect(!input.is_signal);
    try std.testing.expect(!input.is_required);
    try std.testing.expect(input.transform_function == null);
}

test "R3DeclarePipeMetadata defaults" {
    const pipe = R3DeclarePipeMetadata{
        .base = .{
            .min_version = "14.0.0",
            .version = "16.0.0",
            .ng_import = "@angular/core",
            .type = "MyPipe",
        },
        .name = "myPipe",
    };
    try std.testing.expect(pipe.pure);
    try std.testing.expect(!pipe.is_standalone);
}
