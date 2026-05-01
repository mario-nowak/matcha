declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_panic_index_out_of_bounds(i64, i64, i64, i64) noreturn

%String = type { i8*, i64 }
%Array = type { i64, ptr }

define i32 @main() {
entry:
    %.s_0 = alloca %Array
    %.s_1 = alloca i64
    %.s_2 = alloca i64

    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 3) to i64))
    %.t_1 = getelementptr inbounds i64, ptr %.t_0, i64 0
    store i64 1, ptr %.t_1
    %.t_2 = getelementptr inbounds i64, ptr %.t_0, i64 1
    store i64 2, ptr %.t_2
    %.t_3 = getelementptr inbounds i64, ptr %.t_0, i64 2
    store i64 3, ptr %.t_3
    %.t_4 = insertvalue %Array undef, i64 3, 0
    %.t_5 = insertvalue %Array %.t_4, ptr %.t_0, 1
    store %Array %.t_5, ptr %.s_0
    store i64 4, ptr %.s_1
    store i64 0, ptr %.s_2
    br label %label_loop_header_0
label_loop_header_0:
    %.t_6 = load i64, ptr %.s_2
    %.t_7 = load i64, ptr %.s_1
    %.t_8 = icmp slt i64 %.t_6, %.t_7
    br i1 %.t_8, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_9 = load %Array, ptr %.s_0
    %.t_10 = load i64, ptr %.s_2
    %.t_11 = extractvalue %Array %.t_9, 0
    %.t_12 = extractvalue %Array %.t_9, 1
    %.t_13 = icmp slt i64 %.t_10, 0
    %.t_14 = icmp sge i64 %.t_10, %.t_11
    %.t_15 = or i1 %.t_13, %.t_14
    br i1 %.t_15, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 9, i64 22, i64 %.t_10, i64 %.t_11)
    unreachable
label_index_ok_5:
    %.t_16 = getelementptr inbounds i64, ptr %.t_12, i64 %.t_10
    %.t_17 = load i64, ptr %.t_16
    call void @matcha_print_int(i64 %.t_17)
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_18 = load i64, ptr %.s_2
    %.t_19 = add i64 %.t_18, 1
    store i64 %.t_19, ptr %.s_2
    br label %label_loop_header_0
label_loop_exit_3:
    ret i32 0

}
