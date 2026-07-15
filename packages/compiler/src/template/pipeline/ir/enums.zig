/// IR Enums — Operation and Expression kind definitions
///
/// comptime enums for the intermediate representation.
/// These drive the compilation pipeline's ~60 transformation phases.
const std = @import("std");

// ─── Operation Kinds ──────────────────────────────────────────
/// ~50+ op types that compose the IR.
/// Split into Creation ops (rf & 1) and Update ops (rf & 2).
pub const OpKind = enum(u16) {
    // ── Creation Phase ────────────────────────────────────────
    ElementStart = 0,
    ElementEnd = 1,
    ContainerStart = 2,
    ContainerEnd = 3,
    Text = 4,
    Attribute = 5,
    Projection = 6,
    ProjectionDef = 7,
    Listener = 8,
    NamespaceDeclare = 9,
    RepeaterCreate = 10,
    ConditionalCreate = 11,
    Animation = 12,
    AnimationListener = 13,
    Defer = 14,
    DeferOn = 15,
    DeferWhen = 16,
    I18nStart = 17,
    I18n = 18,
    I18nEnd = 19,
    Statement = 20,
    SourceLocation = 21,
    ListEnd = 22,
    Content = 23,
    DisableBindings = 24,
    EnableBindings = 25,
    ControlFlowBlock = 26,
    Template = 27,
    ConditionalBranchCreate = 28,
    ForeignComponent = 29,
    I18nAttributes = 30,
    I18nContext = 31,
    IcuStart = 32,
    IcuEnd = 33,
    IcuPlaceholder = 34,
    ExtractedAttribute = 35,
    ControlCreate = 36,
    Control = 37,
    EnableIncrementalHydrationRuntime = 38,

    // ── Update Phase ──────────────────────────────────────────
    InterpolateText = 100,
    Binding = 101,
    Property = 102,
    StyleProp = 103,
    ClassProp = 104,
    StyleMap = 105,
    ClassMap = 106,
    DomProperty = 107,
    TwoWayProperty = 108,
    TwoWayListener = 109,
    Pipe = 110,
    StoreLet = 111,
    Advance = 112,
    Conditional = 113,
    Repeater = 114,
    Variable = 115,
    I18nExpression = 116,
    AnimationBinding = 117,
    AnimationString = 118,
};

/// Whether an op is a creation-phase or update-phase op
pub fn isCreationOp(kind: OpKind) bool {
    return @intFromEnum(kind) < 100;
}

pub fn isUpdateOp(kind: OpKind) bool {
    return @intFromEnum(kind) >= 100;
}

// ─── Expression Kinds ─────────────────────────────────────────

pub const ExpressionKind = enum(u8) {
    Context = 0,
    ReadVariable = 1,
    NextContext = 2,
    Reference = 3,
    PureFunctionExpr = 4,
    PureFunctionParameterExpr = 5,
    PipeBinding = 6,
    PipeBindingVariadic = 7,
    SafePropertyRead = 8,
    SafeKeyedRead = 9,
    EmptyExpr = 10,
    ConditionalCase = 11,
    ConstCollected = 12,
    TwoWayBindingSet = 13,
    ArrowFunction = 14,
    SlotLiteralExpr = 15,
    BinaryExpr = 16,
    CallExpr = 17,
    LiteralExpr = 18,
    ReadPropExpr = 19,
    ConditionalExpr = 20,
    NotExpr = 21,
};

// ─── Binding Kinds ────────────────────────────────────────────

pub const BindingKind = enum(u8) {
    Attribute = 0,
    ClassName = 1,
    StyleProperty = 2,
    Property = 3,
    Template = 4,
    I18n = 5,
    LegacyAnimation = 6,
    TwoWayProperty = 7,
    Animation = 8,
};

// ─── Namespace ────────────────────────────────────────────────

pub const Namespace = enum(u8) {
    HTML = 0,
    SVG = 1,
    MathML = 2,
};

pub fn namespaceStr(ns: Namespace) []const u8 {
    return switch (ns) {
        .HTML => "html",
        .SVG => "svg",
        .MathML => "math",
    };
}

// ─── Defer Trigger ────────────────────────────────────────────

pub const DeferTriggerKind = enum(u8) {
    Idle = 0,
    Immediate = 1,
    Timer = 2,
    Hover = 3,
    Interaction = 4,
    Viewport = 5,
    Never = 6,
};

// ─── Template Kinds ───────────────────────────────────────────

pub const TemplateKind = enum(u8) {
    NgTemplate = 0,
    Structural = 1,
    Block = 2,
};

// ─── Semantic Variable Kinds ──────────────────────────────────

pub const SemanticVariableKind = enum(u8) {
    Context = 0,
    Identifier = 1,
    SavedView = 2,
    Alias = 3,
};

// ─── Variable Flags ───────────────────────────────────────────

pub const VariableFlags = packed struct {
    always_inline: bool = false,
    _reserved: u7 = 0,
};

// ─── Compilation Mode ─────────────────────────────────────────

pub const CompilationMode = enum(u8) {
    Full,
    DomOnly,
};

pub const CompilationKind = enum(u8) {
    Tmpl, // Template compilation
    HostBinding, // Host binding compilation
};

// ─── Tests ────────────────────────────────────────────────────

test "op kind classification" {
    try std.testing.expect(isCreationOp(.ElementStart));
    try std.testing.expect(isCreationOp(.Listener));
    try std.testing.expect(!isCreationOp(.Binding));
    try std.testing.expect(!isCreationOp(.InterpolateText));

    try std.testing.expect(isUpdateOp(.Binding));
    try std.testing.expect(isUpdateOp(.Property));
    try std.testing.expect(!isUpdateOp(.ElementStart));
}

test "expression kind coverage" {
    const kinds = std.meta.tags(ExpressionKind);
    try std.testing.expect(kinds.len >= 20);
}

test "namespace string" {
    try std.testing.expectEqualStrings("html", namespaceStr(.HTML));
    try std.testing.expectEqualStrings("svg", namespaceStr(.SVG));
}

pub const I18nParamResolutionTime = enum(u8) {
    Creation,
    Postproccessing,
};

pub const I18nExpressionFor = enum(u8) {
    I18nText,
    I18nAttribute,
};

pub const I18nParamValueFlags = enum(u8) {
    None,
    ElementTag,
    TemplateTag,
    OpenTag,
    CloseTag,
    ExpressionIndex,
};

pub const I18nContextKind = enum(u8) {
    RootI18n,
    Icu,
    Attr,
};

pub const AnimationKind = enum(u8) {
    ENTER,
    LEAVE,
};

pub const AnimationBindingKind = enum(u8) {
    STRING,
    VALUE,
};

pub const DeferOpModifierKind = enum(u8) {
    NONE,
    PREFETCH,
    HYDRATE,
};

pub const TDeferDetailsFlags = enum(u8) {
    Default,
    HasHydrateTriggers,
};
