declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
%String = type { i8*, i64 }

%matcha_structure_0_Point = type { i64, i64 }
%matcha_structure_1_PointHolder = type { ptr, ptr }

define i64 @matcha_function_2_someFunction() {
entry:

    ret i64 2

}

define i32 @main() {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca i64

    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
    %.t_1 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
    store i64 3, ptr %.t_1
    %.t_2 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 1
    store i64 1, ptr %.t_2
    store ptr %.t_0, ptr %.s_0
    store i64 2, ptr %.s_1
    ret i32 0

}
