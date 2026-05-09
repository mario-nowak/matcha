declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_read_file(ptr, ptr, i64)
declare ptr @matcha_string_split(ptr, i64, ptr, i64)

%String = type { i8*, i64 }
%Array = type { i64, i64, ptr }

@.string_literal_0 = private unnamed_addr constant [21 x i8] c"aoc-2024-01-input.txt"
@.string_literal_1 = private unnamed_addr constant [1 x i8] c"\0A"

define i32 @main() {
entry:
    %.s_0 = alloca %String
    %.s_1 = alloca %String
    %.s_2 = alloca ptr

    %.t_0 = getelementptr inbounds [21 x i8], [21 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_1 = insertvalue %String undef, i8* %.t_0, 0
    %.t_2 = insertvalue %String %.t_1, i64 21, 1
    %.t_3 = extractvalue %String %.t_2, 0
    %.t_4 = extractvalue %String %.t_2, 1
    call void @matcha_read_file(ptr %.s_0, ptr %.t_3, i64 %.t_4)
    %.t_5 = load %String, ptr %.s_0
    store %String %.t_5, ptr %.s_1
    %.t_6 = load %String, ptr %.s_1
    %.t_7 = getelementptr inbounds [1 x i8], [1 x i8]* @.string_literal_1, i64 0, i64 0
    %.t_8 = insertvalue %String undef, i8* %.t_7, 0
    %.t_9 = insertvalue %String %.t_8, i64 1, 1
    %.t_10 = extractvalue %String %.t_6, 0
    %.t_11 = extractvalue %String %.t_6, 1
    %.t_12 = extractvalue %String %.t_9, 0
    %.t_13 = extractvalue %String %.t_9, 1
    %.t_14 = call ptr @matcha_string_split(ptr %.t_10, i64 %.t_11, ptr %.t_12, i64 %.t_13)
    store ptr %.t_14, ptr %.s_2
    %.t_15 = load ptr, ptr %.s_2
    %.t_16 = getelementptr inbounds %Array, ptr %.t_15, i32 0, i32 0
    %.t_17 = load i64, ptr %.t_16
    call void @matcha_print_int(i64 %.t_17)
    ret i32 0

}
