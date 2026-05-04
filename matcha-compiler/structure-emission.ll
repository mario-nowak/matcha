declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)

%String = type { i8*, i64 }
%Array = type { i64, ptr }

%matcha_structure_0_Point = type { i64, i64 }
define ptr @matcha_structure_0_Point__function_7_movedBy(ptr %arg_0_self, ptr %arg_1_other) {
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
