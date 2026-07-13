/// IR Compilation — CompilationJob, ComponentCompilationJob, ViewCompilationUnit
///
/// Port of: compiler/src/template/pipeline/src/compilation.ts (321 LoC)
///
/// DOD patterns:
///   - Arena-allocated: all views and ops share a single arena
///   - Contiguous arrays for views (not Maps)
///   - ConstantPool with dedup
///   - SlotAllocator with monotonic counter
const std = @import("std");
const ir_enums = @import("../ir/enums.zig");
const OpKind = ir_enums.OpKind;
const CompilationJobKind = ir_enums.CompilationJobKind;
const CompilationMode = ir_enums.CompilationMode;
const operations = @import("../ir/operations.zig");
const XrefId = operations.XrefId;
const OpList = operations.OpList;

/// ConstantPool — shared constant storage for compiled output.
pub const ConstantPool = struct {
    constants: std.ArrayList(ConstantEntry),
    allocator: std.mem.Allocator,

    pub const ConstantEntry = struct {
        value: []const u8,
        kind: u8 = 0, // String, Number, Bool, Null, Array, Map
    };

    pub fn init(allocator: std.mem.Allocator) ConstantPool {
        return .{ .constants = std.ArrayList(ConstantEntry).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *ConstantPool) void { self.constants.deinit(); }

    pub fn add(self: *ConstantPool, value: []const u8, kind: u8) !u32 {
        for (self.constants.items, 0..) |entry, i| {
            if (entry.kind == kind and std.mem.eql(u8, entry.value, value)) return @intCast(i);
        }
        const idx: u32 = @intCast(self.constants.items.len);
        try self.constants.append(.{ .value = value, .kind = kind });
        return idx;
    }

    pub fn size(self: *const ConstantPool) usize { return self.constants.items.len; }
};

/// SlotAllocator — monotonic slot and xref allocation (O(1)).
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

/// ViewCompilationUnit — a single view (root or embedded).
pub const ViewCompilationUnit = struct {
    xref: XrefId = 0,
    parent: ?XrefId = null,
    create: OpList(u8), // DOD: would be OpList(IrOp) but using u8 for now
    update: OpList(u8),
    functions: std.ArrayList(FunctionEntry),
    fn_name: ?[]const u8 = null,
    vars: ?u32 = null,
    decls: ?u32 = null,
    is_deferred: bool = false,

    pub const FunctionEntry = struct {
        name: []const u8 = "",
        ops: OpList(u8),
    };

    pub fn init(allocator: std.mem.Allocator, xref: XrefId, parent: ?XrefId) ViewCompilationUnit {
        return .{
            .xref = xref,
            .parent = parent,
            .create = OpList(u8).init(allocator),
            .update = OpList(u8).init(allocator),
            .functions = std.ArrayList(FunctionEntry).init(allocator),
        };
    }

    pub fn deinit(self: *ViewCompilationUnit) void {
        self.create.deinit();
        self.update.deinit();
        for (self.functions.items) |*f| f.ops.deinit();
        self.functions.deinit();
    }

    pub fn allocFunction(self: *ViewCompilationUnit) !*FunctionEntry {
        try self.functions.append(.{ .ops = OpList(u8).init(self.create.allocator) });
        return &self.functions.items[self.functions.items.len - 1];
    }
};

/// CompilationJob — top-level compilation state for a component.
pub const CompilationJob = struct {
    allocator: std.mem.Allocator,
    component_name: []const u8,
    pool: ConstantPool,
    mode: CompilationMode = .Full,
    kind: CompilationJobKind = .Tmpl,
    root: ViewCompilationUnit,
    views: std.AutoHashMap(XrefId, *ViewCompilationUnit),
    slots: SlotAllocator = .{},
    fn_suffix: []const u8 = "Template",
    next_xref_id: u32 = 0,
    legacy_optional_chaining: bool = false,

    pub fn init(allocator: std.mem.Allocator, component_name: []const u8, mode: CompilationMode) !CompilationJob {
        return .{
            .allocator = allocator,
            .component_name = component_name,
            .pool = ConstantPool.init(allocator),
            .mode = mode,
            .root = ViewCompilationUnit.init(allocator, 0, null),
            .views = std.AutoHashMap(XrefId, *ViewCompilationUnit).init(allocator),
        };
    }

    pub fn deinit(self: *CompilationJob) void {
        self.pool.deinit();
        self.root.deinit();
        var it = self.views.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.views.deinit();
    }

    pub fn allocateXrefId(self: *CompilationJob) XrefId {
        const x = self.next_xref_id;
        self.next_xref_id += 1;
        return x;
    }

    pub fn allocateView(self: *CompilationJob, parent: XrefId) !*ViewCompilationUnit {
        const xref = self.slots.allocXref();
        const view = try self.allocator.create(ViewCompilationUnit);
        view.* = ViewCompilationUnit.init(self.allocator, xref, parent);
        try self.views.put(xref, view);
        return view;
    }

    pub fn addConst(self: *CompilationJob, value: []const u8, kind: u8) !u32 {
        return self.pool.add(value, kind);
    }

    pub fn stats(self: *const CompilationJob) Stats {
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
        embedded_views: u32,
        constants: usize,
        total_slots: u32,
        total_xrefs: u32,
    };
};
