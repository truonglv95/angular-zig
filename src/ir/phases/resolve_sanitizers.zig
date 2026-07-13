/// resolve_sanitizers phase
///
/// Port of: template/pipeline/src/phases/resolve_sanitizers.ts
///
/// Both phase — migrated from impl.zig
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
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

const schema = @import("../../schema/registry.zig");

// ─── Shared helpers ──
const isJavascriptUrl = helpers.isJavascriptUrl;
const helpers = @import("helpers.zig");
const SecurityContext = schema.SecurityContext;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    const registry = schema.SchemaRegistry{};

    // Process create ops (Attribute ops)
    {
        const items = view.create.ops.items;
        for (items) |*op| {
            if (op.kind == .Attribute) {
                const attr = &op.data.Attribute;
                if (attr.security_context != null) continue; // already marked

                // O(1) comptime StaticStringMap lookup
                if (registry.getPropertySecurityContext(attr.name)) |ctx| {
                    attr.security_context = @intFromEnum(ctx);
                }

                // Check for javascript: URLs on href/src (runtime value check)
                if ((std.mem.eql(u8, attr.name, "href") or
                    std.mem.eql(u8, attr.name, "src")) and
                    isJavascriptUrl(attr.value))
                {
                    attr.security_context = @intFromEnum(SecurityContext.HTML);
                }
            }
        }
    }

    // Process update ops (Property, DomProperty, Binding, InterpolateText)
    {
        const items = view.update.ops.items;
        for (items) |*op| {
            switch (op.data) {
                .Property => |*p| {
                    if (p.security_context != null) continue;
                    // O(1) comptime lookup — covers innerHTML, outerHTML, href, src, etc.
                    if (registry.getPropertySecurityContext(p.name)) |ctx| {
                        p.security_context = @intFromEnum(ctx);
                    }
                },
                .DomProperty => |*d| {
                    if (d.security_context != null) continue;
                    if (registry.getPropertySecurityContext(d.name)) |ctx| {
                        d.security_context = @intFromEnum(ctx);
                    }
                },
                .Binding => |*b| {
                    // Bindings can also target security-sensitive properties
                    if (registry.getPropertySecurityContext(b.name)) |ctx| {
                        _ = ctx;
                    }
                },
                .InterpolateText => |*it| {
                    if (it.security_context != null) continue;
                    // All text interpolations render into the DOM → HTML context
                    it.security_context = @intFromEnum(SecurityContext.HTML);
                },
                else => {},
            }
        }
    }
}
