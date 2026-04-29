comptime {
    @Struct(.auto, null, &.{"foo"}, &.{u32}, &.{.{ .@"comptime" = true }});
}
comptime {
    @Struct(.@"extern", null, &.{"foo"}, &.{u32}, &.{.{ .@"comptime" = true, .default_value_ptr = &@as(u32, 10) }});
}
comptime {
    @Struct(.@"bitpack", null, &.{"foo"}, &.{u32}, &.{.{ .@"align" = 4 }});
}

// error
//
// :2:46: error: comptime field without default initialization value
// :5:51: error: extern struct fields cannot be marked comptime
// :8:52: error: bitpack struct fields cannot be aligned
