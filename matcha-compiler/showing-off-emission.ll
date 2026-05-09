declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_print_string(ptr, i64)

%String = type { i8*, i64 }
%Array = type { i64, i64, ptr }

@.string_literal_0 = private unnamed_addr constant [7 x i8] c"Is zero"
@.string_literal_1 = private unnamed_addr constant [11 x i8] c"Hello world"
@.string_literal_2 = private unnamed_addr constant [15 x i8] c"Printing points"
@.string_literal_3 = private unnamed_addr constant [27 x i8] c"Printing the while loop now"

%matcha_structure_2_Point = type { i64, i64 }
%matcha_structure_3_NestedPoint = type { ptr, ptr }

define i64 @matcha_function_0_addOne(i64 %arg_0_x) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_x, ptr %.s_0
    %.t_0 = load i64, ptr %.s_0
    %.t_1 = add i64 %.t_0, 1
    ret i64 %.t_1

}

define i64 @matcha_function_1_complexFunction(i64 %arg_0_x) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_x, ptr %.s_0
    %.t_0 = load i64, ptr %.s_0
    %.t_1 = icmp eq i64 %.t_0, 0
    br i1 %.t_1, label %label_then_1, label %label_continue_0
label_then_1:
    %.t_2 = getelementptr inbounds [7 x i8], [7 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_3 = insertvalue %String undef, i8* %.t_2, 0
    %.t_4 = insertvalue %String %.t_3, i64 7, 1
    %.t_5 = extractvalue %String %.t_4, 0
    %.t_6 = extractvalue %String %.t_4, 1
    call void @matcha_print_string(ptr %.t_5, i64 %.t_6)
    %.t_7 = load i64, ptr %.s_0
    ret i64 %.t_7
label_continue_0:
    %.t_8 = load i64, ptr %.s_0
    %.t_9 = add i64 %.t_8, 1
    ret i64 %.t_9

}

define i32 @main() {
entry:
    %.s_0 = alloca i64
    %.s_1 = alloca i64
    %.s_2 = alloca i64
    %.s_3 = alloca i64
    %.s_4 = alloca i64
    %.s_5 = alloca i1
    %.s_6 = alloca ptr
    %.s_7 = alloca ptr

    store i64 3, ptr %.s_0
    store i64 3, ptr %.s_1
    %.t_0 = load i64, ptr %.s_1
    %.t_1 = add i64 %.t_0, 1
    store i64 %.t_1, ptr %.s_1
    %.t_2 = load i64, ptr %.s_1
    call void @matcha_print_int(i64 %.t_2)
    %.t_3 = getelementptr inbounds [11 x i8], [11 x i8]* @.string_literal_1, i64 0, i64 0
    %.t_4 = insertvalue %String undef, i8* %.t_3, 0
    %.t_5 = insertvalue %String %.t_4, i64 11, 1
    %.t_6 = extractvalue %String %.t_5, 0
    %.t_7 = extractvalue %String %.t_5, 1
    call void @matcha_print_string(ptr %.t_6, i64 %.t_7)
    %.t_8 = load i64, ptr %.s_1
    %.t_9 = call i64 @matcha_function_0_addOne(i64 %.t_8)
    call void @matcha_print_int(i64 %.t_9)
    store i64 4, ptr %.s_2
    %.t_10 = load i64, ptr %.s_2
    store i64 %.t_10, ptr %.s_3
    %.t_11 = load i64, ptr %.s_3
    call void @matcha_print_int(i64 %.t_11)
    %.t_12 = call i64 @matcha_function_1_complexFunction(i64 1)
    store i64 %.t_12, ptr %.s_4
    %.t_13 = load i64, ptr %.s_4
    call void @matcha_print_int(i64 %.t_13)
    store i1 1, ptr %.s_5
    %.t_14 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_2_Point, ptr null, i32 1) to i64))
    %.t_15 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_14, i32 0, i32 0
    store i64 4, ptr %.t_15
    %.t_16 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_14, i32 0, i32 1
    store i64 5, ptr %.t_16
    store ptr %.t_14, ptr %.s_6
    %.t_17 = load ptr, ptr %.s_6
    %.t_18 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_17, i32 0, i32 1
    store i64 2, ptr %.t_18
    %.t_19 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_3_NestedPoint, ptr null, i32 1) to i64))
    %.t_20 = load ptr, ptr %.s_6
    %.t_21 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_19, i32 0, i32 0
    store ptr %.t_20, ptr %.t_21
    %.t_22 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_2_Point, ptr null, i32 1) to i64))
    %.t_23 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_22, i32 0, i32 0
    store i64 3, ptr %.t_23
    %.t_24 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_22, i32 0, i32 1
    store i64 6, ptr %.t_24
    %.t_25 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_19, i32 0, i32 1
    store ptr %.t_22, ptr %.t_25
    store ptr %.t_19, ptr %.s_7
    %.t_26 = getelementptr inbounds [15 x i8], [15 x i8]* @.string_literal_2, i64 0, i64 0
    %.t_27 = insertvalue %String undef, i8* %.t_26, 0
    %.t_28 = insertvalue %String %.t_27, i64 15, 1
    %.t_29 = extractvalue %String %.t_28, 0
    %.t_30 = extractvalue %String %.t_28, 1
    call void @matcha_print_string(ptr %.t_29, i64 %.t_30)
    %.t_31 = load ptr, ptr %.s_6
    %.t_32 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_31, i32 0, i32 0
    store i64 110, ptr %.t_32
    %.t_33 = load ptr, ptr %.s_7
    %.t_34 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_33, i32 0, i32 0
    %.t_35 = load ptr, ptr %.t_34
    %.t_36 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_35, i32 0, i32 0
    store i64 330, ptr %.t_36
    %.t_37 = load ptr, ptr %.s_7
    %.t_38 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_37, i32 0, i32 0
    %.t_39 = load ptr, ptr %.t_38
    %.t_40 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_39, i32 0, i32 0
    %.t_41 = load i64, ptr %.t_40
    call void @matcha_print_int(i64 %.t_41)
    %.t_42 = load ptr, ptr %.s_7
    %.t_43 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_42, i32 0, i32 1
    %.t_44 = load ptr, ptr %.t_43
    %.t_45 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_44, i32 0, i32 1
    %.t_46 = load i64, ptr %.t_45
    call void @matcha_print_int(i64 %.t_46)
    %.t_47 = getelementptr inbounds [27 x i8], [27 x i8]* @.string_literal_3, i64 0, i64 0
    %.t_48 = insertvalue %String undef, i8* %.t_47, 0
    %.t_49 = insertvalue %String %.t_48, i64 27, 1
    %.t_50 = extractvalue %String %.t_49, 0
    %.t_51 = extractvalue %String %.t_49, 1
    call void @matcha_print_string(ptr %.t_50, i64 %.t_51)
    br label %label_loop_header_0
label_loop_header_0:
    %.t_52 = load i64, ptr %.s_3
    %.t_53 = icmp slt i64 %.t_52, 10
    br i1 %.t_53, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_54 = load i64, ptr %.s_3
    %.t_55 = add i64 %.t_54, 1
    store i64 %.t_55, ptr %.s_3
    %.t_56 = load i64, ptr %.s_3
    call void @matcha_print_int(i64 %.t_56)
    br label %label_loop_continue_2
label_loop_continue_2:
    br label %label_loop_header_0
label_loop_exit_3:
    ret i32 0

}
