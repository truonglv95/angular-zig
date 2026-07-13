/// Compiler Facade Interface — Public API for the compiler
///
/// Port of: compiler/src/compiler_facade_interface.ts (434 LoC)
///
/// Defines the public interface that the Angular runtime uses to interact
/// with the compiler. Both JIT and AOT compilers implement this interface.
const std = @import("std");

/// Factory target — what kind of Angular construct is being compiled.
pub const FactoryTarget = enum(u8) {
    Component,
    Directive,
    Injectable,
    Pipe,
    NgModule,
};

/// Dependency metadata — describes a DI dependency.
pub const R3DependencyMetadata = struct {
    token: []const u8,
    optional: bool = false,
    self: bool = false,
    skip_self: bool = false,
    host: bool = false,
};

/// Query metadata — describes a content/view query.
pub const R3QueryMetadata = struct {
    property_name: []const u8,
    first: bool = false,
    descendants: bool = false,
    read: ?[]const u8 = null,
    static: bool = false,
};

/// Input metadata — describes an @Input() property.
pub const Input = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
    required: bool = false,
    transform: ?[]const u8 = null,
};

/// Output metadata — describes an @Output() property.
pub const Output = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
};

/// Host binding metadata — describes a host binding.
pub const HostBinding = struct {
    property_name: []const u8,
    hostPropertyName: ?[]const u8 = null,
};

/// Host listener metadata — describes a host listener.
pub const HostListener = struct {
    event_name: []const u8,
    handler: []const u8,
};

/// The compiler facade interface — implemented by both JIT and AOT compilers.
pub const CompilerFacade = struct {
    compileComponent: *const fn (allocator: std.mem.Allocator, meta: anytype) anyerror![]const u8,
    compileDirective: *const fn (allocator: std.mem.Allocator, meta: anytype) anyerror![]const u8,
    compilePipe: *const fn (allocator: std.mem.Allocator, meta: anytype) anyerror![]const u8,
    compileInjectable: *const fn (allocator: std.mem.Allocator, meta: anytype) anyerror![]const u8,
    compileNgModule: *const fn (allocator: std.mem.Allocator, meta: anytype) anyerror![]const u8,
};
