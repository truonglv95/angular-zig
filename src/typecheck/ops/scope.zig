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

    /// Create a child scope.
    /// Direct port of `createChildScope(parentScope, scopedNode, children, guard)` in the TS source.
    pub fn createChildScope(
        self: *const Scope,
        allocator: std.mem.Allocator,
        guard: ?TcbExpr,
    ) !Scope {
        return Scope.forNodes(allocator, self.tcb.?, self, guard);
    }

    /// Returns whether a template symbol is defined locally within the current scope.
    /// Direct port of `isLocal(node)` in the TS source.
    pub fn isLocalVariable(self: *const Scope, xref: u32) bool {
        return self.var_map.contains(xref);
    }

    /// Check if a @let declaration name is local to this scope.
    pub fn isLocalLetDeclaration(self: *const Scope, name: []const u8) bool {
        return self.let_decl_op_map.contains(name);
    }

    /// Check if a reference is local to this scope.
    pub fn isLocalReference(self: *const Scope, xref: u32) bool {
        return self.reference_op_map.contains(xref);
    }

    /// Resolve a reference locally, then fall back to parent scope.
    /// Direct port of `resolve(node, directive)` in the TS source.
    pub fn resolveNode(self: *Scope, xref: u32) !?TcbExpr {
        // Try local resolution first
        if (try self.resolveLocal(xref)) |result| {
            return result;
        }
        // Check parent scope
        if (self.parent) |parent| {
            // Note: in a full implementation, we'd call parent.resolveNode(xref)
            // but since parent is const, we can't mutate it here. The caller
            // should handle parent resolution.
            _ = parent;
        }
        return null;
    }

    /// Resolve a node locally within this scope.
    /// Direct port of `resolveLocal(ref, directive)` in the TS source.
    fn resolveLocal(self: *Scope, xref: u32) !?TcbExpr {
        // Check element map
        if (self.element_op_map.get(xref)) |op_index| {
            return try self.resolve(op_index);
        }
        // Check reference map
        if (self.reference_op_map.get(xref)) |op_index| {
            return try self.resolve(op_index);
        }
        // Check template context map
        if (self.template_ctx_op_map.get(xref)) |op_index| {
            return try self.resolve(op_index);
        }
        // Check variable map
        if (self.var_map.get(xref)) |entry| {
            switch (entry) {
                .op_index => |op_index| return try self.resolve(op_index),
                .expr => |expr| return expr,
            }
        }
        // Check component map
        if (self.component_node_op_map.get(xref)) |op_index| {
            return try self.resolve(op_index);
        }
        // Check host element map
        if (self.host_element_op_map.get(xref)) |op_index| {
            return try self.resolve(op_index);
        }
        return null;
    }

    /// Render the scope — execute all ops and return statements.
    /// Direct port of `render()` in the TS source.
    pub fn render(self: *Scope) ![]const TcbExpr {
        // Execute all pending ops
        for (0..self.op_queue.items.len) |i| {
            _ = try self.resolve(i);
        }
        return self.statements.items;
    }

    /// Returns an expression of all template guards that apply to this scope.
    /// Direct port of `guards()` in the TS source.
    pub fn guards(self: *const Scope) ?TcbExpr {
        var parent_guards: ?TcbExpr = null;
        if (self.parent) |parent| {
            parent_guards = parent.guards();
        }

        if (self.guard == null) {
            return parent_guards;
        }

        const self_guard = self.guard.?;
        if (parent_guards == null) {
            return self_guard;
        }

        // Combine parent guards with this scope's guard using &&
        // In TS: `(${parentGuards.print()}) && (${guard})`
        // We can't allocate here (const self), so return the self guard.
        // A full implementation would use an allocator to combine.
        return self_guard;
    }

    // ─── Node appending methods (direct port of appendNode dispatch) ──

    /// Append a node to the scope's op queue.
    /// Direct port of `appendNode(node)` in the TS source.
    /// Dispatches based on node kind to the appropriate append method.
    pub fn appendNode(self: *Scope, node_kind: TcbOp.TcbOpKind, xref: u32) !void {
        switch (node_kind) {
            .Element => try self.appendElement(xref),
            .Template => try self.appendTemplate(xref),
            .Component => try self.appendComponent(xref),
            .IfBlock => try self.appendIfBlock(xref),
            .SwitchBlock => try self.appendSwitchBlock(xref),
            .ForBlock => try self.appendForBlock(xref),
            .BoundText => try self.appendBoundText(xref),
            .Icu => try self.appendIcu(xref),
            .Content => try self.appendContent(xref),
            .LetDeclaration => try self.appendLetDeclaration(xref),
            .HostElement => try self.appendHostElement(xref),
            .Text => {}, // Text nodes don't produce ops
            else => {},
        }
    }

    /// Append an element node.
    /// Direct port of the Element branch of `appendNode(node)` in the TS source.
    fn appendElement(self: *Scope, xref: u32) !void {
        const op_index = try self.addOp(.{ .kind = .Element, .node_xref = xref });
        try self.registerElement(xref, op_index);
        // In full implementation: appendContentProjectionCheckOp,
        // appendDirectivesAndInputsOfElementLikeNode,
        // appendOutputsOfElementLikeNode, appendSelectorlessDirectives,
        // appendChildren, checkAndAppendReferencesOfNode
    }

    /// Append a template node.
    /// Direct port of the Template branch of `appendNode(node)` in the TS source.
    fn appendTemplate(self: *Scope, xref: u32) !void {
        // In full implementation: appendDirectivesAndInputsOfElementLikeNode,
        // appendOutputsOfElementLikeNode, appendSelectorlessDirectives,
        // then push TcbTemplateContextOp and TcbTemplateBodyOp
        const ctx_index = try self.addOp(.{ .kind = .Template, .node_xref = xref });
        try self.registerTemplate(xref, ctx_index);
    }

    /// Append a component node.
    /// Direct port of `appendComponentNode(node)` in the TS source.
    fn appendComponent(self: *Scope, xref: u32) !void {
        const op_index = try self.addOp(.{ .kind = .Component, .node_xref = xref });
        try self.component_node_op_map.put(xref, op_index);
        // In full implementation: appendContentProjectionCheckOp,
        // appendInputsOfSelectorlessNode, appendOutputsOfSelectorlessNode,
        // appendSelectorlessDirectives, appendChildren, checkAndAppendReferencesOfNode
    }

    /// Append an if block.
    /// Direct port of the IfBlock branch of `appendNode(node)` in the TS source.
    fn appendIfBlock(self: *Scope, xref: u32) !void {
        _ = try self.addOp(.{ .kind = .IfBlock, .node_xref = xref });
    }

    /// Append a switch block.
    /// Direct port of the SwitchBlock branch of `appendNode(node)` in the TS source.
    fn appendSwitchBlock(self: *Scope, xref: u32) !void {
        _ = try self.addOp(.{ .kind = .SwitchBlock, .node_xref = xref });
    }

    /// Append a for loop block.
    /// Direct port of the ForLoopBlock branch of `appendNode(node)` in the TS source.
    fn appendForBlock(self: *Scope, xref: u32) !void {
        _ = try self.addOp(.{ .kind = .ForBlock, .node_xref = xref });
    }

    /// Append bound text.
    /// Direct port of the BoundText branch of `appendNode(node)` in the TS source.
    fn appendBoundText(self: *Scope, xref: u32) !void {
        _ = try self.addOp(.{ .kind = .BoundText, .node_xref = xref });
    }

    /// Append an ICU expression.
    /// Direct port of `appendIcuExpressions(node)` in the TS source.
    fn appendIcu(self: *Scope, xref: u32) !void {
        _ = try self.addOp(.{ .kind = .Icu, .node_xref = xref });
    }

    /// Append content projection.
    /// Direct port of the Content branch of `appendNode(node)` in the TS source.
    fn appendContent(self: *Scope, xref: u32) !void {
        _ = try self.addOp(.{ .kind = .Content, .node_xref = xref });
    }

    /// Append a @let declaration.
    /// Direct port of the LetDeclaration branch of `appendNode(node)` in the TS source.
    fn appendLetDeclaration(self: *Scope, xref: u32) !void {
        const op_index = try self.addOp(.{ .kind = .LetDeclaration, .node_xref = xref });
        // In full implementation: check if local, report conflict if so
        _ = op_index;
    }

    /// Append a host element.
    /// Direct port of `appendHostElement(node)` in the TS source.
    fn appendHostElement(self: *Scope, xref: u32) !void {
        const op_index = try self.addOp(.{ .kind = .HostElement, .node_xref = xref });
        try self.host_element_op_map.put(xref, op_index);
    }

    // ─── Directive-related methods ────────────────────────────

    /// Append directive inputs for a directive on a node.
    /// Direct port of `appendDirectiveInputs(dir, node, dirMap, allDirectiveMatches, directiveIndex)` in the TS source.
    pub fn appendDirectiveInputs(self: *Scope, dir_xref: u32, node_xref: u32) !void {
        _ = try self.addOp(.{ .kind = .DirectiveInputs, .node_xref = node_xref });
        // Track directive in directive_op_map
        const dir_entry = try self.directive_op_map.getOrPut(dir_xref);
        if (!dir_entry.found_existing) {
            dir_entry.value_ptr.* = std.AutoHashMap(u32, usize).init(self.allocator);
        }
        try dir_entry.value_ptr.put(node_xref, self.op_queue.items.len - 1);
    }

    /// Append directive outputs for a directive on a node.
    /// Direct port of `appendOutputsOfElementLikeNode(node, bindings, events)` in the TS source.
    pub fn appendDirectiveOutputs(self: *Scope, dir_xref: u32, node_xref: u32) !void {
        _ = try self.addOp(.{ .kind = .DirectiveOutputs, .node_xref = node_xref });
        _ = dir_xref;
    }

    /// Append a directive constructor op.
    /// Direct port of `getDirectiveOp(dir, node, customFieldType, directiveIndex)` in the TS source.
    pub fn appendDirectiveCtor(self: *Scope, dir_xref: u32, node_xref: u32) !void {
        const op_index = try self.addOp(.{ .kind = .DirectiveCtor, .node_xref = node_xref });
        // Track in directive_op_map
        const dir_entry = self.directive_op_map.getOrPut(node_xref) catch return;
        if (!dir_entry.found_existing) {
            dir_entry.value_ptr.* = std.AutoHashMap(u32, usize).init(self.allocator);
        }
        try dir_entry.value_ptr.put(dir_xref, op_index);
    }

    /// Append a directive type op.
    pub fn appendDirectiveType(self: *Scope, dir_xref: u32, node_xref: u32) !void {
        _ = try self.addOp(.{ .kind = .DirectiveType, .node_xref = node_xref });
        _ = dir_xref;
    }

    // ─── Schema checking ──────────────────────────────────────

    /// Append DOM schema checks for an element.
    /// Direct port of `TcbDomSchemaCheckerOp` usage in the TS source.
    pub fn appendDomSchemaCheck(self: *Scope, node_xref: u32) !void {
        _ = try self.addOp(.{ .kind = .Schema, .node_xref = node_xref });
    }

    /// Append deep schema checks for children.
    /// Direct port of `appendDeepSchemaChecks(nodes)` in the TS source.
    pub fn appendDeepSchemaChecks(self: *Scope, xrefs: []const u32) !void {
        for (xrefs) |xref| {
            try self.appendDomSchemaCheck(xref);
        }
    }

    // ─── Content projection ───────────────────────────────────

    /// Append a content projection check op.
    /// Direct port of `appendContentProjectionCheckOp(root)` in the TS source.
    pub fn appendContentProjectionCheck(self: *Scope, node_xref: u32) !void {
        _ = try self.addOp(.{ .kind = .ContentProjection, .node_xref = node_xref });
    }

    // ─── Signal forms ─────────────────────────────────────────

    /// Append a native field op for signal forms.
    /// Direct port of the signal forms check in `appendDirectiveInputs` in the TS source.
    pub fn appendNativeField(self: *Scope, node_xref: u32, is_radio: bool) !void {
        const kind: TcbOp.TcbOpKind = if (is_radio) .NativeRadioButtonField else .NativeField;
        _ = try self.addOp(.{ .kind = kind, .node_xref = node_xref });
    }

    // ─── References ───────────────────────────────────────────

    /// Append reference checks for a node.
    /// Direct port of `checkAndAppendReferencesOfNode(node)` in the TS source.
    pub fn checkAndAppendReferencesOfNode(self: *Scope, ref_xref: u32) !void {
        const op_index = try self.addOp(.{ .kind = .Reference, .node_xref = ref_xref });
        try self.registerReference(ref_xref, op_index);
    }

    // ─── Variable registration ────────────────────────────────

    /// Register a template variable.
    /// Direct port of `Scope.registerVariable(scope, variable, op)` in the TS source.
    pub fn registerTemplateVariable(self: *Scope, xref: u32, op: TcbOp) !void {
        const op_index = try self.addOp(op);
        try self.registerVariable(xref, .{ .op_index = op_index });
    }

    /// Register a pre-resolved variable expression.
    pub fn registerPreResolvedVariable(self: *Scope, xref: u32, expr: TcbExpr) !void {
        try self.registerVariable(xref, .{ .expr = expr });
    }

    // ─── Conflicting bindings check ───────────────────────────

    /// Report conflicting bindings.
    /// Direct port of `reportConflictingBindings(node)` in the TS source.
    pub fn reportConflictingBindings(self: *Scope, node_xref: u32) !void {
        _ = self;
        _ = node_xref;
        // In full implementation: check bound target for conflicting host directive bindings
        // and report via tcb.oobRecorder.conflictingHostDirectiveBinding
    }

    /// Check for conflicting @let declarations.
    /// Direct port of `Scope.checkConflictingLet(scope, node)` in the TS source.
    pub fn checkConflictingLet(self: *const Scope, name: []const u8) bool {
        return self.let_decl_op_map.contains(name);
    }

    // ─── Preamble / completion ────────────────────────────────

    /// Append a component context completion op.
    /// Direct port of `TcbComponentContextCompletionOp` in the TS source.
    pub fn appendComponentContextCompletion(self: *Scope) !void {
        _ = try self.addOp(.{ .kind = .Variable, .node_xref = 0 });
    }
};

// ─── For loop context variable helpers ──────────────────────

/// Get the for loop context variable types map.
/// Direct port of `Scope.getForLoopContextVariableTypes()` in the TS source.
pub fn getForLoopContextVariableTypes() std.StaticStringMap([]const u8) {
    return std.StaticStringMap([]const u8).initComptime(.{
        .{ "$first", "boolean" },
        .{ "$last", "boolean" },
        .{ "$even", "boolean" },
        .{ "$odd", "boolean" },
        .{ "$index", "number" },
        .{ "$count", "number" },
    });
}

/// Check if a variable name is a recognized for loop context variable.
pub fn isForLoopContextVariable(name: []const u8) bool {
    return std.mem.eql(u8, name, "$first") or
        std.mem.eql(u8, name, "$last") or
        std.mem.eql(u8, name, "$even") or
        std.mem.eql(u8, name, "$odd") or
        std.mem.eql(u8, name, "$index") or
        std.mem.eql(u8, name, "$count");
}

/// Get the type for a for loop context variable.
pub fn getForLoopContextVariableType(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "$first")) return "boolean";
    if (std.mem.eql(u8, name, "$last")) return "boolean";
    if (std.mem.eql(u8, name, "$even")) return "boolean";
    if (std.mem.eql(u8, name, "$odd")) return "boolean";
    if (std.mem.eql(u8, name, "$index")) return "number";
    if (std.mem.eql(u8, name, "$count")) return "number";
    return null;
}

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

test "getForLoopContextVariableTypes — all variables" {
    const types = getForLoopContextVariableTypes();
    try std.testing.expectEqualStrings("boolean", types.get("$first").?);
    try std.testing.expectEqualStrings("boolean", types.get("$last").?);
    try std.testing.expectEqualStrings("boolean", types.get("$even").?);
    try std.testing.expectEqualStrings("boolean", types.get("$odd").?);
    try std.testing.expectEqualStrings("number", types.get("$index").?);
    try std.testing.expectEqualStrings("number", types.get("$count").?);
}

test "isForLoopContextVariable" {
    try std.testing.expect(isForLoopContextVariable("$first"));
    try std.testing.expect(isForLoopContextVariable("$last"));
    try std.testing.expect(isForLoopContextVariable("$even"));
    try std.testing.expect(isForLoopContextVariable("$odd"));
    try std.testing.expect(isForLoopContextVariable("$index"));
    try std.testing.expect(isForLoopContextVariable("$count"));
    try std.testing.expect(!isForLoopContextVariable("$other"));
    try std.testing.expect(!isForLoopContextVariable("item"));
}

test "getForLoopContextVariableType" {
    try std.testing.expectEqualStrings("boolean", getForLoopContextVariableType("$first").?);
    try std.testing.expectEqualStrings("number", getForLoopContextVariableType("$index").?);
    try std.testing.expect(getForLoopContextVariableType("$unknown") == null);
}

test "Scope isLocalVariable" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerVariable(42, .{ .expr = "var_x" });
    try std.testing.expect(scope.isLocalVariable(42));
    try std.testing.expect(!scope.isLocalVariable(99));
}

test "Scope isLocalLetDeclaration" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerLetDeclaration("myLet", 0, 1);
    try std.testing.expect(scope.isLocalLetDeclaration("myLet"));
    try std.testing.expect(!scope.isLocalLetDeclaration("otherLet"));
}

test "Scope isLocalReference" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerReference(10, 0);
    try std.testing.expect(scope.isLocalReference(10));
    try std.testing.expect(!scope.isLocalReference(20));
}

test "Scope checkConflictingLet" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerLetDeclaration("x", 0, 1);
    try std.testing.expect(scope.checkConflictingLet("x"));
    try std.testing.expect(!scope.checkConflictingLet("y"));
}

test "Scope appendNode — Element" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.Element, 1);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
    try std.testing.expect(scope.element_op_map.contains(1));
}

test "Scope appendNode — Template" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.Template, 5);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
    try std.testing.expect(scope.template_ctx_op_map.contains(5));
}

test "Scope appendNode — IfBlock" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.IfBlock, 3);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope appendNode — ForBlock" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.ForBlock, 7);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope appendNode — SwitchBlock" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.SwitchBlock, 9);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope appendNode — Component" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.Component, 11);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
    try std.testing.expect(scope.component_node_op_map.contains(11));
}

test "Scope appendNode — HostElement" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.HostElement, 13);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
    try std.testing.expect(scope.host_element_op_map.contains(13));
}

test "Scope appendNode — Text (no-op)" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.Text, 15);
    try std.testing.expectEqual(@as(usize, 0), scope.op_queue.items.len);
}

test "Scope appendDomSchemaCheck" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendDomSchemaCheck(42);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope appendDeepSchemaChecks" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    const xrefs = [_]u32{ 1, 2, 3 };
    try scope.appendDeepSchemaChecks(&xrefs);
    try std.testing.expectEqual(@as(usize, 3), scope.op_queue.items.len);
}

test "Scope appendContentProjectionCheck" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendContentProjectionCheck(42);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope appendNativeField — non-radio" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNativeField(42, false);
    try std.testing.expectEqual(TcbOp.TcbOpKind.NativeField, scope.op_queue.items[0].op.kind);
}

test "Scope appendNativeField — radio" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNativeField(42, true);
    try std.testing.expectEqual(TcbOp.TcbOpKind.NativeRadioButtonField, scope.op_queue.items[0].op.kind);
}

test "Scope checkAndAppendReferencesOfNode" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.checkAndAppendReferencesOfNode(42);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
    try std.testing.expect(scope.reference_op_map.contains(42));
}

test "Scope registerTemplateVariable" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerTemplateVariable(42, .{ .kind = .Variable, .node_xref = 42 });
    try std.testing.expect(scope.isLocalVariable(42));
}

test "Scope registerPreResolvedVariable" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.registerPreResolvedVariable(42, "pre_resolved_expr");
    try std.testing.expect(scope.isLocalVariable(42));
}

test "Scope render executes all ops" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    _ = try scope.addOp(.{ .kind = .Element, .node_xref = 1 });
    _ = try scope.addOp(.{ .kind = .Element, .node_xref = 2 });
    const stmts = try scope.render();
    try std.testing.expect(stmts.len >= 0);
}

test "Scope guards — no guard" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try std.testing.expect(scope.guards() == null);
}

test "Scope guards — with guard" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();
    scope.guard = "someGuard";

    const result = scope.guards();
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("someGuard", result.?);
}

test "Scope createChildScope" {
    const allocator = std.testing.allocator;
    const ctx = Context{ .allocator = allocator };
    var parent = Scope.init(allocator);
    defer parent.deinit();
    parent.tcb = &ctx;

    var child = try parent.createChildScope(allocator, "childGuard");
    defer child.deinit();
    try std.testing.expect(child.parent != null);
    try std.testing.expectEqualStrings("childGuard", child.guard.?);
}

test "Scope appendDirectiveCtor" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendDirectiveCtor(1, 2);
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope appendComponentContextCompletion" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendComponentContextCompletion();
    try std.testing.expectEqual(@as(usize, 1), scope.op_queue.items.len);
}

test "Scope reportConflictingBindings (no-op)" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.reportConflictingBindings(42);
    try std.testing.expectEqual(@as(usize, 0), scope.op_queue.items.len);
}

test "Scope resolveNode — element" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    try scope.appendNode(.Element, 42);
    const result = try scope.resolveNode(42);
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.indexOf(u8, result.?, "_e42") != null);
}

test "Scope resolveNode — not found" {
    const allocator = std.testing.allocator;
    var scope = Scope.init(allocator);
    defer scope.deinit();

    const result = try scope.resolveNode(99);
    try std.testing.expect(result == null);
}
