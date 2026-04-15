%String = type { i8*, i64 }

@.string_literal_0 = private unnamed_addr constant [10 x i8] c"It's true!"
@.string_literal_1 = private unnamed_addr constant [11 x i8] c"It's false!"
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

define i32 @main() {
entry:

    %.t_0 = icmp eq i1 0, 1
    br i1 %.t_0, label %label_match_arm_1, label %label_match_next_2
label_match_arm_1:
    %.t_1 = getelementptr inbounds [10 x i8], [10 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_2 = insertvalue %String undef, i8* %.t_1, 0
    %.t_3 = insertvalue %String %.t_2, i64 10, 1
    call void @builtin_printString(%String %.t_3)
    br label %label_match_continue_0
label_match_next_2:
    br label %label_match_arm_3
label_match_arm_3:
    %.t_4 = getelementptr inbounds [11 x i8], [11 x i8]* @.string_literal_1, i64 0, i64 0
    %.t_5 = insertvalue %String undef, i8* %.t_4, 0
    %.t_6 = insertvalue %String %.t_5, i64 11, 1
    call void @builtin_printString(%String %.t_6)
    br label %label_match_continue_0
label_match_continue_0:
    ret i32 0

}
