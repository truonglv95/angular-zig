/// Core — Core compiler types and utilities
///
/// Port of: compiler/src/core.ts (325 LoC)
///
/// Re-exports core types used across the compiler: ViewEncapsulation,
/// ChangeDetectionStrategy, Input, Output, HostBinding, HostListener.
const std = @import("std");

pub const ViewEncapsulation = enum(u8) {
    Emulated = 0,
    Native = 1,
    None = 2,
    ShadowDom = 3,
};

pub const ChangeDetectionStrategy = enum(u8) {
    Default = 0,
    OnPush = 1,
};

pub const Input = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
    required: bool = false,
    transform: ?[]const u8 = null,
};

pub const Output = struct {
    name: []const u8,
    alias: ?[]const u8 = null,
};

pub const HostBinding = struct {
    property_name: []const u8,
    host_property_name: ?[]const u8 = null,
};

pub const HostListener = struct {
    event_name: []const u8,
    handler: []const u8,
};

pub const Query = struct {
    property_name: []const u8,
    first: bool = false,
    descendants: bool = false,
    read: ?[]const u8 = null,
    is_static: bool = false,
};

/// CompileResult — the result of a compilation.
pub const CompileResult = struct {
    output: []const u8,
    source_map: ?[]const u8 = null,
    errors: []const []const u8 = &.{},
};

/// CompileReflector — provides reflection capabilities.
pub const CompileReflector = struct {};
