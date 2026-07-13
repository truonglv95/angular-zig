/// namespace phase
///
/// Port of: template/pipeline/src/phases/namespace.ts
///
/// Create phase — migrated from impl.zig
const std = @import("std");

const job_mod = @import("../job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

const ir_ops = @import("../ops.zig");
const IrOp = ir_ops.IrOp;
const OpKind = ir_ops.OpKind;
const OpData = ir_ops.OpData;

const ir_enums = @import("../enums.zig");
const CompilationKind = ir_enums.CompilationKind;

const ir_expr = @import("../expression.zig");
const IrExpr = ir_expr.IrExpr;

const source_span = @import("../../source_span.zig");

// ─── Shared helpers ──
const MAX_DEPTH = helpers.MAX_DEPTH;
const helpers = @import("helpers.zig");
const html_tags = @import("../../ml_parser/tags.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const Namespace = ir_ops.Namespace;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    // Stack of namespaces per depth (stack-allocated)
    var ns_stack: [MAX_DEPTH]Namespace = undefined;
    @memset(&ns_stack, Namespace.HTML);
    var depth: u32 = 0;

    const items = view.create.ops.items;
    for (items) |op| {
        switch (op.kind) {
            .ElementStart => {
                const elem_ns = op.data.ElementStart.namespace;
                const parent_ns = if (depth > 0) ns_stack[depth - 1] else Namespace.HTML;
                // Insert NamespaceDeclare when namespace changes
                if (elem_ns != parent_ns) {
                    try result.append(.{
                        .kind = .NamespaceDeclare,
                        .xref = op.xref,
                        .source_span = op.source_span,
                        .data = .{ .NamespaceDeclare = elem_ns },
                    });
                }
                if (depth < MAX_DEPTH) {
                    ns_stack[depth] = elem_ns;
                }
                depth += 1;
                try result.append(op);
            },
            .ElementEnd => {
                try result.append(op);
                if (depth > 0) depth -= 1;
            },
            .ContainerStart => {
                depth += 1;
                try result.append(op);
            },
            .ContainerEnd => {
                try result.append(op);
                if (depth > 0) depth -= 1;
            },
            else => {
                try result.append(op);
            },
        }
    }

    view.create.ops.deinit();
    view.create.ops = result;
}


// ─── Merged from declare_namespaces.zig (1:1 structure consolidation) ──
pub fn declareNamespaces(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const allocator = view.create.allocator;
    var result = std.array_list.Managed(IrOp).init(allocator);
    errdefer result.deinit();

    // Track the last emitted namespace to avoid redundant declarations
    var last_ns: Namespace = .HTML;

    const items = view.create.ops.items;
    for (items) |op| {
        if (op.kind == .ElementStart) {
            const elem_ns = op.data.ElementStart.namespace;
            // Only emit NamespaceDeclare when transitioning away from HTML
            // (the emitNamespaceChanges phase handles depth-based transitions;
            // this phase ensures the first transition is always declared)
            if (elem_ns != .HTML and elem_ns != last_ns) {
                // Verify the element name matches the declared namespace
                // using comptime StaticStringMap for consistency
                const name = op.data.ElementStart.name;
                const is_svg = html_tags.SVG_ELEMENTS.has(name);
                const is_mathml = html_tags.MATHML_ELEMENTS.has(name);

                if ((elem_ns == .SVG and is_svg) or
                    (elem_ns == .MathML and is_mathml) or
                    (!is_svg and !is_mathml))
                {
                    // Element name is consistent with namespace (or unknown
                    // element in a foreign namespace) — emit declaration
                    try result.append(.{
                        .kind = .NamespaceDeclare,
                        .xref = op.xref,
                        .source_span = op.source_span,
                        .data = .{ .NamespaceDeclare = elem_ns },
                    });
                    last_ns = elem_ns;
                }
            }
        } else if (op.kind == .ElementEnd) {
            // When closing a foreign-namespace element, return to HTML
            // Check if we were in a non-HTML namespace by looking at last_ns
            // This is a simple heuristic; emitNamespaceChanges does the full
            // depth tracking.
            if (last_ns != .HTML) {
                // Check if this end closes the namespace scope
                // (simplified: always return to HTML on ElementEnd
                //  when we're in a foreign namespace)
                // Don't emit a declaration here — the return to HTML is implicit
                // The emitNamespaceChanges phase will handle this correctly.
            }
        }

        try result.append(op);
    }

    view.create.ops.deinit();
    view.create.ops = result;
}
