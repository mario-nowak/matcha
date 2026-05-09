declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_panic_index_out_of_bounds(i64, i64, i64, i64) noreturn

%String = type { i8*, i64 }
%Array = type { i64, i64, ptr }

define void @matcha_function_0_incrementArray(ptr %arg_0_array) {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca i64

    store ptr %arg_0_array, ptr %.s_0
    store i64 0, ptr %.s_1
    br label %label_loop_header_0
label_loop_header_0:
    %.t_0 = load i64, ptr %.s_1
    %.t_1 = load ptr, ptr %.s_0
    %.t_2 = getelementptr inbounds %Array, ptr %.t_1, i32 0, i32 0
    %.t_3 = load i64, ptr %.t_2
    %.t_4 = icmp slt i64 %.t_0, %.t_3
    br i1 %.t_4, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_5 = load ptr, ptr %.s_0
    %.t_6 = load i64, ptr %.s_1
    %.t_7 = getelementptr inbounds %Array, ptr %.t_5, i32 0, i32 0
    %.t_8 = load i64, ptr %.t_7
    %.t_9 = getelementptr inbounds %Array, ptr %.t_5, i32 0, i32 2
    %.t_10 = load ptr, ptr %.t_9
    %.t_11 = icmp slt i64 %.t_6, 0
    %.t_12 = icmp sge i64 %.t_6, %.t_8
    %.t_13 = or i1 %.t_11, %.t_12
    br i1 %.t_13, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 4, i64 14, i64 %.t_6, i64 %.t_8)
    unreachable
label_index_ok_5:
    %.t_14 = getelementptr inbounds i64, ptr %.t_10, i64 %.t_6
    %.t_15 = load ptr, ptr %.s_0
    %.t_16 = load i64, ptr %.s_1
    %.t_17 = getelementptr inbounds %Array, ptr %.t_15, i32 0, i32 0
    %.t_18 = load i64, ptr %.t_17
    %.t_19 = getelementptr inbounds %Array, ptr %.t_15, i32 0, i32 2
    %.t_20 = load ptr, ptr %.t_19
    %.t_21 = icmp slt i64 %.t_16, 0
    %.t_22 = icmp sge i64 %.t_16, %.t_18
    %.t_23 = or i1 %.t_21, %.t_22
    br i1 %.t_23, label %label_index_panic_6, label %label_index_ok_7
label_index_panic_6:
    call void @matcha_panic_index_out_of_bounds(i64 4, i64 25, i64 %.t_16, i64 %.t_18)
    unreachable
label_index_ok_7:
    %.t_24 = getelementptr inbounds i64, ptr %.t_20, i64 %.t_16
    %.t_25 = load i64, ptr %.t_24
    %.t_26 = add i64 %.t_25, 1
    store i64 %.t_26, ptr %.t_14
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_27 = load i64, ptr %.s_1
    %.t_28 = add i64 %.t_27, 1
    store i64 %.t_28, ptr %.s_1
    br label %label_loop_header_0
label_loop_exit_3:
    ret void

}

define i64 @matcha_function_1_sumArray(ptr %arg_0_array) {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca i64
    %.s_2 = alloca i64

    store ptr %arg_0_array, ptr %.s_0
    store i64 0, ptr %.s_1
    store i64 0, ptr %.s_2
    br label %label_loop_header_0
label_loop_header_0:
    %.t_0 = load i64, ptr %.s_2
    %.t_1 = load ptr, ptr %.s_0
    %.t_2 = getelementptr inbounds %Array, ptr %.t_1, i32 0, i32 0
    %.t_3 = load i64, ptr %.t_2
    %.t_4 = icmp slt i64 %.t_0, %.t_3
    br i1 %.t_4, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_5 = load i64, ptr %.s_1
    %.t_6 = load ptr, ptr %.s_0
    %.t_7 = load i64, ptr %.s_2
    %.t_8 = getelementptr inbounds %Array, ptr %.t_6, i32 0, i32 0
    %.t_9 = load i64, ptr %.t_8
    %.t_10 = getelementptr inbounds %Array, ptr %.t_6, i32 0, i32 2
    %.t_11 = load ptr, ptr %.t_10
    %.t_12 = icmp slt i64 %.t_7, 0
    %.t_13 = icmp sge i64 %.t_7, %.t_9
    %.t_14 = or i1 %.t_12, %.t_13
    br i1 %.t_14, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 12, i64 26, i64 %.t_7, i64 %.t_9)
    unreachable
label_index_ok_5:
    %.t_15 = getelementptr inbounds i64, ptr %.t_11, i64 %.t_7
    %.t_16 = load i64, ptr %.t_15
    %.t_17 = add i64 %.t_5, %.t_16
    store i64 %.t_17, ptr %.s_1
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_18 = load i64, ptr %.s_2
    %.t_19 = add i64 %.t_18, 1
    store i64 %.t_19, ptr %.s_2
    br label %label_loop_header_0
label_loop_exit_3:
    %.t_20 = load i64, ptr %.s_1
    ret i64 %.t_20

}

define i32 @main() {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca i64
    %.s_2 = alloca i64

    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
    %.t_1 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 3) to i64))
    %.t_2 = getelementptr inbounds i64, ptr %.t_1, i64 0
    store i64 1, ptr %.t_2
    %.t_3 = getelementptr inbounds i64, ptr %.t_1, i64 1
    store i64 2, ptr %.t_3
    %.t_4 = getelementptr inbounds i64, ptr %.t_1, i64 2
    store i64 3, ptr %.t_4
    %.t_5 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 0
    store i64 3, ptr %.t_5
    %.t_6 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 1
    store i64 3, ptr %.t_6
    %.t_7 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 2
    store ptr %.t_1, ptr %.t_7
    store ptr %.t_0, ptr %.s_0
    %.t_8 = load ptr, ptr %.s_0
    call void @matcha_function_0_incrementArray(ptr %.t_8)
    store i64 0, ptr %.s_1
    br label %label_loop_header_0
label_loop_header_0:
    %.t_9 = load i64, ptr %.s_1
    %.t_10 = load ptr, ptr %.s_0
    %.t_11 = getelementptr inbounds %Array, ptr %.t_10, i32 0, i32 0
    %.t_12 = load i64, ptr %.t_11
    %.t_13 = icmp slt i64 %.t_9, %.t_12
    br i1 %.t_13, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_14 = load ptr, ptr %.s_0
    %.t_15 = load i64, ptr %.s_1
    %.t_16 = getelementptr inbounds %Array, ptr %.t_14, i32 0, i32 0
    %.t_17 = load i64, ptr %.t_16
    %.t_18 = getelementptr inbounds %Array, ptr %.t_14, i32 0, i32 2
    %.t_19 = load ptr, ptr %.t_18
    %.t_20 = icmp slt i64 %.t_15, 0
    %.t_21 = icmp sge i64 %.t_15, %.t_17
    %.t_22 = or i1 %.t_20, %.t_21
    br i1 %.t_22, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 24, i64 22, i64 %.t_15, i64 %.t_17)
    unreachable
label_index_ok_5:
    %.t_23 = getelementptr inbounds i64, ptr %.t_19, i64 %.t_15
    %.t_24 = load i64, ptr %.t_23
    call void @matcha_print_int(i64 %.t_24)
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_25 = load i64, ptr %.s_1
    %.t_26 = add i64 %.t_25, 1
    store i64 %.t_26, ptr %.s_1
    br label %label_loop_header_0
label_loop_exit_3:
    %.t_27 = load ptr, ptr %.s_0
    %.t_28 = call i64 @matcha_function_1_sumArray(ptr %.t_27)
    store i64 %.t_28, ptr %.s_2
    %.t_29 = load i64, ptr %.s_2
    call void @matcha_print_int(i64 %.t_29)
    ret i32 0

}
