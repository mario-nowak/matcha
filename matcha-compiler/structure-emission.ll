declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_panic_index_out_of_bounds(i64, i64, i64, i64) noreturn
declare ptr @matcha_array_append_slot(ptr, i64)

%String = type { i8*, i64 }
%Array = type { i64, i64, ptr }

%matcha_structure_0_Point = type { i64, i64 }
define ptr @matcha_structure_0_Point__function_8_movedBy(ptr %arg_0_self, ptr %arg_1_other) {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca ptr

    store ptr %arg_0_self, ptr %.s_0
    store ptr %arg_1_other, ptr %.s_1
    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_1 = load ptr, ptr %.s_0
    %.t_2 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_1, i32 0, i32 0
    %.t_3 = load i64, ptr %.t_2
    %.t_4 = load ptr, ptr %.s_1
    %.t_5 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_4, i32 0, i32 0
    %.t_6 = load i64, ptr %.t_5
    %.t_7 = add i64 %.t_3, %.t_6
    %.t_8 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
    store i64 %.t_7, ptr %.t_8
    %.t_9 = load ptr, ptr %.s_0
    %.t_10 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_9, i32 0, i32 1
    %.t_11 = load i64, ptr %.t_10
    %.t_12 = load ptr, ptr %.s_1
    %.t_13 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_12, i32 0, i32 1
    %.t_14 = load i64, ptr %.t_13
    %.t_15 = add i64 %.t_11, %.t_14
    %.t_16 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 1
    store i64 %.t_15, ptr %.t_16
    ret ptr %.t_0

}
define void @matcha_structure_0_Point__function_11_invert(ptr %arg_0_self) {
entry:
    %.s_0 = alloca ptr

    store ptr %arg_0_self, ptr %.s_0
    %.t_0 = load ptr, ptr %.s_0
    %.t_1 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
    %.t_2 = load ptr, ptr %.s_0
    %.t_3 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_2, i32 0, i32 0
    %.t_4 = load i64, ptr %.t_3
    %.t_5 = sub i64 0, %.t_4
    store i64 %.t_5, ptr %.t_1
    %.t_6 = load ptr, ptr %.s_0
    %.t_7 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_6, i32 0, i32 1
    %.t_8 = load ptr, ptr %.s_0
    %.t_9 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_8, i32 0, i32 1
    %.t_10 = load i64, ptr %.t_9
    %.t_11 = sub i64 0, %.t_10
    store i64 %.t_11, ptr %.t_7
    ret void

}
define ptr @matcha_structure_0_Point__function_13_origin() {
entry:

    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_1 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
    store i64 0, ptr %.t_1
    %.t_2 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 1
    store i64 0, ptr %.t_2
    ret ptr %.t_0

}
define void @matcha_structure_0_Point__function_14_print(ptr %arg_0_self) {
entry:
    %.s_0 = alloca ptr

    store ptr %arg_0_self, ptr %.s_0
    %.t_0 = load ptr, ptr %.s_0
    %.t_1 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
    %.t_2 = load i64, ptr %.t_1
    call void @matcha_print_int(i64 %.t_2)
    %.t_3 = load ptr, ptr %.s_0
    %.t_4 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_3, i32 0, i32 1
    %.t_5 = load i64, ptr %.t_4
    call void @matcha_print_int(i64 %.t_5)
    ret void

}
%matcha_structure_1_PointCluster = type { ptr }
define ptr @matcha_structure_1_PointCluster__function_16_sum(ptr %arg_0_self) {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca ptr
    %.s_2 = alloca i64

    store ptr %arg_0_self, ptr %.s_0
    %.t_0 = call ptr @matcha_structure_0_Point__function_13_origin()
    store ptr %.t_0, ptr %.s_1
    store i64 0, ptr %.s_2
    br label %label_loop_header_0
label_loop_header_0:
    %.t_1 = load i64, ptr %.s_2
    %.t_2 = load ptr, ptr %.s_0
    %.t_3 = getelementptr inbounds %matcha_structure_1_PointCluster, ptr %.t_2, i32 0, i32 0
    %.t_4 = load ptr, ptr %.t_3
    %.t_5 = getelementptr inbounds %Array, ptr %.t_4, i32 0, i32 0
    %.t_6 = load i64, ptr %.t_5
    %.t_7 = icmp slt i64 %.t_1, %.t_6
    br i1 %.t_7, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_8 = load ptr, ptr %.s_1
    %.t_9 = load ptr, ptr %.s_0
    %.t_10 = getelementptr inbounds %matcha_structure_1_PointCluster, ptr %.t_9, i32 0, i32 0
    %.t_11 = load ptr, ptr %.t_10
    %.t_12 = load i64, ptr %.s_2
    %.t_13 = getelementptr inbounds %Array, ptr %.t_11, i32 0, i32 0
    %.t_14 = load i64, ptr %.t_13
    %.t_15 = getelementptr inbounds %Array, ptr %.t_11, i32 0, i32 2
    %.t_16 = load ptr, ptr %.t_15
    %.t_17 = icmp slt i64 %.t_12, 0
    %.t_18 = icmp sge i64 %.t_12, %.t_14
    %.t_19 = or i1 %.t_17, %.t_18
    br i1 %.t_19, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 33, i64 42, i64 %.t_12, i64 %.t_14)
    unreachable
label_index_ok_5:
    %.t_20 = getelementptr inbounds ptr, ptr %.t_16, i64 %.t_12
    %.t_21 = load ptr, ptr %.t_20
    %.t_22 = call ptr @matcha_structure_0_Point__function_8_movedBy(ptr %.t_8, ptr %.t_21)
    store ptr %.t_22, ptr %.s_1
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_23 = load i64, ptr %.s_2
    %.t_24 = add i64 %.t_23, 1
    store i64 %.t_24, ptr %.s_2
    br label %label_loop_header_0
label_loop_exit_3:
    %.t_25 = load ptr, ptr %.s_1
    ret ptr %.t_25

}

define i32 @main() {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca ptr

    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_1_PointCluster, ptr null, i32 1) to i64))
    %.t_1 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
    %.t_2 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (ptr, ptr null, i64 4) to i64))
    %.t_3 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_4 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_3, i32 0, i32 0
    store i64 3, ptr %.t_4
    %.t_5 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_3, i32 0, i32 1
    store i64 1, ptr %.t_5
    %.t_6 = getelementptr inbounds ptr, ptr %.t_2, i64 0
    store ptr %.t_3, ptr %.t_6
    %.t_7 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_8 = sub i64 0, 3
    %.t_9 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_7, i32 0, i32 0
    store i64 %.t_8, ptr %.t_9
    %.t_10 = sub i64 0, 4
    %.t_11 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_7, i32 0, i32 1
    store i64 %.t_10, ptr %.t_11
    %.t_12 = getelementptr inbounds ptr, ptr %.t_2, i64 1
    store ptr %.t_7, ptr %.t_12
    %.t_13 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_14 = sub i64 0, 8
    %.t_15 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_13, i32 0, i32 0
    store i64 %.t_14, ptr %.t_15
    %.t_16 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_13, i32 0, i32 1
    store i64 5, ptr %.t_16
    %.t_17 = getelementptr inbounds ptr, ptr %.t_2, i64 2
    store ptr %.t_13, ptr %.t_17
    %.t_18 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_19 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_18, i32 0, i32 0
    store i64 9, ptr %.t_19
    %.t_20 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_18, i32 0, i32 1
    store i64 2, ptr %.t_20
    %.t_21 = getelementptr inbounds ptr, ptr %.t_2, i64 3
    store ptr %.t_18, ptr %.t_21
    %.t_22 = getelementptr inbounds %Array, ptr %.t_1, i32 0, i32 0
    store i64 4, ptr %.t_22
    %.t_23 = getelementptr inbounds %Array, ptr %.t_1, i32 0, i32 1
    store i64 4, ptr %.t_23
    %.t_24 = getelementptr inbounds %Array, ptr %.t_1, i32 0, i32 2
    store ptr %.t_2, ptr %.t_24
    %.t_25 = getelementptr inbounds %matcha_structure_1_PointCluster, ptr %.t_0, i32 0, i32 0
    store ptr %.t_1, ptr %.t_25
    store ptr %.t_0, ptr %.s_0
    %.t_26 = load ptr, ptr %.s_0
    %.t_27 = getelementptr inbounds %matcha_structure_1_PointCluster, ptr %.t_26, i32 0, i32 0
    %.t_28 = load ptr, ptr %.t_27
    %.t_29 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_30 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_29, i32 0, i32 0
    store i64 6, ptr %.t_30
    %.t_31 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_29, i32 0, i32 1
    store i64 7, ptr %.t_31
    %.t_32 = call ptr @matcha_array_append_slot(ptr %.t_28, i64 ptrtoint (ptr getelementptr (ptr, ptr null, i64 1) to i64))
    store ptr %.t_29, ptr %.t_32
    %.t_33 = load ptr, ptr %.s_0
    %.t_34 = call ptr @matcha_structure_1_PointCluster__function_16_sum(ptr %.t_33)
    store ptr %.t_34, ptr %.s_1
    %.t_35 = load ptr, ptr %.s_1
    call void @matcha_structure_0_Point__function_11_invert(ptr %.t_35)
    %.t_36 = load ptr, ptr %.s_1
    call void @matcha_structure_0_Point__function_14_print(ptr %.t_36)
    ret i32 0

}
