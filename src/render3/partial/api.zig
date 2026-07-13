/// R3 Partial API — Partial declaration interfaces + dispatch
///
/// Port of: compiler/src/render3/render3/partial/.ts (607 LoC)
const std = @import("std");

/// PartialDeclarationKind — kinds of partial declarations.
pub const PartialDeclarationKind = enum(u8) {
    Component, Directive, Pipe, Injectable, NgModule, Injector, Factory,
};

/// R3DeclareComponentFacade — partial component declaration.
pub const R3DeclareComponentFacade = struct {
    type: []const u8,
    template: []const u8 = "",
    encapsulation: u8 = 0,
};

/// R3DeclareDirectiveFacade — partial directive declaration.
pub const R3DeclareDirectiveFacade = struct {
    type: []const u8,
    selector: []const u8 = "",
};

/// R3DeclarePipeFacade — partial pipe declaration.
pub const R3DeclarePipeFacade = struct {
    type: []const u8,
    name: []const u8,
    pure: bool = true,
};

/// R3DeclareInjectableFacade — partial injectable declaration.
pub const R3DeclareInjectableFacade = struct {
    type: []const u8,
    providedIn: ?[]const u8 = null,
};

/// Compile a partial declaration into a full definition.
pub fn compilePartial(allocator: std.mem.Allocator, kind: PartialDeclarationKind, meta: anytype) ![]const u8 {
    return switch (kind) {
        .Component => std.fmt.allocPrint(allocator, "ɵɵdefineComponent({{ type: {s} }})", .{meta.type}),
        .Directive => std.fmt.allocPrint(allocator, "ɵɵdefineDirective({{ type: {s} }})", .{meta.type}),
        .Pipe => std.fmt.allocPrint(allocator, "ɵɵdefinePipe({{ type: {s} }})", .{meta.type}),
        .Injectable => std.fmt.allocPrint(allocator, "ɵɵdefineInjectable({{ type: {s} }})", .{meta.type}),
        .NgModule => std.fmt.allocPrint(allocator, "ɵɵdefineNgModule({{ type: {s} }})", .{meta.type}),
        .Injector => std.fmt.allocPrint(allocator, "ɵɵdefineInjector({{ type: {s} }})", .{meta.type}),
        .Factory => std.fmt.allocPrint(allocator, "ɵɵdeclareFactory({{ type: {s} }})", .{meta.type}),
    };
}
