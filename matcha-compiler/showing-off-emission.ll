declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
%String = type { i8*, i64 }

@.string_literal_0 = private unnamed_addr constant [7 x i8] c"Is zero"
@.string_literal_1 = private unnamed_addr constant [11 x i8] c"Hello world"
@.string_literal_2 = private unnamed_addr constant [15 x i8] c"Printing points"
@.string_literal_3 = private unnamed_addr constant [27 x i8] c"Printing the while loop now"
@.print_string_newline = private unnamed_addr constant [1 x i8] c"\0A"
@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c"%d\0A\00"

declare i64 @write(i32, i8*, i64)
declare i32 @printf(i8*, ...)

%matcha_structure_2_Point = type { i64, i64 }
%matcha_structure_3_NestedPoint = type { ptr, ptr }

define void @builtin_printString(%String %arg_0_value) {
entry:

    %.t_0 = extractvalue %String %arg_0_value, 0
    %.t_1 = extractvalue %String %arg_0_value, 1
    call i64 @write(i32 1, i8* %.t_0, i64 %.t_1)
    %.t_2 = getelementptr inbounds [1 x i8], [1 x i8]* @.print_string_newline, i64 0, i64 0
    call i64 @write(i32 1, i8* %.t_2, i64 1)
    ret void

}

define void @builtin_printInt(i64 %arg_0_value) {
entry:

    %.t_0 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_0, i64 %arg_0_value)
    ret void

}

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
    call void @builtin_printString(%String %.t_4)
    %.t_5 = load i64, ptr %.s_0
    ret i64 %.t_5
label_continue_0:
    %.t_6 = load i64, ptr %.s_0
    %.t_7 = add i64 %.t_6, 1
    ret i64 %.t_7

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
    call void @builtin_printInt(i64 %.t_2)
    %.t_3 = getelementptr inbounds [11 x i8], [11 x i8]* @.string_literal_1, i64 0, i64 0
    %.t_4 = insertvalue %String undef, i8* %.t_3, 0
    %.t_5 = insertvalue %String %.t_4, i64 11, 1
    call void @builtin_printString(%String %.t_5)
    %.t_6 = load i64, ptr %.s_1
    %.t_7 = call i64 @matcha_function_0_addOne(i64 %.t_6)
    call void @builtin_printInt(i64 %.t_7)
    store i64 4, ptr %.s_2
    %.t_8 = load i64, ptr %.s_2
    store i64 %.t_8, ptr %.s_3
    %.t_9 = load i64, ptr %.s_3
    call void @builtin_printInt(i64 %.t_9)
    %.t_10 = call i64 @matcha_function_1_complexFunction(i64 1)
    store i64 %.t_10, ptr %.s_4
    %.t_11 = load i64, ptr %.s_4
    call void @builtin_printInt(i64 %.t_11)
    store i1 1, ptr %.s_5
    %.t_12 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_2_Point, ptr null, i32 1) to i64))
    %.t_13 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_12, i32 0, i32 0
    store i64 4, ptr %.t_13
    %.t_14 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_12, i32 0, i32 1
    store i64 5, ptr %.t_14
    store ptr %.t_12, ptr %.s_6
    %.t_15 = load ptr, ptr %.s_6
    %.t_16 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_15, i32 0, i32 1
    store i64 2, ptr %.t_16
    %.t_17 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_3_NestedPoint, ptr null, i32 1) to i64))
    %.t_18 = load ptr, ptr %.s_6
    %.t_19 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_17, i32 0, i32 0
    store ptr %.t_18, ptr %.t_19
    %.t_20 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_2_Point, ptr null, i32 1) to i64))
    %.t_21 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_20, i32 0, i32 0
    store i64 3, ptr %.t_21
    %.t_22 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_20, i32 0, i32 1
    store i64 6, ptr %.t_22
    %.t_23 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_17, i32 0, i32 1
    store ptr %.t_20, ptr %.t_23
    store ptr %.t_17, ptr %.s_7
    %.t_24 = getelementptr inbounds [15 x i8], [15 x i8]* @.string_literal_2, i64 0, i64 0
    %.t_25 = insertvalue %String undef, i8* %.t_24, 0
    %.t_26 = insertvalue %String %.t_25, i64 15, 1
    call void @builtin_printString(%String %.t_26)
    %.t_27 = load ptr, ptr %.s_6
    %.t_28 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_27, i32 0, i32 0
    store i64 110, ptr %.t_28
    %.t_29 = load ptr, ptr %.s_7
    %.t_30 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_29, i32 0, i32 0
    %.t_31 = load ptr, ptr %.t_30
    %.t_32 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_31, i32 0, i32 0
    store i64 330, ptr %.t_32
    %.t_33 = load ptr, ptr %.s_7
    %.t_34 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_33, i32 0, i32 0
    %.t_35 = load ptr, ptr %.t_34
    %.t_36 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_35, i32 0, i32 0
    %.t_37 = load i64, ptr %.t_36
    call void @builtin_printInt(i64 %.t_37)
    %.t_38 = load ptr, ptr %.s_7
    %.t_39 = getelementptr inbounds %matcha_structure_3_NestedPoint, ptr %.t_38, i32 0, i32 1
    %.t_40 = load ptr, ptr %.t_39
    %.t_41 = getelementptr inbounds %matcha_structure_2_Point, ptr %.t_40, i32 0, i32 1
    %.t_42 = load i64, ptr %.t_41
    call void @builtin_printInt(i64 %.t_42)
    %.t_43 = getelementptr inbounds [27 x i8], [27 x i8]* @.string_literal_3, i64 0, i64 0
    %.t_44 = insertvalue %String undef, i8* %.t_43, 0
    %.t_45 = insertvalue %String %.t_44, i64 27, 1
    call void @builtin_printString(%String %.t_45)
    br label %label_loop_header_0
label_loop_header_0:
    %.t_46 = load i64, ptr %.s_3
    %.t_47 = icmp slt i64 %.t_46, 10
    br i1 %.t_47, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_48 = load i64, ptr %.s_3
    %.t_49 = add i64 %.t_48, 1
    store i64 %.t_49, ptr %.s_3
    %.t_50 = load i64, ptr %.s_3
    call void @builtin_printInt(i64 %.t_50)
    br label %label_loop_continue_2
label_loop_continue_2:
    br label %label_loop_header_0
label_loop_exit_3:
    ret i32 0

}
