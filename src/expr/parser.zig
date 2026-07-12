/// Expression Parser — Recursive Descent with Operator Precedence
///
/// Zig advantage:
///   - No closures / heap allocations during parsing
///   - All state on stack → cache-friendly
///   - comptime operator precedence table
///   - Error handling via error union (no exceptions overhead)
///   - AST nodes allocated from Arena — bump pointer, O(1)
///
/// Grammar (simplified):
///   Pipe       ::= Conditional ('|' Identifier CallArgs?)*
///   Conditional ::= LogicalOR ('?' Pipe ':' Pipe)?
///   LogicalOR  ::= LogicalAND ('||' LogicalAND)*
///   LogicalAND ::= BitwiseOR ('&&' BitwiseOR)*
///   Equality   ::= Comparison (('=='|'==='|'!='|'!==') Comparison)*
///   Comparison ::= Shift (('<'|'>'|'<='|'>=') Shift)*
///   Shift      ::= Additive (('<<'|'>>'|'>>>') Additive)*
///   Additive   ::= Multiplicative (('+'|'-') Multiplicative)*
///   Multiplicative ::= Unary (('*'|'/'|'%') Unary)*
///   Unary      ::= ('!'|'-'|'+') Unary | Postfix
///   Postfix    ::= CallMember ('!' | '?.' MemberOrCall)*
///   CallMember ::= Primary (Call | MemberAccess | KeyedAccess)*
///   Primary    ::= Literal | Identifier | '(' Pipe ')' | ...
const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Ast = ast.Ast;
const AstKind = ast.AstKind;
const ParseSpan = ast.ParseSpan;
const BinaryOp = ast.BinaryOp;
const LiteralValue = ast.LiteralValue;
const ArrowParam = ast.ArrowParam;

const lexer = @import("lexer.zig");
const Token = lexer.Token;
const TokenType = lexer.TokenType;

const arena_mod = @import("../arena.zig");
const AstArena = arena_mod.AstArena;

const source_span = @import("../source_span.zig");
const AbsoluteSourceSpan = source_span.AbsoluteSourceSpan;

// ─── Parse Flags ──────────────────────────────────────────────

pub const ParseFlags = packed struct {
    is_action: bool = false, // event handler (allows assignments, semicolons)
    is_binding: bool = false, // property binding (no assignments)
    is_pipe: bool = false, // inside pipe context
};

// ─── Parser ────────────────────────────────────────────────────

pub const Parser = struct {
    allocator: Allocator,
    arena: *AstArena,
    source: []const u8,
    tokens: []const Token,
    pos: u32 = 0,
    offset: u32 = 0, // global offset for absolute spans
    errors: std.array_list.Managed(source_span.ParseError),

    pub fn init(allocator: Allocator, arena: *AstArena, source: []const u8, tokens: []const Token, offset: u32) Parser {
        return .{
            .allocator = allocator,
            .arena = arena,
            .source = source,
            .tokens = tokens,
            .offset = offset,
            .errors = std.array_list.Managed(source_span.ParseError).init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.errors.deinit();
    }

    // ─── Token Helpers ───────────────────────────────────────

    fn current(self: *const Parser) Token {
        if (self.pos < self.tokens.len) return self.tokens[self.pos];
        return .{ .type = .EOF, .index = @intCast(self.source.len), .end = @intCast(self.source.len) };
    }

    fn next(self: *Parser) Token {
        const tok = self.current();
        if (self.pos < self.tokens.len) self.pos += 1;
        return tok;
    }

    fn peekAt(self: *const Parser, ahead: u32) Token {
        const idx = @min(self.pos + ahead, self.tokens.len - 1);
        return self.tokens[idx];
    }

    fn expect(self: *Parser, tok_type: TokenType, value: []const u8) !bool {
        const tok = self.current();
        if (tok.type == tok_type and std.mem.eql(u8, tok.slice(self.source), value)) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn expectIdentifier(self: *Parser, name: []const u8) !bool {
        return self.expect(.Identifier, name) or self.expect(.Keyword, name);
    }

    fn at(self: *const Parser, tok_type: TokenType) bool {
        return self.current().type == tok_type;
    }

    fn atOperator(self: *const Parser, op: []const u8) bool {
        const tok = self.current();
        return tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), op);
    }

    fn atKeyword(self: *const Parser, kw: []const u8) bool {
        const tok = self.current();
        return (tok.type == .Keyword or tok.type == .Identifier) and
            std.mem.eql(u8, tok.slice(self.source), kw);
    }

    // ─── Span Helpers ────────────────────────────────────────

    fn span(self: *const Parser, start: u32, end: u32) ParseSpan {
        return .{ .start = start + self.offset, .end = end + self.offset };
    }

    fn absSpan(self: *const Parser, start: u32, end: u32) AbsoluteSourceSpan {
        return .{ .start = start + self.offset, .end = end + self.offset };
    }

    // ─── Error Reporting ─────────────────────────────────────

    fn errorAt(self: *Parser, index: u32, comptime msg: []const u8) !void {
        // Truncate source span for error
        const end = @min(index + 10, @as(u32, @intCast(self.source.len)));
        try self.errors.append(.{
            .span = source_span.ParseSourceSpan.init(index, end, self.source),
            .msg = msg,
        });
    }

    // ─── Public Entry Points ─────────────────────────────────

    /// Parse an action expression (event handler) — allows assignments, chains
    pub fn parseAction(self: *Parser) !*const Ast {
        const result = try self.parsePipe();
        if (self.atOperator(";")) {
            // Chain expression (semicolon-separated)
            var exprs = std.array_list.Managed(*const Ast).init(self.allocator);
            defer exprs.deinit();
            try exprs.append(result);
            while (self.atOperator(";")) {
                _ = self.next();
                try exprs.append(try self.parsePipe());
            }
            const start = self.tokens[0].index;
            const end_tok = self.current();
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = self.span(start, end_tok.index),
                .abs_span = self.absSpan(start, end_tok.index),
                .data = .{ .Chain = .{ .expressions = try self.arena.alloc(*const Ast, exprs.items.len) } },
            };
            @memcpy(@constCast(node.data.Chain.expressions), exprs.items);
            return node;
        }
        return result;
    }

    /// Parse a binding expression (property binding) — no assignments
    pub fn parseBinding(self: *Parser) !*const Ast {
        return self.parsePipe();
    }

    /// Parse a template binding micro-syntax: `*ngFor="let item of items; trackBy: track"`
    pub fn parseTemplateBindings(self: *Parser) !TemplateBindingResult {
        var bindings = std.array_list.Managed(TemplateBinding).init(self.allocator);
        defer bindings.deinit();

        while (self.pos < self.tokens.len and !self.at(.EOF)) {
            // key: value or key
            const key = try self.parseTemplateBindingKey();
            const value = if (self.atOperator(":") or self.atOperator("=")) blk: {
                _ = self.next();
                break :blk try self.parseTemplateBindingValue();
            } else null;
            try bindings.append(.{ .key = key, .value = value });

            if (!self.expect(.Operator, ";") catch false) break;
        }

        return .{
            .bindings = bindings.items,
            .errors = self.errors.items,
        };
    }

    // ─── Core Parsing (Precedence Climbing) ──────────────────

    /// Top-level: pipe expressions
    fn parsePipe(self: *Parser) error{OutOfMemory}!*const Ast {
        var result = try self.parseConditional();

        while (self.atOperator("|")) {
            // Save the start position of the left expression BEFORE advancing.
            // Bug fix: previously used self.tokens[self.pos - 1].index which
            // pointed at the last token of the left expr (e.g. 'b' in 'a + b | pipe')
            // instead of the beginning of the entire left expression.
            const pipe_start = result.span.start;
            const pipe_abs_start = result.abs_span.start;
            _ = self.next(); // skip |

            // Pipe name
            const name_tok = self.next();
            const name = name_tok.slice(self.source);

            // Optional args
            var args = std.array_list.Managed(*const Ast).init(self.allocator);
            defer args.deinit();

            if (self.atOperator(":")) {
                _ = self.next();
                try args.append(try self.parsePipe());
                while (self.atOperator(":")) {
                    _ = self.next();
                    try args.append(try self.parsePipe());
                }
            }

            const pipe_end = self.current().index;
            const node = try self.arena.create(Ast);
            const args_slice = if (args.items.len > 0)
                try self.arena.alloc(*const Ast, args.items.len)
            else
                &[_]*const Ast{};
            if (args.items.len > 0) @memcpy(@constCast(args_slice), args.items);

            node.* = .{
                .span = .{ .start = pipe_start, .end = pipe_end },
                .abs_span = .{ .start = pipe_abs_start, .end = @intCast(pipe_end) },
                .data = .{ .BindingPipe = .{
                    .exp = result,
                    .name = name,
                    .args = args_slice,
                } },
            };
            result = node;
        }

        return result;
    }

    /// Conditional: expr ? true : false
    fn parseConditional(self: *Parser) error{OutOfMemory}!*const Ast {
        const start_pos = self.pos;
        const result = try self.parseLogicalOr();

        if (self.atOperator("?")) {
            _ = self.next();
            const true_expr = try self.parsePipe();
            if (!(self.expect(.Operator, ":") catch false)) {
                try self.errorAt(self.current().index, "Expected ':' in conditional expression");
                return result;
            }
            const false_expr = try self.parsePipe();
            const end_pos = self.pos;
            const start = self.tokens[start_pos].index;
            const end = self.tokens[end_pos].index;
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = self.span(start, end),
                .abs_span = self.absSpan(start, end),
                .data = .{ .Conditional = .{
                    .condition = result,
                    .true_expr = true_expr,
                    .false_expr = false_expr,
                } },
            };
            return node;
        }

        return result;
    }

    /// Binary operations — precedence climbing via comptime table
    fn parseBinaryOps(self: *Parser, level: u8) error{OutOfMemory}!*const Ast {
        if (level >= 12) return self.parseUnary();

        var left = try self.parseBinaryOps(level + 1);

        while (true) {
            const tok = self.current();
            if (tok.type != .Operator) break;

            const op = self.matchBinaryOp(tok.slice(self.source)) orelse break;
            const prec = op.precedence();
            if (prec != level) break;

            // Save the start position of the left operand BEFORE advancing.
            // Bug fix: previously `start` was read AFTER self.next(), pointing
            // at the right operand instead of the beginning of the binary expr.
            const bin_start = left.span.start;
            const bin_abs_start = left.abs_span.start;

            _ = self.next();
            const right = try self.parseBinaryOps(if (op.isAssociative()) level + 1 else level + 1);

            const end = self.current().index;
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = .{ .start = bin_start, .end = end },
                .abs_span = .{ .start = bin_abs_start, .end = @intCast(end) },
                .data = .{ .Binary = .{ .op = op, .left = left, .right = right } },
            };
            left = node;
        }

        return left;
    }

    // Convenience shorthands
    fn parseLogicalOr(self: *Parser) !*const Ast {
        return self.parseBinaryOps(1); // || has precedence 1
    }

    fn parseUnary(self: *Parser) !*const Ast {
        const tok = self.current();
        const op_str = tok.slice(self.source);

        if (tok.type == .Operator and std.mem.eql(u8, op_str, "!")) {
            _ = self.next();
            const expr = try self.parseUnary();
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = expr.span,
                .abs_span = expr.abs_span,
                .data = .{ .PrefixNot = .{ .expression = expr } },
            };
            return node;
        }

        if (tok.type == .Operator and (std.mem.eql(u8, op_str, "+") or std.mem.eql(u8, op_str, "-"))) {
            // Check if it's unary (not binary) — unary if no left operand
            _ = self.next();
            const expr = try self.parseUnary();
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = expr.span,
                .abs_span = expr.abs_span,
                .data = .{ .Unary = .{ .operator = op_str[0], .expr = expr } },
            };
            return node;
        }

        if (self.atKeyword("typeof")) {
            _ = self.next();
            const expr = try self.parseUnary();
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = expr.span,
                .abs_span = expr.abs_span,
                .data = .{ .TypeofExpr = .{ .expression = expr } },
            };
            return node;
        }

        if (self.atKeyword("void")) {
            _ = self.next();
            const expr = try self.parseUnary();
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = expr.span,
                .abs_span = expr.abs_span,
                .data = .{ .VoidExpr = .{ .expression = expr } },
            };
            return node;
        }

        return self.parsePostfix();
    }

    fn parsePostfix(self: *Parser) !*const Ast {
        var result = try self.parseCallMember();

        while (true) {
            if (self.atOperator("!")) {
                const tok = self.next();
                const node = try self.arena.create(Ast);
                node.* = .{
                    .span = self.span(tok.index, tok.end),
                    .abs_span = self.absSpan(tok.index, tok.end),
                    .data = .{ .NonNullAssert = .{ .expression = result } },
                };
                result = node;
            } else {
                break;
            }
        }

        return result;
    }

    fn parseCallMember(self: *Parser) !*const Ast {
        var result = try self.parsePrimary();

        while (true) {
            const tok = self.current();

            // Member access: .identifier
            if (tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), ".")) {
                _ = self.next();
                if (self.at(.Identifier) or self.at(.Keyword)) {
                    const name_tok = self.next();
                    const name = name_tok.slice(self.source);
                    const start = self.tokens[self.pos].index;
                    const node = try self.arena.create(Ast);
                    node.* = .{
                        .span = self.span(start, name_tok.end),
                        .abs_span = self.absSpan(start, name_tok.end),
                        .data = .{ .PropertyRead = .{ .receiver = result, .name = name } },
                    };
                    result = node;
                } else {
                    // stray dot, put it back
                    self.pos -= 1;
                    break;
                }
            }
            // Safe navigation: ?.identifier or ?.[expr]
            else if (tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), "?.")) {
                _ = self.next();
                const start = self.tokens[self.pos].index;

                if (self.at(.Identifier) or self.at(.Keyword)) {
                    const name_tok = self.next();
                    const name = name_tok.slice(self.source);
                    const node = try self.arena.create(Ast);
                    node.* = .{
                        .span = self.span(start, name_tok.end),
                        .abs_span = self.absSpan(start, name_tok.end),
                        .data = .{ .SafePropertyRead = .{ .receiver = result, .name = name } },
                    };
                    result = node;
                } else if (self.atOperator("[")) {
                    _ = self.next();
                    const key = try self.parsePipe();
                    _ = self.expect(.Operator, "]") catch {};
                    const end_tok = self.current();
                    const node = try self.arena.create(Ast);
                    node.* = .{
                        .span = self.span(start, end_tok.index),
                        .abs_span = self.absSpan(start, end_tok.index),
                        .data = .{ .SafeKeyedRead = .{ .receiver = result, .key = key } },
                    };
                    result = node;
                } else {
                    break;
                }
            }
            // Keyed access: [expr]
            else if (tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), "[")) {
                _ = self.next();
                const key = try self.parsePipe();
                _ = self.expect(.Operator, "]") catch {};
                const end_tok = self.current();
                const start = self.tokens[self.pos].index;
                const node = try self.arena.create(Ast);
                node.* = .{
                    .span = self.span(start, end_tok.index),
                    .abs_span = self.absSpan(start, end_tok.index),
                    .data = .{ .KeyedRead = .{ .receiver = result, .key = key } },
                };
                result = node;
            }
            // Function call: (args)
            else if (tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), "(")) {
                const open_tok = self.next();
                var args = std.array_list.Managed(*const Ast).init(self.allocator);
                defer args.deinit();

                if (!self.atOperator(")")) {
                    try args.append(try self.parsePipe());
                    while (self.atOperator(",")) {
                        _ = self.next();
                        try args.append(try self.parsePipe());
                    }
                }
                const close_tok = self.current();
                _ = self.expect(.Operator, ")") catch {};

                const args_slice = if (args.items.len > 0)
                    try self.arena.alloc(*const Ast, args.items.len)
                else
                    &[_]*const Ast{};
                if (args.items.len > 0) @memcpy(@constCast(args_slice), args.items);

                const node = try self.arena.create(Ast);
                node.* = .{
                    .span = self.span(open_tok.index, close_tok.index),
                    .abs_span = self.absSpan(open_tok.index, close_tok.index),
                    .data = .{ .Call = .{
                        .receiver = result,
                        .args = args_slice,
                        .argument_span = ParseSpan{
                            .start = open_tok.index,
                            .end = close_tok.index,
                        },
                    } },
                };
                result = node;
            } else {
                break;
            }
        }

        return result;
    }

    fn parsePrimary(self: *Parser) !*const Ast {
        const tok = self.current();

        // Parenthesized expression
        if (tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), "(")) {
            return self.parseParenthesized();
        }

        // String literal
        if (tok.type == .String) {
            _ = self.next();
            const raw = tok.slice(self.source);
            // Strip quotes
            const content = raw[1 .. raw.len - 1];
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = self.span(tok.index, tok.end),
                .abs_span = self.absSpan(tok.index, tok.end),
                .data = .{ .LiteralPrimitive = .{ .String = content } },
            };
            return node;
        }

        // Number literal
        if (tok.type == .Number) {
            _ = self.next();
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = self.span(tok.index, tok.end),
                .abs_span = self.absSpan(tok.index, tok.end),
                .data = .{ .LiteralPrimitive = .{ .Number = tok.num_value } },
            };
            return node;
        }

        // Boolean / null / undefined
        if (tok.type == .Keyword) {
            const val = tok.slice(self.source);
            if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "false")) {
                _ = self.next();
                const node = try self.arena.create(Ast);
                node.* = .{
                    .span = self.span(tok.index, tok.end),
                    .abs_span = self.absSpan(tok.index, tok.end),
                    .data = .{ .LiteralPrimitive = .{ .Boolean = std.mem.eql(u8, val, "true") } },
                };
                return node;
            }
            if (std.mem.eql(u8, val, "null")) {
                _ = self.next();
                const node = try self.arena.create(Ast);
                node.* = Ast.literalNull(
                    self.span(tok.index, tok.end),
                    self.absSpan(tok.index, tok.end),
                );
                return node;
            }
            if (std.mem.eql(u8, val, "undefined")) {
                _ = self.next();
                const node = try self.arena.create(Ast);
                node.* = .{
                    .span = self.span(tok.index, tok.end),
                    .abs_span = self.absSpan(tok.index, tok.end),
                    .data = .{ .LiteralPrimitive = .{ .Undefined = {} } },
                };
                return node;
            }
            if (std.mem.eql(u8, val, "this")) {
                _ = self.next();
                const node = try self.arena.create(Ast);
                node.* = .{
                    .span = self.span(tok.index, tok.end),
                    .abs_span = self.absSpan(tok.index, tok.end),
                    .data = .{ .ThisReceiver = {} },
                };
                return node;
            }
        }

        // Array literal
        if (tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), "[")) {
            return self.parseArrayLiteral();
        }

        // Object literal
        if (tok.type == .Operator and std.mem.eql(u8, tok.slice(self.source), "{")) {
            return self.parseObjectLiteral();
        }

        // Identifier → implicit receiver + property read
        if (tok.type == .Identifier) {
            _ = self.next();
            const name = tok.slice(self.source);
            const receiver = try self.arena.create(Ast);
            receiver.* = Ast.implicitReceiver(
                self.span(tok.index, tok.index),
                self.absSpan(tok.index, tok.index),
            );
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = self.span(tok.index, tok.end),
                .abs_span = self.absSpan(tok.index, tok.end),
                .data = .{ .PropertyRead = .{
                    .receiver = receiver,
                    .name = name,
                } },
            };
            return node;
        }

        // Dollar sign (e.g., in template context)
        if (tok.type == .Dollar) {
            _ = self.next();
            const node = try self.arena.create(Ast);
            node.* = Ast.implicitReceiver(
                self.span(tok.index, tok.end),
                self.absSpan(tok.index, tok.end),
            );
            return node;
        }

        try self.errorAt(tok.index, "Unexpected token");
        const node = try self.arena.create(Ast);
        node.* = Ast.empty(
            self.span(tok.index, tok.end),
            self.absSpan(tok.index, tok.end),
        );
        return node;
    }

    fn parseParenthesized(self: *Parser) !*const Ast {
        const open = self.next(); // (
        const expr = try self.parsePipe();

        // Check for arrow function: (a, b) => expr
        if (self.atOperator("=") and self.peekAt(1).type == .Operator and
            std.mem.eql(u8, self.peekAt(1).slice(self.source), ">"))
        {
            // We need to re-parse as arrow function
            // For now, return the expression
            _ = self.next();
            _ = self.next();
            const body = try self.parsePipe();
            const node = try self.arena.create(Ast);
            node.* = .{
                .span = self.span(open.index, self.current().index),
                .abs_span = self.absSpan(open.index, self.current().index),
                .data = .{ .ArrowFunction = .{
                    .params = &[_]ArrowParam{},
                    .body = body,
                } },
            };
            return node;
        }

        _ = self.expect(.Operator, ")") catch {};
        const node = try self.arena.create(Ast);
        node.* = .{
            .span = self.span(open.index, self.current().index),
            .abs_span = self.absSpan(open.index, self.current().index),
            .data = .{ .Parenthesized = .{ .expression = expr } },
        };
        return node;
    }

    fn parseArrayLiteral(self: *Parser) !*const Ast {
        const open = self.next(); // [
        var exprs = std.array_list.Managed(*const Ast).init(self.allocator);
        defer exprs.deinit();

        if (!self.atOperator("]")) {
            if (self.atOperator("...")) {
                _ = self.next();
                const expr = try self.parsePipe();
                const node = try self.arena.create(Ast);
                node.* = .{
                    .span = self.span(open.index, self.current().index),
                    .abs_span = self.absSpan(open.index, self.current().index),
                    .data = .{ .SpreadElement = .{ .expression = expr } },
                };
                try exprs.append(node);
            } else {
                try exprs.append(try self.parsePipe());
            }
            while (self.atOperator(",")) {
                _ = self.next();
                if (self.atOperator("]")) break;
                try exprs.append(try self.parsePipe());
            }
        }
        _ = self.expect(.Operator, "]") catch {};

        const exprs_slice = if (exprs.items.len > 0)
            try self.arena.alloc(*const Ast, exprs.items.len)
        else
            &[_]*const Ast{};
        if (exprs.items.len > 0) @memcpy(@constCast(exprs_slice), exprs.items);

        const node = try self.arena.create(Ast);
        node.* = .{
            .span = self.span(open.index, self.current().index),
            .abs_span = self.absSpan(open.index, self.current().index),
            .data = .{ .LiteralArray = .{ .expressions = exprs_slice } },
        };
        return node;
    }

    fn parseObjectLiteral(self: *Parser) !*const Ast {
        const open = self.next(); // {
        var entries = std.array_list.Managed(ast.MapEntry).init(self.allocator);
        defer entries.deinit();

        if (!self.atOperator("}")) {
            try entries.append(try self.parseMapEntry());
            while (self.atOperator(",")) {
                _ = self.next();
                if (self.atOperator("}")) break;
                try entries.append(try self.parseMapEntry());
            }
        }
        _ = self.expect(.Operator, "}") catch {};

        const entries_slice = if (entries.items.len > 0)
            try self.arena.alloc(ast.MapEntry, entries.items.len)
        else
            &[_]ast.MapEntry{};
        if (entries.items.len > 0) @memcpy(@constCast(entries_slice), entries.items);

        const node = try self.arena.create(Ast);
        node.* = .{
            .span = self.span(open.index, self.current().index),
            .abs_span = self.absSpan(open.index, self.current().index),
            .data = .{ .LiteralMap = .{ .entries = entries_slice } },
        };
        return node;
    }

    fn parseMapEntry(self: *Parser) !ast.MapEntry {
        const tok = self.next();
        const key = tok.slice(self.source);
        _ = self.expect(.Operator, ":") catch {};
        const value = try self.parsePipe();
        return .{ .key = key, .value = value, .quoted = tok.type == .String };
    }

    // ─── Template Binding Helpers ─────────────────────────────

    fn parseTemplateBindingKey(self: *Parser) ![]const u8 {
        const tok = self.next();
        return tok.slice(self.source);
    }

    fn parseTemplateBindingValue(self: *Parser) !*const Ast {
        return self.parsePipe();
    }

    // ─── Operator Matching ────────────────────────────────────

    fn matchBinaryOp(_: *const Parser, op_str: []const u8) ?BinaryOp {
        const map = comptime blk: {
            var m: [@typeInfo(BinaryOp).@"enum".fields.len]struct {
                []const u8,
                BinaryOp,
            } = undefined;
            const fields = @typeInfo(BinaryOp).@"enum".fields;
            for (fields, 0..) |f, i| {
                _ = f.name;
                const op: BinaryOp = @enumFromInt(f.value);
                const str = switch (op) {
                    .Equals => "==",
                    .NotEquals => "!=",
                    .Identical => "===",
                    .NotIdentical => "!==",
                    .Less => "<",
                    .Greater => ">",
                    .LessEquals => "<=",
                    .GreaterEquals => ">=",
                    .Plus => "+",
                    .Minus => "-",
                    .Multiply => "*",
                    .Divide => "/",
                    .Percent => "%",
                    .And => "&&",
                    .Or => "||",
                    .Nullish => "??",
                    .In => "in",
                    .Instanceof => "instanceof",
                    .BitwiseAnd => "&",
                    .BitwiseOr => "|",
                    .BitwiseXor => "^",
                    .LeftShift => "<<",
                    .RightShift => ">>",
                    .UnsignedRightShift => ">>>",
                    .Comma => ",",
                };
                m[i] = .{ str, op };
            }
            break :blk m;
        };

        for (map) |entry| {
            if (std.mem.eql(u8, op_str, entry.@"0")) return entry.@"1";
        }
        return null;
    }
};

// ─── Template Binding Result ───────────────────────────────────

pub const TemplateBindingKey = struct {
    source: []const u8,
    span: ParseSpan,
};

pub const TemplateBinding = struct {
    key: []const u8,
    value: ?*const Ast,
};

pub const TemplateBindingResult = struct {
    bindings: []const TemplateBinding,
    errors: []const source_span.ParseError,
};

// ─── Tests ────────────────────────────────────────────────────

test "parse simple property access" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    const source = "user.name";
    var lxr = @import("lexer.zig").Lexer.init(allocator, source);
    defer lxr.deinit();
    const lex_result = try lxr.tokenize();
    var parser = Parser.init(allocator, &arena, source, lex_result.@"0", 0);
    defer parser.deinit();

    const ast_node = try parser.parseBinding();
    try std.testing.expectEqual(AstKind.PropertyRead, std.meta.activeTag(ast_node.data));
}

test "parse pipe expression" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    const source = "items | slice:1:5";
    var lxr = @import("lexer.zig").Lexer.init(allocator, source);
    defer lxr.deinit();
    const lex_result = try lxr.tokenize();
    var parser = Parser.init(allocator, &arena, source, lex_result.@"0", 0);
    defer parser.deinit();

    const ast_node = try parser.parseBinding();
    try std.testing.expectEqual(AstKind.BindingPipe, std.meta.activeTag(ast_node.data));
}

test "parse conditional" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    const source = "show ? 'yes' : 'no'";
    var lxr = @import("lexer.zig").Lexer.init(allocator, source);
    defer lxr.deinit();
    const lex_result = try lxr.tokenize();
    var parser = Parser.init(allocator, &arena, source, lex_result.@"0", 0);
    defer parser.deinit();

    const ast_node = try parser.parseBinding();
    try std.testing.expectEqual(AstKind.Conditional, std.meta.activeTag(ast_node.data));
}

test "parse binary arithmetic" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    const source = "a + b * 2";
    var lxr = @import("lexer.zig").Lexer.init(allocator, source);
    defer lxr.deinit();
    const lex_result = try lxr.tokenize();
    var parser = Parser.init(allocator, &arena, source, lex_result.@"0", 0);
    defer parser.deinit();

    const ast_node = try parser.parseBinding();
    // Should be: Binary(+, PropertyRead(a), Binary(*, PropertyRead(b), Literal(2)))
    try std.testing.expectEqual(AstKind.Binary, std.meta.activeTag(ast_node.data));
    const binary = ast_node.data.Binary;
    try std.testing.expectEqual(BinaryOp.Plus, binary.op);
    try std.testing.expectEqual(AstKind.Binary, std.meta.activeTag(binary.right.data));
    try std.testing.expectEqual(BinaryOp.Multiply, binary.right.data.Binary.op);
}

test "parse safe navigation" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    const source = "user?.address?.street";
    var lxr = @import("lexer.zig").Lexer.init(allocator, source);
    defer lxr.deinit();
    const lex_result = try lxr.tokenize();
    var parser = Parser.init(allocator, &arena, source, lex_result.@"0", 0);
    defer parser.deinit();

    const ast_node = try parser.parseBinding();
    try std.testing.expectEqual(AstKind.SafePropertyRead, std.meta.activeTag(ast_node.data));
    try std.testing.expectEqual(AstKind.SafePropertyRead, std.meta.activeTag(ast_node.data.SafePropertyRead.receiver.data));
}

test "parse function call" {
    const allocator = std.testing.allocator;
    var arena = AstArena.init(allocator);
    defer arena.deinit();

    const source = "save(user.name, user.email)";
    var lxr = @import("lexer.zig").Lexer.init(allocator, source);
    defer lxr.deinit();
    const lex_result = try lxr.tokenize();
    var parser = Parser.init(allocator, &arena, source, lex_result.@"0", 0);
    defer parser.deinit();

    const ast_node = try parser.parseBinding();
    try std.testing.expectEqual(AstKind.Call, std.meta.activeTag(ast_node.data));
    try std.testing.expectEqual(@as(usize, 2), ast_node.data.Call.args.len);
}
