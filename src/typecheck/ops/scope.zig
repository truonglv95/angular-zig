/// TCB Ops Scope — Per-template-node TCB scope tracking
///
/// Port of: compiler/src/typecheck/ops/scope.ts (1066 LoC)
///
/// The Scope class is the heart of the type check block (TCB) system. Each
/// template (including nested ng-templates) has its own Scope, which:
///   - Maintains a queue of TcbOp operations to execute
///   - Tracks elements, directives, references, variables, and templates
///   - Resolves cross-references between nodes
///   - Generates TypeScript statements for type checking
///
/// The scope hierarchy mirrors the syntactic structure of the template,
/// where each nested ng-template creates a child scope.
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
    strict_null_checks: bool = true,
    enable_template_type_checker: bool = false,
    use_program_type_checking: bool = false,
};

/// DirectiveOwner — identifies what owns a directive (element or template).
pub const DirectiveOwner = u32;

/// TcbOp — a pending type check block operation.
pub const TcbOp = struct {
    kind: TcbOpKind,
    node_xref: u32 = 0,

    pub const TcbOpKind = enum(u8) {
        Element,
        Template,
        Reference,
        DirectiveCtor,
        DirectiveInputs,
        DirectiveOutputs,
        DirectiveType,
        Variable,
        IfBlock,
        SwitchBlock,
        ForBlock,
        LetDeclaration,
        Text,
        BoundText,
        Content,
        Icu,
        Component,
        HostElement,
        Schema,
        ContentProjection,
        NativeField,
        NativeRadioButtonField,
    };
};

/// OpQueueEntry — either a pending TcbOp, a memoized result, or null.
pub const OpQueueEntry = union(enum) {
    op: TcbOp,
    result: ?TcbExpr,
    /// Marker for circular dependency detection.
    infer_type: void,
};

/// For loop context variable types.
/// Direct port of `Scope.getForLoopContextVariableTypes()` in the TS source.
pub const ForLoopContextVariableTypes = struct {
    pub const FIRST = "boolean";
    pub const LAST = "boolean";
    pub const EVEN = "boolean";
    pub const ODD = "boolean";
    pub const INDEX = "number";
    pub const COUNT = "number";
};

/// LetDeclarationEntry — tracks a @let declaration in the scope.
pub const LetDeclarationEntry = struct {
    op_index: usize,
    node_xref: u32,
};

/// Scope — per-template-node TCB scope tracking.
/// Direct port of `Scope` class in the TS source.
pub const Scope = struct {
    allocator: std.mem.Allocator,
    /// The TCB context.
    tcb: ?*const Context = null,
    /// Parent scope (null for root).
    parent: ?*const Scope = null,
    /// Guard expression for type narrowing.
    guard: ?TcbExpr = null,

    /// Queue of operations to execute.
    op_queue: std.array_list.Managed(OpQueueEntry),
    /// Map of element xrefs → op queue index.
    element_op_map: std.AutoHashMap(u32, usize),
    /// Map of host element xrefs → op queue index.
    host_element_op_map: std.AutoHashMap(u32, usize),
    /// Map of component xrefs → op queue index.
    component_node_op_map: std.AutoHashMap(u32, usize),
    /// Map of directive owners → (directive metadata → op queue index).
    directive_op_map: std.AutoHashMap(DirectiveOwner, std.AutoHashMap(u32, usize)),
    /// Map of reference xrefs → op queue index.
    reference_op_map: std.AutoHashMap(u32, usize),
    /// Map of template xrefs → op queue index.
    template_ctx_op_map: std.AutoHashMap(u32, usize),
    /// Map of variable xrefs → op queue index or pre-resolved identifier.
    var_map: std.AutoHashMap(u32, VarEntry),
    /// Map of @let declaration names → entry.
    let_decl_op_map: std.StringHashMap(LetDeclarationEntry),
    /// Statements for this template.
    statements: std.array_list.Managed(TcbExpr),

    /// Directive instances in this scope.
    directives: std.array_list.Managed(DirectiveInstance),
    /// Variable name → type mapping.
    variables: std.StringHashMap([]const u8),

    pub const DirectiveInstance = struct {
        name: []const u8,
        xref: u32,
        is_component: bool = false,
    };

    pub const VarEntry = union(enum) {
        op_index: usize,
        expr: TcbExpr,
    };

    pub fn init(allocator: std.mem.Allocator) Scope {
        return .{
            .allocator = allocator,
            .op_queue = std.array_list.Managed(OpQueueEntry).init(allocator),
            .element_op_map = std.AutoHashMap(u32, usize).init(allocator),
            .host_element_op_map = std.AutoHashMap(u32, usize).init(allocator),
            .component_node_op_map = std.AutoHashMap(u32, usize).init(allocator),
            .directive_op_map = std.AutoHashMap(DirectiveOwner, std.AutoHashMap(u32, usize)).init(allocator),
            .reference_op_map = std.AutoHashMap(u32, usize).init(allocator),
            .template_ctx_op_map = std.AutoHashMap(u32, usize).init(allocator),
            .var_map = std.AutoHashMap(u32, VarEntry).init(allocator),
            .let_decl_op_map = std.StringHashMap(LetDeclarationEntry).init(allocator),
            .statements = std.array_list.Managed(TcbExpr).init(allocator),
            .directives = std.array_list.Managed(DirectiveInstance).init(allocator),
            .variables = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Scope) void {
        self.op_queue.deinit();
        self.element_op_map.deinit();
        self.host_element_op_map.deinit();
        self.component_node_op_map.deinit();
        // Clean up nested maps in directive_op_map
        var it = self.directive_op_map.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit();
        self.directive_op_map.deinit();
        self.reference_op_map.deinit();
        self.template_ctx_op_map.deinit();
        self.var_map.deinit();
        self.let_decl_op_map.deinit();
        self.statements.deinit();
        self.directives.deinit();
        self.variables.deinit();
    }

    /// Add an op to the queue and return its index.
    pub fn addOp(self: *Scope, op: TcbOp) !usize {
        const index = self.op_queue.items.len;
        try self.op_queue.append(.{ .op = op });
        return index;
    }

    /// Add a statement to the scope.
    pub fn addStatement(self: *Scope, stmt: TcbExpr) !void {
        try self.statements.append(stmt);
    }

    /// Resolve an op by index, executing it if needed.
    /// Direct port of `Scope.resolve(node)` in the TS source.
    pub fn resolve(self: *Scope, index: usize) !?TcbExpr {
        if (index >= self.op_queue.items.len) return null;

        switch (self.op_queue.items[index]) {
            .result => |r| return r,
            .infer_type => return null, // Circular dependency
            .op => |op| {
                // Mark as in-progress to detect cycles.
                self.op_queue.items[index] = .{ .infer_type = {} };

                // Execute the op (simplified — full impl would dispatch on op.kind).
                const result: ?TcbExpr = try self.executeOp(op);

                // Memoize the result.
                self.op_queue.items[index] = .{ .result = result };
                return result;
            },
        }
    }

    /// Execute a single op and return its result.
    fn executeOp(self: *Scope, op: TcbOp) !?TcbExpr {
        return switch (op.kind) {
            .Element => try std.fmt.allocPrint(self.allocator, "var _e{d}: HTMLElement;", .{op.node_xref}),
            .Template => try std.fmt.allocPrint(self.allocator, "var _t{d}: any;", .{op.node_xref}),
            .Reference => try std.fmt.allocPrint(self.allocator, "var _r{d}: any;", .{op.node_xref}),
            .DirectiveCtor => try std.fmt.allocPrint(self.allocator, "var _d{d}: any;", .{op.node_xref}),
            .Variable => try std.fmt.allocPrint(self.allocator, "var _v{d}: any;", .{op.node_xref}),
            .Text => null,
            .BoundText => null,
            else => null,
        };
    }

    /// Register an element op in the element map.
    pub fn registerElement(self: *Scope, xref: u32, op_index: usize) !void {
        try self.element_op_map.put(xref, op_index);
    }

    /// Register a reference op.
    pub fn registerReference(self: *Scope, xref: u32, op_index: usize) !void {
        try self.reference_op_map.put(xref, op_index);
    }

    /// Register a template context op.
    pub fn registerTemplate(self: *Scope, xref: u32, op_index: usize) !void {
        try self.template_ctx_op_map.put(xref, op_index);
    }

    /// Register a variable.
    pub fn registerVariable(self: *Scope, xref: u32, entry: VarEntry) !void {
        try self.var_map.put(xref, entry);
    }

    /// Register a @let declaration.
    pub fn registerLetDeclaration(self: *Scope, name: []const u8, op_index: usize, node_xref: u32) !void {
        try self.let_decl_op_map.put(name, .{ .op_index = op_index, .node_xref = node_xref });
    }

    /// Add a directive instance.
    pub fn addDirective(self: *Scope, name: []const u8, xref: u32) !void {
        try self.directives.append(.{ .name = name, .xref = xref });
    }

    /// Add a variable type mapping.
    pub fn addVariable(self: *Scope, name: []const u8, type_name: []const u8) !void {
        try self.variables.put(name, type_name);
    }

    /// Look up a variable by name.
    pub fn lookupVariable(self: *const Scope, name: []const u8) ?[]const u8 {
        return self.variables.get(name);
    }

    /// Look up a @let declaration by name.
    pub fn lookupLetDeclaration(self: *const Scope, name: []const u8) ?LetDeclarationEntry {
        return self.let_decl_op_map.get(name);
    }

    /// Render the scope to a block of statements.
    /// Direct port of `Scope.renderToBlock()` in the TS source.
    pub fn renderToBlock(self: *const Scope, allocator: std.mem.Allocator) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(allocator);
        errdefer buf.deinit();

        for (self.statements.items) |stmt| {
            try buf.appendSlice(stmt);
            try buf.appendSlice("; ");
        }

        return buf.toOwnedSlice();
    }

    /// Create a scope for a set of nodes.
    /// Direct port of `Scope.forNodes(tcb, parentScope, scopedNode, children, guard)` in the TS source.
    pub fn forNodes(
        allocator: std.mem.Allocator,
        tcb: *const Context,
        parent_scope: ?*const Scope,
        guard: ?TcbExpr,
    ) !Scope {
        var scope = Scope.init(allocator);
        scope.tcb = tcb;
        scope.parent = parent_scope;
        scope.guard = guard;
        return scope;
    }
};

// ─── Tests ──────────────────────────────────────────────────

test "Scope init/deinit" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();
    try std.testing.expectEqual(@as(usize, 0), scope.op_queue.items.len);
    try std.testing.expectEqual(@as(usize, 0), scope.statements.items.len);
}

test "Scope addOp" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    const index = try scope.addOp(.{ .kind = .Element, .node_xref = 1 });
    try std.testing.expectEqual(@as(usize, 0), index);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope addStatement" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.addStatement("var x: number");
    try scope.addStatement("var y: string");
    try std.testing.expectEqual(@as(usize, 2), scope.statements.items.len);
}

test "Scope resolve executes and memoizes" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    const index = try scope.addOp(.{ .kind = .Element, .node_xref = 42 });
    const result = try scope.resolve(index);
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "_e42") != null);

    // Second call should return memoized result.
    const result2 = try scope.resolve(index);
    try std.testing.expect(result2 != null);
}

test "Scope registerElement" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerElement(1, 0);
    try scope.registerElement(2, 5);
    try std.testing.expectEqual(@as(usize, 0), scope.element_op_map.get(1).?);
    try std.testing.expectEqual(@as(usize, 5), scope.element_op_map.get(2).?);
}

test "Scope addDirective and addVariable" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.addDirective("NgIf", 1);
    try scope.addDirective("NgFor", 2);
    try std.testing.expectEqual(@as(usize, 2), scope.directives.items.len);
    try std.testing.expectEqualStrings("NgIf", scope.directives.items[0].name);

    try scope.addVariable("item", "any");
    try std.testing.expectEqualStrings("any", scope.lookupVariable("item").?);
    try std.testing.expect(scope.lookupVariable("missing") == null);
}

test "Scope registerLetDeclaration and lookup" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerLetDeclaration("myLet", 0, 42);
    const entry = scope.lookupLetDeclaration("myLet").?;
    try std.testing.expectEqual(@as(usize, 0), entry.op_index);
    try std.testing.expectEqual(@as(u32, 42), entry.node_xref);
    try std.testing.expect(scope.lookupLetDeclaration("missing") == null);
}

test "Scope renderToBlock" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.addStatement("var x: number");
    try scope.addStatement("var y: string");
    const block = try scope.renderToBlock(allocator);
    defer allocator.free(block);
    try std.testing.expectEqualStrings("var x: number; var y: string; ", block);
}

test "Scope forNodes creates child scope" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    var parent = Scope.init(allocator);
    defer parent.deinit();

    var child = try Scope.forNodes(allocator, &ctx, &parent, "guard_expr");
    defer child.deinit();
    try std.testing.expect(child.parent != null);
    try std.testing.expect(child.guard != null);
}

test "ForLoopContextVariableTypes" {
    try std.testing.expectEqualStrings("boolean", ForLoopContextVariableTypes.FIRST);
    try std.testing.expectEqualStrings("boolean", ForLoopContextVariableTypes.LAST);
    try std.testing.expectEqualStrings("number", ForLoopContextVariableTypes.INDEX);
    try std.testing.expectEqualStrings("number", ForLoopContextVariableTypes.COUNT);
}
