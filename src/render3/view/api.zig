/// R3 View API — Metadata interfaces for view compilation
///
/// Port of: compiler/src/render3/render3/view/.ts (595 LoC)
const std = @import("std");

/// R3DirectiveMetadata — metadata for compiling a directive.
pub const R3DirectiveMetadata = struct {
    name: []const u8,
    selector: []const u8 = "",
    inputs: []const []const u8 = &.{},
    outputs: []const []const u8 = &.{},
    export_as: []const []const u8 = &.{},
    is_standalone: bool = false,
    queries: []const []const u8 = &.{},
    host_bindings: []const []const u8 = &.{},
    host_listeners: []const []const u8 = &.{},
};

/// R3ComponentMetadata — metadata for compiling a component.
pub const R3ComponentMetadata = struct {
    base: R3DirectiveMetadata,
    template: []const u8 = "",
    encapsulation: u8 = 0,
    change_detection: u8 = 0,
    styles: []const []const u8 = &.{},
    style_urls: []const []const u8 = &.{},
    animations: []const []const u8 = &.{},
    is_standalone: bool = false,
    imports: []const []const u8 = &.{},
};

/// R3HostMetadata — metadata for host binding compilation.
pub const R3HostMetadata = struct {
    type_name: []const u8,
    bindings: []const []const u8 = &.{},
    listeners: []const []const u8 = &.{},
};

/// R3QueryMetadata — metadata for content/view queries.
pub const R3QueryMetadata = struct {
    property_name: []const u8,
    first: bool = false,
    descendants: bool = false,
    read: ?[]const u8 = null,
    static: bool = false,
    predicate: []const u8 = "",
};

/// R3TemplateDependencyMetadata — template dependency.
pub const R3TemplateDependencyMetadata = struct {
    kind: []const u8,
    type_name: []const u8,
};
