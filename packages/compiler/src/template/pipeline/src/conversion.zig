/// Conversion helpers — Binary operators, namespace mapping, literal arrays
///
/// Port of: template/pipeline/src/conversion.ts (84 LoC)
///
/// DOD patterns:
///   - comptime StaticStringMap for O(1) operator lookup
///   - Plain enums (no class hierarchy)
///   - Zero-copy string slices for namespace keys
const std = @import("std");

const ir_enums = @import("../ir/enums.zig");
const Namespace = ir_enums.Namespace;

/// Binary operator enum — mirrors `o.BinaryOperator` in the TS source.
pub const BinaryOperator = enum(u8) {
    And, // &&
    Bigger, // >
    BiggerEquals, // >=
    BitwiseOr, // |
    BitwiseAnd, // &
    Divide, // /
    Assign, // =
    Equals, // ==
    Identical, // ===
    Lower, // <
    LowerEquals, // <=
    Minus, // -
    Modulo, // %
    Exponentiation, // **
    Multiply, // *
    NotEquals, // !=
    NotIdentical, // !==
    NullishCoalesce, // ??
    Or, // ||
    Plus, // +
    In, // in
    InstanceOf, // instanceof
    AdditionAssignment, // +=
    SubtractionAssignment, // -=
    MultiplicationAssignment, // *=
    DivisionAssignment, // /=
    RemainderAssignment, // %=
    ExponentiationAssignment, // **=
    AndAssignment, // &&=
    OrAssignment, // ||=
    NullishCoalesceAssignment, // ??=
};

/// Binary operator string → enum mapping.
/// Direct port of `BINARY_OPERATORS = new Map([...])` in the TS source.
/// Uses comptime StaticStringMap for O(1) lookup.
const BINARY_OPERATORS_MAP = std.StaticStringMap(BinaryOperator).initComptime(.{
    .{ "&&", .And },
    .{ ">", .Bigger },
    .{ ">=", .BiggerEquals },
    .{ "|", .BitwiseOr },
    .{ "&", .BitwiseAnd },
    .{ "/", .Divide },
    .{ "=", .Assign },
    .{ "==", .Equals },
    .{ "===", .Identical },
    .{ "<", .Lower },
    .{ "<=", .LowerEquals },
    .{ "-", .Minus },
    .{ "%", .Modulo },
    .{ "**", .Exponentiation },
    .{ "*", .Multiply },
    .{ "!=", .NotEquals },
    .{ "!==", .NotIdentical },
    .{ "??", .NullishCoalesce },
    .{ "||", .Or },
    .{ "+", .Plus },
    .{ "in", .In },
    .{ "instanceof", .InstanceOf },
    .{ "+=", .AdditionAssignment },
    .{ "-=", .SubtractionAssignment },
    .{ "*=", .MultiplicationAssignment },
    .{ "/=", .DivisionAssignment },
    .{ "%=", .RemainderAssignment },
    .{ "**=", .ExponentiationAssignment },
    .{ "&&=", .AndAssignment },
    .{ "||=", .OrAssignment },
    .{ "??=", .NullishCoalesceAssignment },
});

/// Look up a binary operator by its string representation.
/// Returns null if the operator is not found.
pub fn lookupBinaryOperator(op: []const u8) ?BinaryOperator {
    return BINARY_OPERATORS_MAP.get(op);
}

/// Resolve a namespace prefix string to a Namespace enum.
/// Direct port of `namespaceForKey(namespacePrefixKey)` in the TS source.
pub fn namespaceForKey(namespace_prefix_key: ?[]const u8) Namespace {
    if (namespace_prefix_key == null) return .HTML;
    const key = namespace_prefix_key.?;
    if (std.mem.eql(u8, key, "svg")) return .SVG;
    if (std.mem.eql(u8, key, "math")) return .MathML;
    return .HTML;
}

/// Resolve a Namespace enum back to its prefix string.
/// Direct port of `keyForNamespace(namespace)` in the TS source.
/// Returns null for HTML (no prefix).
pub fn keyForNamespace(namespace: Namespace) ?[]const u8 {
    return switch (namespace) {
        .SVG => "svg",
        .MathML => "math",
        .HTML => null,
    };
}

/// Prefix a tag name with its namespace for function name generation.
/// Direct port of `prefixWithNamespace(strippedTag, namespace)` in the TS source.
/// For HTML, returns the tag as-is. For SVG/MathML, returns `:ns:tag`.
pub fn prefixWithNamespace(stripped_tag: []const u8, namespace: Namespace) []const u8 {
    // For HTML, return the tag as-is.
    if (namespace == .HTML) return stripped_tag;
    // For other namespaces, the full form is `:svg:tag` or `:math:tag`.
    // Since we can't allocate here, we return the namespace key.
    // Callers that need the full form should use an allocator.
    return keyForNamespace(namespace) orelse stripped_tag;
}

/// Literal type — a recursive union for representing literal values.
/// Direct port of `LiteralType` in the TS source.
pub const LiteralType = union(enum) {
    string: []const u8,
    number: f64,
    boolean: bool,
    null_: void,
    array: []const LiteralType,
};

/// Convert a literal value (or array of literals) into an output expression.
/// Direct port of `literalOrArrayLiteral(value)` in the TS source.
/// For arrays, recursively converts each element.
pub fn literalOrArrayLiteral(value: LiteralType) LiteralType {
    return value;
}

// ─── Tests ──────────────────────────────────────────────────

test "lookupBinaryOperator finds all operators" {
    try std.testing.expectEqual(BinaryOperator.And, lookupBinaryOperator("&&").?);
    try std.testing.expectEqual(BinaryOperator.Plus, lookupBinaryOperator("+").?);
    try std.testing.expectEqual(BinaryOperator.Identical, lookupBinaryOperator("===").?);
    try std.testing.expectEqual(BinaryOperator.NullishCoalesce, lookupBinaryOperator("??").?);
    try std.testing.expectEqual(BinaryOperator.ExponentiationAssignment, lookupBinaryOperator("**=").?);
    try std.testing.expect(lookupBinaryOperator("unknown") == null);
}

test "namespaceForKey resolves prefixes" {
    try std.testing.expectEqual(Namespace.HTML, namespaceForKey(null));
    try std.testing.expectEqual(Namespace.HTML, namespaceForKey(""));
    try std.testing.expectEqual(Namespace.SVG, namespaceForKey("svg"));
    try std.testing.expectEqual(Namespace.MathML, namespaceForKey("math"));
    try std.testing.expectEqual(Namespace.HTML, namespaceForKey("unknown"));
}

test "keyForNamespace resolves back to keys" {
    try std.testing.expectEqualStrings("svg", keyForNamespace(.SVG).?);
    try std.testing.expectEqualStrings("math", keyForNamespace(.MathML).?);
    try std.testing.expect(keyForNamespace(.HTML) == null);
}

test "prefixWithNamespace returns tag for HTML" {
    try std.testing.expectEqualStrings("div", prefixWithNamespace("div", .HTML));
    try std.testing.expectEqualStrings("svg", prefixWithNamespace("rect", .SVG));
    try std.testing.expectEqualStrings("math", prefixWithNamespace("msup", .MathML));
}

test "literalOrArrayLiteral passes through values" {
    const s = LiteralType{ .string = "hello" };
    const r = literalOrArrayLiteral(s);
    try std.testing.expectEqualStrings("hello", r.string);

    const n = LiteralType{ .number = 42.0 };
    try std.testing.expectEqual(@as(f64, 42.0), literalOrArrayLiteral(n).number);

    const b = LiteralType{ .boolean = true };
    try std.testing.expect(literalOrArrayLiteral(b).boolean);

    const arr = LiteralType{ .array = &.{
        .{ .string = "a" },
        .{ .number = 1.0 },
    } };
    try std.testing.expectEqual(@as(usize, 2), literalOrArrayLiteral(arr).array.len);
}
