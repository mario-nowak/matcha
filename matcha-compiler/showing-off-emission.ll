declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
%String = type { i8*, i64 }

@.string_literal_0 = private unnamed_addr constant [7 x i8] c"Is zero"
@.string_literal_1 = private unnamed_addr constant [11 x i8] c"Hello world"
@.print_string_newline = private unnamed_addr constant [1 x i8] c"\0A"
@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c"%d\0A\00"

declare i64 @write(i32, i8*, i64)
declare i32 @printf(i8*, ...)

%matcha_structure_2_Point = type { i64, i64 }

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
    br label %label_loop_header_0
label_loop_header_0:
    %.t_15 = load i64, ptr %.s_3
    %.t_16 = icmp slt i64 %.t_15, 10
    br i1 %.t_16, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_17 = load i64, ptr %.s_3
    %.t_18 = add i64 %.t_17, 1
    store i64 %.t_18, ptr %.s_3
    %.t_19 = load i64, ptr %.s_3
    call void @builtin_printInt(i64 %.t_19)
    br label %label_loop_continue_2
label_loop_continue_2:
    br label %label_loop_header_0
label_loop_exit_3:
    ret i32 0

}
