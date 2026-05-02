declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_panic_index_out_of_bounds(i64, i64, i64, i64) noreturn

%String = type { i8*, i64 }
%Array = type { i64, ptr }

define void @matcha_function_0_incrementArray(%Array %arg_0_array) {
entry:
    %.s_0 = alloca %Array
    %.s_1 = alloca i64

    store %Array %arg_0_array, ptr %.s_0
    store i64 0, ptr %.s_1
    br label %label_loop_header_0
label_loop_header_0:
    %.t_0 = load i64, ptr %.s_1
    %.t_1 = load %Array, ptr %.s_0
    %.t_2 = extractvalue %Array %.t_1, 0
    %.t_3 = icmp slt i64 %.t_0, %.t_2
    br i1 %.t_3, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_4 = load %Array, ptr %.s_0
    %.t_5 = load i64, ptr %.s_1
    %.t_6 = extractvalue %Array %.t_4, 0
    %.t_7 = extractvalue %Array %.t_4, 1
    %.t_8 = icmp slt i64 %.t_5, 0
    %.t_9 = icmp sge i64 %.t_5, %.t_6
    %.t_10 = or i1 %.t_8, %.t_9
    br i1 %.t_10, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 4, i64 14, i64 %.t_5, i64 %.t_6)
    unreachable
label_index_ok_5:
    %.t_11 = getelementptr inbounds i64, ptr %.t_7, i64 %.t_5
    %.t_12 = load %Array, ptr %.s_0
    %.t_13 = load i64, ptr %.s_1
    %.t_14 = extractvalue %Array %.t_12, 0
    %.t_15 = extractvalue %Array %.t_12, 1
    %.t_16 = icmp slt i64 %.t_13, 0
    %.t_17 = icmp sge i64 %.t_13, %.t_14
    %.t_18 = or i1 %.t_16, %.t_17
    br i1 %.t_18, label %label_index_panic_6, label %label_index_ok_7
label_index_panic_6:
    call void @matcha_panic_index_out_of_bounds(i64 4, i64 25, i64 %.t_13, i64 %.t_14)
    unreachable
label_index_ok_7:
    %.t_19 = getelementptr inbounds i64, ptr %.t_15, i64 %.t_13
    %.t_20 = load i64, ptr %.t_19
    %.t_21 = add i64 %.t_20, 1
    store i64 %.t_21, ptr %.t_11
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_22 = load i64, ptr %.s_1
    %.t_23 = add i64 %.t_22, 1
    store i64 %.t_23, ptr %.s_1
    br label %label_loop_header_0
label_loop_exit_3:
    ret void

}

define i64 @matcha_function_1_sumArray(%Array %arg_0_array) {
entry:
    %.s_0 = alloca %Array
    %.s_1 = alloca i64
    %.s_2 = alloca i64

    store %Array %arg_0_array, ptr %.s_0
    store i64 0, ptr %.s_1
    store i64 0, ptr %.s_2
    br label %label_loop_header_0
label_loop_header_0:
    %.t_0 = load i64, ptr %.s_2
    %.t_1 = load %Array, ptr %.s_0
    %.t_2 = extractvalue %Array %.t_1, 0
    %.t_3 = icmp slt i64 %.t_0, %.t_2
    br i1 %.t_3, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_4 = load i64, ptr %.s_1
    %.t_5 = load %Array, ptr %.s_0
    %.t_6 = load i64, ptr %.s_2
    %.t_7 = extractvalue %Array %.t_5, 0
    %.t_8 = extractvalue %Array %.t_5, 1
    %.t_9 = icmp slt i64 %.t_6, 0
    %.t_10 = icmp sge i64 %.t_6, %.t_7
    %.t_11 = or i1 %.t_9, %.t_10
    br i1 %.t_11, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 12, i64 26, i64 %.t_6, i64 %.t_7)
    unreachable
label_index_ok_5:
    %.t_12 = getelementptr inbounds i64, ptr %.t_8, i64 %.t_6
    %.t_13 = load i64, ptr %.t_12
    %.t_14 = add i64 %.t_4, %.t_13
    store i64 %.t_14, ptr %.s_1
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_15 = load i64, ptr %.s_2
    %.t_16 = add i64 %.t_15, 1
    store i64 %.t_16, ptr %.s_2
    br label %label_loop_header_0
label_loop_exit_3:
    %.t_17 = load i64, ptr %.s_1
    ret i64 %.t_17

}

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
    %.t_6 = load %Array, ptr %.s_0
    call void @matcha_function_0_incrementArray(%Array %.t_6)
    store i64 0, ptr %.s_1
    br label %label_loop_header_0
label_loop_header_0:
    %.t_7 = load i64, ptr %.s_1
    %.t_8 = load %Array, ptr %.s_0
    %.t_9 = extractvalue %Array %.t_8, 0
    %.t_10 = icmp slt i64 %.t_7, %.t_9
    br i1 %.t_10, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_11 = load %Array, ptr %.s_0
    %.t_12 = load i64, ptr %.s_1
    %.t_13 = extractvalue %Array %.t_11, 0
    %.t_14 = extractvalue %Array %.t_11, 1
    %.t_15 = icmp slt i64 %.t_12, 0
    %.t_16 = icmp sge i64 %.t_12, %.t_13
    %.t_17 = or i1 %.t_15, %.t_16
    br i1 %.t_17, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 24, i64 22, i64 %.t_12, i64 %.t_13)
    unreachable
label_index_ok_5:
    %.t_18 = getelementptr inbounds i64, ptr %.t_14, i64 %.t_12
    %.t_19 = load i64, ptr %.t_18
    call void @matcha_print_int(i64 %.t_19)
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_20 = load i64, ptr %.s_1
    %.t_21 = add i64 %.t_20, 1
    store i64 %.t_21, ptr %.s_1
    br label %label_loop_header_0
label_loop_exit_3:
    %.t_22 = load %Array, ptr %.s_0
    %.t_23 = call i64 @matcha_function_1_sumArray(%Array %.t_22)
    store i64 %.t_23, ptr %.s_2
    %.t_24 = load i64, ptr %.s_2
    call void @matcha_print_int(i64 %.t_24)
    ret i32 0

}
