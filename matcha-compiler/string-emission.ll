%String = type { i8*, i64 }

@.string_literal_0 = private unnamed_addr constant [5 x i8] c"Hello"
@.print_string_newline = private unnamed_addr constant [1 x i8] c"\0A"

declare i64 @write(i32, i8*, i64)

define void @builtin_printString(%String %arg_0_value) {
entry:

    %.t_0 = extractvalue %String %arg_0_value, 0
    %.t_1 = extractvalue %String %arg_0_value, 1
    call i64 @write(i32 1, i8* %.t_0, i64 %.t_1)
    %.t_2 = getelementptr inbounds [1 x i8], [1 x i8]* @.print_string_newline, i64 0, i64 0
    call i64 @write(i32 1, i8* %.t_2, i64 1)
    ret void

}

define %String @matcha_0_identity(%String %arg_0_value) {
entry:
    %.s_0 = alloca %String

    store %String %arg_0_value, %String* %.s_0
    %.t_0 = load %String, %String* %.s_0
    ret %String %.t_0

}

define i32 @main() {
entry:
    %.s_0 = alloca %String

    %.t_0 = getelementptr inbounds [5 x i8], [5 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_1 = insertvalue %String undef, i8* %.t_0, 0
    %.t_2 = insertvalue %String %.t_1, i64 5, 1
    store %String %.t_2, %String* %.s_0
    %.t_3 = load %String, %String* %.s_0
    %.t_4 = call %String @matcha_0_identity(%String %.t_3)
    call void @builtin_printString(%String %.t_4)
    %.t_5 = load %String, %String* %.s_0
    %.t_6 = call %String @matcha_0_identity(%String %.t_5)
    call void @builtin_printString(%String %.t_6)
    %.t_7 = load %String, %String* %.s_0
    %.t_8 = call %String @matcha_0_identity(%String %.t_7)
    call void @builtin_printString(%String %.t_8)
    %.t_9 = load %String, %String* %.s_0
    %.t_10 = call %String @matcha_0_identity(%String %.t_9)
    call void @builtin_printString(%String %.t_10)
    ret i32 0

}
