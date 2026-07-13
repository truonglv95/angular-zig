/// I18n Context System — Shared infrastructure for i18n phases
///
/// This module provides the i18n context types and helpers needed by
/// the 12 i18n phases. It mirrors the i18n context system from
/// Angular's template/pipeline/src/ir/ module.
const std = @import("std");

const job_mod = @import("../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;

// ─── I18n Context Kind ───────────────────────────────────────

/// Kind of i18n context — determines how the message is extracted.
pub const I18nContextKind = enum(u8) {
    /// Context for an i18n attribute binding.
    Attr,
    /// Context for a root i18n block (i18n attribute on an element).
    RootI18n,
    /// Context for an ICU expression inside an i18n block.
    Icu,
};

// ─── I18n Message ────────────────────────────────────────────

/// A translatable message extracted from a template.
/// Mirrors i18n.Message from compiler/src/i18n/i18n_ast.ts
pub const I18nMessage = struct {
    /// Unique ID computed from the message content (legacy format).
    id: []const u8 = "",
    /// Unique ID computed from the message content (custom format).
    custom_id: []const u8 = "",
    /// Human-readable description of the message.
    description: ?[]const u8 = null,
    /// Meaning context for the message (disambiguates identical strings).
    meaning: ?[]const u8 = null,
    /// The message nodes (text, placeholders, tags, ICUs).
    nodes: []const I18nMessageNode = &.{},
    /// The source span of the message.
    source_span: ?AbsoluteSourceSpan = null,
    /// Whether this message has been processed.
    processed: bool = false,
};

/// A node in an i18n message — text, placeholder, or tag.
pub const I18nMessageNode = union(enum) {
    /// Literal text content.
    text: []const u8,
    /// A placeholder for an interpolated expression (e.g. {{ name }} → PH).
    placeholder: Placeholder,
    /// A placeholder for an element tag (e.g. <b>...</b> → START_TAG_B).
    tag: TagPlaceholder,
    /// An ICU expression ({count, plural, =0 {...} other {...}}).
    icu: IcuPlaceholder,
};

/// A placeholder for an interpolated expression.
pub const Placeholder = struct {
    /// Name like "PH" or "PH_1".
    name: []const u8,
    /// The source expression text.
    expression: []const u8,
    /// Source span of the expression.
    span: ?AbsoluteSourceSpan = null,
};

/// A placeholder for an element tag.
pub const TagPlaceholder = struct {
    /// Tag name like "b", "span", etc.
    tag: []const u8,
    /// Whether this is a start tag, end tag, or self-closing.
    kind: TagKind,
    /// Children placeholders (for nested content).
    children: []const I18nMessageNode = &.{},
};

pub const TagKind = enum { start, end, self_closing };

/// An ICU expression placeholder.
pub const IcuPlaceholder = struct {
    /// The ICU expression text.
    expression: []const u8,
    /// Placeholder name like "ICU" or "ICU_1".
    name: []const u8,
};

// ─── I18n Context Op ─────────────────────────────────────────

/// An i18n context operation — tracks the i18n state for a block.
/// This is stored as metadata on the view, not as a separate IR op.
pub const I18nContext = struct {
    /// Unique xref ID for this context.
    xref: u32,
    /// Kind of context (attr, root, ICU).
    kind: I18nContextKind,
    /// The root i18n block this context belongs to.
    root: u32,
    /// The message associated with this context.
    message: I18nMessage,
    /// Placeholders collected from this context.
    placeholders: std.array_list.Managed(Placeholder),
    /// Sub-contexts (ICUs inside this context).
    sub_contexts: std.array_list.Managed(u32),

    pub fn init(allocator: std.mem.Allocator, xref: u32, kind: I18nContextKind, root: u32) I18nContext {
        return .{
            .xref = xref,
            .kind = kind,
            .root = root,
            .message = .{},
            .placeholders = std.array_list.Managed(Placeholder).init(allocator),
            .sub_contexts = std.array_list.Managed(u32).init(allocator),
        };
    }

    pub fn deinit(self: *I18nContext) void {
        self.placeholders.deinit();
        self.sub_contexts.deinit();
    }
};

// ─── I18n Context Registry ───────────────────────────────────

/// Registry of i18n contexts for a compilation job.
/// Maps xref IDs to I18nContext instances.
pub const I18nContextRegistry = struct {
    contexts: std.AutoHashMap(u32, *I18nContext),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) I18nContextRegistry {
        return .{
            .contexts = std.AutoHashMap(u32, *I18nContext).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *I18nContextRegistry) void {
        var it = self.contexts.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.contexts.deinit();
    }

    /// Create a new i18n context and register it.
    pub fn createContext(
        self: *I18nContextRegistry,
        kind: I18nContextKind,
        root: u32,
        xref: u32,
    ) !*I18nContext {
        const ctx = try self.allocator.create(I18nContext);
        ctx.* = I18nContext.init(self.allocator, xref, kind, root);
        try self.contexts.put(xref, ctx);
        return ctx;
    }

    /// Get a context by xref ID.
    pub fn get(self: *const I18nContextRegistry, xref: u32) ?*I18nContext {
        return self.contexts.get(xref);
    }
};

// ─── AbsoluteSourceSpan ──────────────────────────────────────
// Forward declaration to avoid circular import
const source_span_mod = @import("../../../source_span.zig");
const AbsoluteSourceSpan = source_span_mod.AbsoluteSourceSpan;
