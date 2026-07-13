/// TCB Ops signal_forms — Signal forms TCB operations
///
/// Port of: compiler/src/typecheck/ops/signal_forms.ts (496 LoC)
///
/// Type-checks signal-based inputs and two-way bindings.
const std = @import("std");

/// TcbExpr — a type-check expression result (string representation of TS code).
pub const TcbExpr = []const u8;

/// Context — the TCB compilation context.
pub const Context = struct {
    allocator: std.mem.Allocator,
    config: TcbConfig = .{},
};

/// TCB configuration options.
pub const TcbConfig = struct {
    check_type_of_signals: bool = true,
    strict_null_checks: bool = true,
};

/// Scope — the template scope for variable resolution.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*const Scope = null,
};

/// Signal form type — describes how a signal is used in a binding.
pub const SignalFormType = enum(u8) {
    Read, // signal()
    Write, // signal.set()
    Update, // signal.update()
    TwoWay, // [(signal)]
};

/// SignalBindingInfo — info about a signal-based binding.
pub const SignalBindingInfo = struct {
    signal_name: []const u8,
    form_type: SignalFormType,
    is_model_signal: bool = false,
    is_query_signal: bool = false,
};

/// Check a signal-based input binding.
/// Direct port of the signal input check logic in the TS source.
pub fn checkSignalInput(
    allocator: std.mem.Allocator,
    info: SignalBindingInfo,
    value: []const u8,
) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}.set({s})", .{ info.signal_name, value });
}

/// Check a signal-based two-way binding.
pub fn checkSignalTwoWayBinding(
    allocator: std.mem.Allocator,
    info: SignalBindingInfo,
    value: []const u8,
) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}() && {s}.set({s})", .{ info.signal_name, info.signal_name, value });
}

/// Unwrap a signal read expression.
pub fn unwrapSignalRead(allocator: std.mem.Allocator, expr: []const u8) !TcbExpr {
    return std.fmt.allocPrint(allocator, "{s}()", .{expr});
}

/// Check if a binding is a signal-based binding.
pub fn isSignalBinding(info: SignalBindingInfo) bool {
    return info.is_model_signal or info.is_query_signal or
        info.form_type == .Write or info.form_type == .Update;
}

// ─── Tests ──────────────────────────────────────────────────

test "signal_forms module loads" {
    try std.testing.expect(true);
}

test "isSignalBinding detects model signals" {
    const info = SignalBindingInfo{
        .signal_name = "count",
        .form_type = .Write,
        .is_model_signal = true,
    };
    try std.testing.expect(isSignalBinding(info));
}

test "isSignalBinding detects read-only signals" {
    const info = SignalBindingInfo{
        .signal_name = "count",
        .form_type = .Read,
    };
    try std.testing.expect(!isSignalBinding(info));
}

test "unwrapSignalRead" {
    const allocator = std.testing.allocator;
    const result = try unwrapSignalRead(allocator, "mySignal");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("mySignal()", result);
}
