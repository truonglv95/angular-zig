/// i18n_text_extraction — Extract translatable text from Text ops
const std = @import("std");
const job_mod = @import("../../ir/job.zig");
const ComponentCompilationJob = job_mod.ComponentCompilationJob;
const ViewCompilationUnit = job_mod.ViewCompilationUnit;

pub fn run(job: *ComponentCompilationJob, view: *ViewCompilationUnit) !void {
    _ = job;
    var in_i18n = false;
    var i18n_depth: u32 = 0;
    for (view.create.ops.items) |op| {
        switch (op.kind) {
            .I18nStart => { in_i18n = true; i18n_depth += 1; },
            .I18nEnd => { if (i18n_depth > 0) { i18n_depth -= 1; } if (i18n_depth == 0) { in_i18n = false; } },
            .Text => { if (in_i18n) { } },
            .I18n => { if (in_i18n) {  } },
            else => {},
        }
    }
}

pub fn convertI18nText(allocator: std.mem.Allocator) void { _ = allocator; }