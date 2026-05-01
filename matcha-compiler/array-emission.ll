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
    store i64 0, ptr %.s_1
    br label %label_loop_header_0
label_loop_header_0:
    %.t_6 = load i64, ptr %.s_1
    %.t_7 = load %Array, ptr %.s_0
    %.t_8 = extractvalue %Array %.t_7, 0
    %.t_9 = icmp slt i64 %.t_6, %.t_8
    br i1 %.t_9, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_10 = load %Array, ptr %.s_0
    %.t_11 = load i64, ptr %.s_1
    %.t_12 = extractvalue %Array %.t_10, 0
    %.t_13 = extractvalue %Array %.t_10, 1
    %.t_14 = icmp slt i64 %.t_11, 0
    %.t_15 = icmp sge i64 %.t_11, %.t_12
    %.t_16 = or i1 %.t_14, %.t_15
    br i1 %.t_16, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 8, i64 22, i64 %.t_11, i64 %.t_12)
    unreachable
label_index_ok_5:
    %.t_17 = getelementptr inbounds i64, ptr %.t_13, i64 %.t_11
    %.t_18 = load i64, ptr %.t_17
    call void @matcha_print_int(i64 %.t_18)
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_19 = load i64, ptr %.s_1
    %.t_20 = add i64 %.t_19, 1
    store i64 %.t_20, ptr %.s_1
    br label %label_loop_header_0
label_loop_exit_3:
    ret i32 0

}
