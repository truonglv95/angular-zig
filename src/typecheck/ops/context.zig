/// TCB Ops Context — Context operations for TCB
///
/// Port of: compiler/src/typecheck/typecheck/ops/context.ts (81 LoC)
const std = @import("std");

/// ContextOp — manage TCB context state.
pub const TcbContext = struct {
    current_view: u32 = 0,
    next_view: u32 = 1,

    pub fn allocateView(self: *TcbContext) u32 {
        const v = self.next_view;
        self.next_view += 1;
        return v;
    }
};
