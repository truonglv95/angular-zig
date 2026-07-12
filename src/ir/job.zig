/// IR Compilation Job — Orchestration center of the pipeline
///
/// DOD: ComponentCompilationJob contains:
///   - root ViewCompilationUnit (the template itself)
///   - views: embedded views (ng-template, structural directives)
///   - constant_pool: shared constant array
///   - Dense, cache-friendly layout
///
/// Each ViewCompilationUnit has:
///   - create: OpList for creation-phase ops
///   - update: OpList for update-phase ops
///   - functions: additional function ops
const std = @import("std");
const Allocator = std.mem.Allocator;
const enums = @import("enums.zig");
const CompilationMode = enums.CompilationMode;
const Namespace = enums.Namespace;
const ops = @import("ops.zig");
const IrOp = ops.IrOp;
const CreateOpList = ops.CreateOpList;
const UpdateOpList = ops.UpdateOpList;
const expression = @import("expression.zig");
const IrExpr = expression.IrExpr;
const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Slot / Xref Allocation ──────────────────────────────────
/// Monotonic slot allocator — each call returns next slot index.
/// Zero-cost: just an incrementing counter.
pub const SlotAllocator = struct {
    next_slot: u32 = 0,
    next_xref: u32 = 0,

    pub fn allocSlot(self: *SlotAllocator) u32 {
        const s = self.next_slot;
        self.next_slot += 1;
        return s;
    }

    pub fn allocXref(self: *SlotAllocator) u32 {
        const x = self.next_xref;
        self.next_xref += 1;
        return x;
    }
};

// ─── Constant Pool ───────────────────────────────────────────
/// Shared pool of constant values extracted from expressions.
/// In generated code: const _c0 = ["val1", "val2", ...];
pub const ConstantPool = struct {
    allocator: Allocator,
    constants: std.array_list.Managed(ConstantEntry),

    pub const ConstantEntry = struct {
        value: []const u8,
        kind: ConstantKind,
    };

    pub const ConstantKind = enum(u8) {
        String,
        Number,
        Boolean,
        Null,
        Array,
        Map,
    };

    pub fn init(allocator: Allocator) ConstantPool {
        return .{
            .allocator = allocator,
            .constants = std.array_list.Managed(ConstantEntry).init(allocator),
        };
    }

    pub fn deinit(self: *ConstantPool) void {
        self.constants.deinit();
    }

    /// Add a constant, returns its index.
    /// DOD: O(n) dedup scan — n is typically small (<100 constants per component).
    /// Prevents duplicate string/number entries in the generated _cN array.
    pub fn add(self: *ConstantPool, value: []const u8, kind: ConstantKind) !u32 {
        // Dedup: scan for existing entry with same (value, kind) pair.
        // O(n) but n is bounded by constant pool size per component.
        for (self.constants.items, 0..) |entry, i| {
            if (entry.kind == kind and std.mem.eql(u8, entry.value, value)) {
                return @intCast(i);
            }
        }
        const index: u32 = @intCast(self.constants.items.len);
        try self.constants.append(.{ .value = value, .kind = kind });
        return index;
    }

    pub fn get(self: *const ConstantPool, index: u32) ?ConstantEntry {
        if (index < self.constants.items.len) {
            return self.constants.items[index];
        }
        return null;
    }

    pub fn size(self: *const ConstantPool) usize {
        return self.constants.items.len;
    }
};

// ─── XrefId — Unique identifier for views ────────────────────

pub const XrefId = u32;

// ─── Compilation Unit ────────────────────────────────────────
/// One compilation unit per view (template / embedded view).
pub const ViewCompilationUnit = struct {
    xref: XrefId,
    parent: ?XrefId,
    allocator: Allocator,

    /// Creation-phase ops (rf & RenderFlags.Create)
    create: CreateOpList,
    /// Update-phase ops (rf & RenderFlags.Update)
    update: UpdateOpList,
    /// Additional function ops (pure functions, etc.)
    functions: std.array_list.Managed(std.array_list.Managed(IrOp)),

    /// Variable count (for vars: N in generated code)
    vars: ?u32 = null,
    /// Declaration count (for decls: N in generated code)
    decls: ?u32 = null,
    /// Function name (for embedded views)
    fn_name: ?[]const u8 = null,
    /// Context variables (from parent template)
    context_variables: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, xref: XrefId, parent: ?XrefId) ViewCompilationUnit {
        return .{
            .xref = xref,
            .parent = parent,
            .allocator = allocator,
            .create = CreateOpList.init(allocator),
            .update = UpdateOpList.init(allocator),
            .functions = std.array_list.Managed(std.array_list.Managed(IrOp)).init(allocator),
            .context_variables = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ViewCompilationUnit) void {
        self.create.deinit();
        self.update.deinit();
        for (self.functions.items) |*fn_ops| {
            fn_ops.deinit();
        }
        self.functions.deinit();
        self.context_variables.deinit();
    }

    /// Allocate a new function's op list
    pub fn allocFunction(self: *ViewCompilationUnit) !*std.array_list.Managed(IrOp) {
        try self.functions.append(std.array_list.Managed(IrOp).init(self.allocator));
        return &self.functions.items[self.functions.items.len - 1];
    }
};

// ─── Compilation Job ─────────────────────────────────────────
/// The top-level compilation state for a single component.
pub const ComponentCompilationJob = struct {
    allocator: Allocator,
    root: ViewCompilationUnit,
    views: std.StringHashMap(*ViewCompilationUnit),
    pool: ConstantPool,
    slots: SlotAllocator,
    mode: CompilationMode,
    component_name: []const u8,

    pub fn init(allocator: Allocator, component_name: []const u8, mode: CompilationMode) !ComponentCompilationJob {
        return .{
            .allocator = allocator,
            .root = ViewCompilationUnit.init(allocator, 0, null),
            .views = std.StringHashMap(*ViewCompilationUnit).init(allocator),
            .pool = ConstantPool.init(allocator),
            .slots = .{},
            .mode = mode,
            .component_name = component_name,
        };
    }

    pub fn deinit(self: *ComponentCompilationJob) void {
        self.root.deinit();
        var it = self.views.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.views.deinit();
        self.pool.deinit();
    }

    /// Allocate an embedded view
    pub fn allocateView(self: *ComponentCompilationJob, parent: XrefId) !*ViewCompilationUnit {
        const xref = self.slots.allocXref();
        const view = try self.allocator.create(ViewCompilationUnit);
        view.* = ViewCompilationUnit.init(self.allocator, xref, parent);
        return view;
    }

    /// Add a constant to the pool
    pub fn addConst(self: *ComponentCompilationJob, value: []const u8, kind: ConstantPool.ConstantKind) !u32 {
        return self.pool.add(value, kind);
    }

    /// Get memory statistics
    pub fn stats(self: *const ComponentCompilationJob) Stats {
        return .{
            .root_create_ops = self.root.create.len(),
            .root_update_ops = self.root.update.len(),
            .embedded_views = self.views.count(),
            .constants = self.pool.size(),
            .total_slots = self.slots.next_slot,
            .total_xrefs = self.slots.next_xref,
        };
    }

    pub const Stats = struct {
        root_create_ops: usize,
        root_update_ops: usize,
        embedded_views: usize,
        constants: usize,
        total_slots: usize,
        total_xrefs: usize,
    };
};

// ─── Tests ────────────────────────────────────────────────────

test "SlotAllocator monotonic" {
    var slots = SlotAllocator{};
    try std.testing.expectEqual(@as(u32, 0), slots.allocSlot());
    try std.testing.expectEqual(@as(u32, 1), slots.allocSlot());
    try std.testing.expectEqual(@as(u32, 0), slots.allocXref());
    try std.testing.expectEqual(@as(u32, 1), slots.allocXref());
}

test "ConstantPool add/get" {
    const allocator = std.testing.allocator;
    var pool = ConstantPool.init(allocator);
    defer pool.deinit();

    const idx0 = try pool.add("hello", .String);
    const idx1 = try pool.add("world", .String);
    try std.testing.expectEqual(@as(u32, 0), idx0);
    try std.testing.expectEqual(@as(u32, 1), idx1);

    const c = pool.get(0).?;
    try std.testing.expectEqualStrings("hello", c.value);
    try std.testing.expectEqual(@as(usize, 2), pool.size());
}

test "ConstantPool dedup returns same index" {
    const allocator = std.testing.allocator;
    var pool = ConstantPool.init(allocator);
    defer pool.deinit();

    const idx0 = try pool.add("hello", .String);
    const idx1 = try pool.add("world", .String);
    const idx2 = try pool.add("hello", .String); // duplicate — should return idx0
    const idx3 = try pool.add("world", .String); // duplicate — should return idx1
    const idx4 = try pool.add("hello", .Number); // same value, different kind — new index

    try std.testing.expectEqual(@as(u32, 0), idx0);
    try std.testing.expectEqual(@as(u32, 1), idx1);
    try std.testing.expectEqual(idx0, idx2); // dedup
    try std.testing.expectEqual(idx1, idx3); // dedup
    try std.testing.expectEqual(@as(u32, 2), idx4); // new because different kind

    // Pool should only have 3 entries, not 5
    try std.testing.expectEqual(@as(usize, 3), pool.size());
}

test "ViewCompilationUnit basic" {
    const allocator = std.testing.allocator;
    var unit = ViewCompilationUnit.init(allocator, 0, null);
    defer unit.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };
    try unit.create.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try unit.update.append(.{
        .kind = .Advance,
        .xref = 0,
        .source_span = span,
        .data = .{ .Advance = 1 },
    });

    try std.testing.expectEqual(@as(usize, 1), unit.create.len());
    try std.testing.expectEqual(@as(usize, 1), unit.update.len());
}

test "ComponentCompilationJob full" {
    const allocator = std.testing.allocator;
    var job = try ComponentCompilationJob.init(allocator, "MyComponent", .Full);
    defer job.deinit();

    const span = AbsoluteSourceSpan{ .start = 0, .end = 5 };

    // Add creation ops
    try job.root.create.append(.{
        .kind = .ElementStart,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementStart = .{ .name = "div", .namespace = .HTML, .attrs_xref = 0 } },
    });
    try job.root.create.append(.{
        .kind = .Text,
        .xref = 1,
        .source_span = span,
        .data = .{ .Text = .{ .const_index = 0 } },
    });
    try job.root.create.append(.{
        .kind = .ElementEnd,
        .xref = 0,
        .source_span = span,
        .data = .{ .ElementEnd = {} },
    });

    // Add constant
    const ci = try job.addConst("Hello, World!", .String);
    try std.testing.expectEqual(@as(u32, 0), ci);

    const stats = job.stats();
    try std.testing.expectEqual(@as(usize, 3), stats.root_create_ops);
    try std.testing.expectEqual(@as(usize, 1), stats.constants);
}
