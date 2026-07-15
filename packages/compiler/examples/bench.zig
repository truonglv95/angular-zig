/// Benchmark: Compile many templates to measure performance
///
/// Usage: zig build bench
///
/// DOD: Minimal overhead — each iteration creates a fresh Compiler,
/// runs the full pipeline, and properly frees all memory.
const std = @import("std");

fn getNsTimestamp() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return @as(i64, ts.sec) * @as(i64, 1_000_000_000) + @as(i64, ts.nsec);
}
const Compiler = @import("angular-compiler").Compiler;

const TEMPLATES = [_][]const u8{
    "<div></div>",
    "<span>Hello</span>",
    "<div><p>text</p></div>",
    "<ul><li *ngFor='let item of items'>{{ item }}</li></ul>",
    "<div class='a'><span id='b'>{{ x }}</span></div>",
    "<table><tr><td>Cell</td></tr></table>",
    "<form><input type='text'><button>Submit</button></form>",
    "<div><h1>Title</h1><p *ngIf='show'>Content</p></div>",
    "<nav><a href='/'>Home</a><a href='/about'>About</a></nav>",
    "<section><header><h2>Section</h2></header><div>Body</div></section>",
};

/// A more complex template for realistic benchmarking.
const COMPLEX_TEMPLATE =
    \\<div class="container" [title]="heading">
    \\  <header>
    \\    <h1>{{ title }}</h1>
    \\    <nav>
    \\      <a *ngFor="let link of navLinks" [routerLink]="link.path">{{ link.label }}</a>
    \\    </nav>
    \\  </header>
    \\  <main>
    \\    <div *ngIf="showSidebar" class="sidebar">
    \\      <ul>
    \\        <li *ngFor="let item of sidebarItems">{{ item }}</li>
    \\      </ul>
    \\    </div>
    \\    <div class="content">
    \\      <article *ngFor="let post of posts; track post.id">
    \\        <h2>{{ post.title }}</h2>
    \\        <p [innerHTML]="post.content | async"></p>
    \\        <footer>
    \\          <span class="date">{{ post.date | date:'short' }}</span>
    \\          <span class="author">{{ post.author }}</span>
    \\        </footer>
    \\      </article>
    \\    </div>
    \\  </main>
    \\  <footer>
    \\    <p>&copy; {{ year }} {{ companyName }}</p>
    \\  </footer>
    \\</div>
;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("╔══════════════════════════════════════════╗\n", .{});
    std.debug.print("║   Angular Compiler Zig — Benchmark     ║\n", .{});
    std.debug.print("║   Full Pipeline: HTML → R3 → IR → JS   ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════╝\n\n", .{});

    const iterations = 1000;
    var total_ns: i64 = 0;

    // ── Simple templates ──────────────────────────────────────
    std.debug.print("── Simple Templates ({d} iterations each) ──\n\n", .{iterations});

    for (TEMPLATES, 0..) |tpl, i| {
        var compiler = Compiler.init(allocator, .{});
        const start = getNsTimestamp();

        var j: usize = 0;
        while (j < iterations) : (j += 1) {
            var result = try compiler.compileComponent(.{
                .name = "BenchComponent",
                .template = tpl,
            });
            result.deinit(allocator);
        }

        const elapsed = getNsTimestamp() - start;
        total_ns += elapsed;
        compiler.deinit();

        const per_template = @divFloor(elapsed, @as(i64, @intCast(iterations)));
        std.debug.print("  Template {d:2}: {d:6} ns/template ({d:4} chars)\n", .{
            i + 1,
            per_template,
            tpl.len,
        });
    }

    // ── Complex template ─────────────────────────────────────
    std.debug.print("\n── Complex Template ({d} iterations) ──────\n\n", .{iterations});

    var complex_compiler = Compiler.init(allocator, .{});
    const complex_start = getNsTimestamp();

    var k: usize = 0;
    while (k < iterations) : (k += 1) {
        var result = try complex_compiler.compileComponent(.{
            .name = "ComplexComponent",
            .template = COMPLEX_TEMPLATE,
        });
        result.deinit(allocator);
    }

    const complex_elapsed = getNsTimestamp() - complex_start;
    complex_compiler.deinit();

    const complex_per = @divFloor(complex_elapsed, @as(i64, @intCast(iterations)));
    std.debug.print("  Complex:      {d:6} ns/template ({d:4} chars)\n", .{
        complex_per,
        COMPLEX_TEMPLATE.len,
    });

    // ── Summary ──────────────────────────────────────────────
    const total_templates = TEMPLATES.len * iterations + iterations;
    const all_ns: i64 = total_ns + complex_elapsed;
    const avg = @divFloor(all_ns, @as(i64, @intCast(total_templates)));

    std.debug.print("\n── Summary ──────────────────────────────────\n\n", .{});
    std.debug.print("  Total templates:  {d}\n", .{total_templates});
    std.debug.print("  Total time:       {d:.3} ms\n", .{
        @as(f64, @floatFromInt(all_ns)) / 1_000_000.0,
    });
    std.debug.print("  Average:          {d} ns/template\n", .{avg});
    std.debug.print("  Throughput:       {d:.0} templates/second\n", .{
        @as(f64, @floatFromInt(1_000_000_000)) / @as(f64, @floatFromInt(avg)),
    });
    std.debug.print("  Complex avg:      {d} ns/template\n", .{complex_per});

    // ── Phase breakdown (single run) ─────────────────────────
    std.debug.print("\n── Phase Breakdown (single run) ────────────\n\n", .{});

    var detail_compiler = Compiler.init(allocator, .{});
    const detail_result = try detail_compiler.compileComponent(.{
        .name = "DetailComponent",
        .template = COMPLEX_TEMPLATE,
    });

    std.debug.print("  HTML parse:      {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.html_parse_ns)), 1.0)});
    std.debug.print("  R3 transform:   {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.r3_transform_ns)), 1.0)});
    std.debug.print("  IR generation:  {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.ir_gen_ns)), 1.0)});
    std.debug.print("  IR phases:      {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.ir_transform_ns)), 1.0)});
    std.debug.print("  IR emit:        {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.ir_emit_ns)), 1.0)});
    std.debug.print("  JS emit:        {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.js_emit_ns)), 1.0)});
    std.debug.print("  Source map:     {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.sourcemap_ns)), 1.0)});
    std.debug.print("  ─────────────────────────────\n", .{});
    std.debug.print("  Total:          {d:8} ns\n", .{@divFloor(@as(f64, @floatFromInt(detail_result.stats.total_ns)), 1.0)});
    std.debug.print("  HTML nodes:     {d:6}\n", .{detail_result.stats.html_nodes});
    std.debug.print("  R3 nodes:       {d:6}\n", .{detail_result.stats.r3_nodes});
    std.debug.print("  IR create ops:  {d:6}\n", .{detail_result.stats.ir_create_ops});
    std.debug.print("  IR update ops:  {d:6}\n", .{detail_result.stats.ir_update_ops});
    std.debug.print("  Output stmts:   {d:6}\n", .{detail_result.stats.output_stmts});
    std.debug.print("  Constants:      {d:6}\n", .{detail_result.const_count});
    std.debug.print("  Variables:      {d:6}\n", .{detail_result.var_count});
    std.debug.print("  Arena memory:   {d:6} bytes\n", .{detail_result.stats.arena_bytes});

    // Print per-phase timings if available
    if (detail_result.stats.phase_timings.len > 0) {
        std.debug.print("\n  ── 50 IR Phase Details ──\n\n", .{});
        for (detail_result.stats.phase_timings) |pt| {
            std.debug.print("    {s:45} {d:8} ns\n", .{ pt.name, pt.elapsed_ns });
        }
    }

    var dr = detail_result; dr.deinit(allocator);
    detail_compiler.deinit();

    std.debug.print("\n✓ Benchmark complete\n", .{});
}
