/// Example: Compile Angular component templates
///
/// Demonstrates the full pipeline with bindings, control flow, pipes, and more.
/// Usage: zig build run-example-compile
const std = @import("std");
const Compiler = @import("angular-compiler").Compiler;
const Config = @import("angular-compiler").Config;
const ComponentMeta = @import("angular-compiler").ComponentMeta;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var compiler = Compiler.init(allocator, .{
        .preserve_whitespaces = true,
        .debug_info = true,
    });
    defer compiler.deinit();

    // ══════════════════════════════════════════════════════════
    // Example 1: Component with bindings, events, interpolation
    // ══════════════════════════════════════════════════════════
    const template1 =
        \\<div class="container" [title]="heading" #heroRef>
        \\<h1>{{ title }}</h1>
        \\<p class="intro" [class.active]="isActive">{{ description }}</p>
        \\<button (click)="save($event)">Save</button>
        \\<input [value]="query" (input)="query = $event.target.value" />
        \\<span [style.color]="accentColor">{{ count | number }}</span>
        \\</div>
    ;

    std.debug.print("=== Example 1: Bindings & Events ===\n", .{});
    const result1 = try compiler.compileComponent(.{
        .name = "HeroComponent",
        .template = template1,
        .selectors = &[_][]const u8{"app-hero"},
        .inputs = &[_]ComponentMeta.InputMeta{
            .property_name = "title",
            .binding_name = "title",
        },
        .outputs = &[_]ComponentMeta.OutputMeta{
            .property_name = "onSave",
            .binding_name = "save",
        },
    });
    std.debug.print("{s}\n", .{result1.js_source});
    printStats(&result1.stats);

    // ══════════════════════════════════════════════════════════
    // Example 2: Control flow with @if, @for, @switch
    // ════════════════════════════════════════════════════════
    const template2 =
        \\<div>
        \\@if (showHeader) {
        \\<header>
        \\<h1>{{ title }}</h1>
        \\</header>
        \\}
        \\@for (item of items; track item.id) {
        \\<div class="item" [class.selected]="item.selected">
        \\<span>{{ item.name }}</span>
        \\<span>{{ item.price | currency:'USD' }}</span>
        \\</div>
        \\}
        \\@switch (status) {
        \\@case ("loading") { <mat-spinner /> }
        \\@case ("loaded") { <div>{{ data }}</div> }
        \\@default { <p>Unknown state</p> }
        \\}
        \\@defer (on viewport) {
        \\<heavy-content />
        \\}
        \\</div>
    ;

    std.debug.print("\n=== Example 2: Control Flow ===\n", .{});
    const result2 = try compiler.compileComponent(.{
        .name = "DataListComponent",
        .template = template2,
        .selectors = &[_][]const u8{"data-list"},
        .inputs = &[_]ComponentMeta.InputMeta{
            .property_name = "items",
        },
    });
    std.debug.print("{s}\n", .{result2.js_source});
    printStats(&result2.stats);

    // ══════════════════════════════════════════════════════════
    // Example 3: ng-template with context variables
    // ════════════════════════════════════════════════════════
    const template3 =
        \\<ng-template #cardTpl let-item let-index let-first let-last>
        \\<div class="card">
        \\<h3>{{ item.name }}</h3>
        \\<p>{{ item.desc }}</p>
        \\</div>
        \\</ng-template>
        \\<ng-container [ngTemplateOutlet]="cardTpl" [ngTemplateOutletContext]="item">
        \\</ng-container>
    ;

    std.debug.print("\n=== Example 3: ng-template ===\n", .{});
    const result3 = try compiler.compileComponent(.{
        .name = "CardContainerComponent",
        .template = template3,
    });
    std.debug.print("{s}\n", .{result3.js_source});
    printStats(&result3.stats);

    // ════════════════════════════════════════════════════════
    // Example 4: ng-content with projection
    // ════════════════════════════════════════════════════════
    const template4 =
        \\<div class="card">
        \\<ng-content select="[card-header]">
        \\<h2>Default Header</h2>
        \\</ng-content>
        \\<ng-content select="[card-body]">
        \\<p>Default Body</p>
        \\</ng-content>
        \\<ng-content>
        \\<p>Default Fallback</p>
        \\</ng-content>
        \\</div>
    ;

    std.debug.print("\n=== Example 4: ng-content ===\n", .{});
    const result4 = try compiler.compileComponent(.{
        .name = "CardShellComponent",
        .template = template4,
    });
    std.debug.print("{s}\n", .{result4.js_source});
    printStats(&result4.stats);

    // ══════════════════════════════════════════════════════════
    // Example 5: Two-way binding + style/class maps
    // ════════════════════════════════════════════════════════
    const template5 =
        \\<div>
        \\<input [(ngModel)]="searchText" placeholder="Search..." />
        \\<div [ngClass]="{'highlight': isMatch, 'dimmed': !hasResults}"
        \\[style.--speed]="transitionDuration + 'ms'"
        \\>
        \\<p>Results: {{ count }}</p>
        \\</div>
        \\<ul>
        \\@for (result of results; track result.id) {
        \\<li [class.active]="isActive(result)" [style.cursor]="'pointer'">
        \\{{ result.text }}
        \\</li>
        \\}
        \\</ul>
        \\</div>
    ;

    std.debug.print("\n=== Example 5: Two-way + Maps ===\n", .{});
    const result5 = try compiler.compileComponent(.{
        .name = "SearchComponent",
        .template = template5,
        .selectors = &[_][]const u8{"app-search"},
    });
    std.debug.print("{s}\n", .{result5.js_source});
    printStats(&result5.stats);
}

fn printStats(stats: *const Compiler.CompilationStats) void {
    std.debug.print("--- Stats ---\n", .{});
    std.debug.print("  HTML nodes:      {d}\n", .{stats.html_nodes});
    std.debug.print("  R3 nodes:       {d}\n", .{stats.r3_nodes});
    std.debug.print("  IR create ops:  {d}\n", .{stats.ir_create_ops});
    std.debug.print("  IR update ops:  {d}\n", .{stats.ir_update_ops});
    std.debug.print("  Constants:      {d}\n", .{stats.const_count});
    std.debug.print("  Declarations:   {d}\n", .{stats.decl_count});
    std.debug.print("  Variables:     {d}\n", .{stats.var_count});
    std.debug.print("  Arena memory:   {d} bytes\n", .{stats.arena_bytes});
    std.debug.print("  Total time:     {d} µs\n", .{@divFloor(@as(f64, @floatFromInt(stats.total_ns)) / 1000.0)});
    std.debug.print("    HTML parse:    {d} µs\n", .{@divFloor(@as(f64, @floatFromInt(stats.html_parse_ns)) / 1000.0)});
    std.debug.print("    R3 transform: {d} µs\n", .{@divFloor(@as(f64, @floatFromInt(stats.r3_transform_ns)) / 1000.0)});
    std.debug.print("    IR gen:       {d} µs\n", .{@divFloor(@as(f64, @floatFromInt(stats.ir_gen_ns)) / 1000.0)});
    std.debug.print("    IR phases:    {d} µs\n", .{@divFloor(@as(f64, @floatFromInt(stats.ir_transform_ns)) / 1000.0)});
    std.debug.print("    IR emit:      {d} µs\n", .{@divFloor(@as(f64, @floatFromInt(stats.ir_emit_ns)) / 1000.0)});
    std.debug.print("    JS emit:      {d} µs\n", .{@divFloor(@as(f64, @floatFromInt(stats.js_emit_ns)) / 1000.0)});
}
