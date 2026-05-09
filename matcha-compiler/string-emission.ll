declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_string(ptr, i64)

%String = type { i8*, i64 }
%Array = type { i64, i64, ptr }

@.string_literal_0 = private unnamed_addr constant [5 x i8] c"Hello"

define %String @matcha_function_0_identity(%String %arg_0_value) {
entry:
    %.s_0 = alloca %String

    store %String %arg_0_value, ptr %.s_0
    %.t_0 = load %String, ptr %.s_0
    ret %String %.t_0

}

define i32 @main() {
entry:
    %.s_0 = alloca %String

    %.t_0 = getelementptr inbounds [5 x i8], [5 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_1 = insertvalue %String undef, i8* %.t_0, 0
    %.t_2 = insertvalue %String %.t_1, i64 5, 1
    store %String %.t_2, ptr %.s_0
    %.t_3 = load %String, ptr %.s_0
    %.t_4 = call %String @matcha_function_0_identity(%String %.t_3)
    %.t_5 = extractvalue %String %.t_4, 0
    %.t_6 = extractvalue %String %.t_4, 1
    call void @matcha_print_string(ptr %.t_5, i64 %.t_6)
    %.t_7 = load %String, ptr %.s_0
    %.t_8 = call %String @matcha_function_0_identity(%String %.t_7)
    %.t_9 = extractvalue %String %.t_8, 0
    %.t_10 = extractvalue %String %.t_8, 1
    call void @matcha_print_string(ptr %.t_9, i64 %.t_10)
    %.t_11 = load %String, ptr %.s_0
    %.t_12 = call %String @matcha_function_0_identity(%String %.t_11)
    %.t_13 = extractvalue %String %.t_12, 0
    %.t_14 = extractvalue %String %.t_12, 1
    call void @matcha_print_string(ptr %.t_13, i64 %.t_14)
    %.t_15 = load %String, ptr %.s_0
    %.t_16 = call %String @matcha_function_0_identity(%String %.t_15)
    %.t_17 = extractvalue %String %.t_16, 0
    %.t_18 = extractvalue %String %.t_16, 1
    call void @matcha_print_string(ptr %.t_17, i64 %.t_18)
    ret i32 0

}
