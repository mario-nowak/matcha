%String = type { i8*, i64 }

@.string_literal_0 = private unnamed_addr constant [16 x i8] c"I'm pretty happy"
@.string_literal_1 = private unnamed_addr constant [18 x i8] c"I'm not that happy"
@.string_literal_2 = private unnamed_addr constant [16 x i8] c"I'm pretty happy"
@.string_literal_3 = private unnamed_addr constant [18 x i8] c"I'm not that happy"
@.string_literal_4 = private unnamed_addr constant [16 x i8] c"Some side-effect"
@.string_literal_5 = private unnamed_addr constant [16 x i8] c"I'm pretty happy"
@.string_literal_6 = private unnamed_addr constant [18 x i8] c"I'm not that happy"
@.string_literal_7 = private unnamed_addr constant [16 x i8] c"Exhaustive happy"
@.string_literal_8 = private unnamed_addr constant [14 x i8] c"Exhaustive sad"
@.print_string_newline = private unnamed_addr constant [1 x i8] c"\0A"
@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c"%d\0A\00"

declare i64 @write(i32, i8*, i64)
declare i32 @printf(i8*, ...)

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

define i64 @matcha_0_myFunction(i64 %arg_0_parameter) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_parameter, i64* %.s_0
    %.t_0 = load i64, i64* %.s_0
    %.t_1 = icmp eq i64 %.t_0, 0
    br i1 %.t_1, label %label_match_arm_2, label %label_match_next_3
label_match_arm_2:
    br label %label_match_continue_0
label_match_next_3:
    %.t_2 = icmp eq i64 %.t_0, 1
    br i1 %.t_2, label %label_match_arm_4, label %label_match_else_1
label_match_arm_4:
    br label %label_match_continue_0
label_match_else_1:
    %.t_3 = load i64, i64* %.s_0
    br label %label_match_continue_0
label_match_continue_0:
    %.t_4 = phi i64 [1, %label_match_arm_2], [0, %label_match_arm_4], [%.t_3, %label_match_else_1]
    ret i64 %.t_4

}

define i32 @main() {
entry:
    %.s_0 = alloca i1

    %.t_0 = call i64 @matcha_0_myFunction(i64 0)
    call void @builtin_printInt(i64 %.t_0)
    %.t_1 = call i64 @matcha_0_myFunction(i64 1)
    call void @builtin_printInt(i64 %.t_1)
    %.t_2 = call i64 @matcha_0_myFunction(i64 2)
    call void @builtin_printInt(i64 %.t_2)
    store i1 1, i1* %.s_0
    %.t_3 = load i1, i1* %.s_0
    br i1 %.t_3, label %label_match_arm_2, label %label_match_else_1
label_match_arm_2:
    %.t_4 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_5 = insertvalue %String undef, i8* %.t_4, 0
    %.t_6 = insertvalue %String %.t_5, i64 16, 1
    call void @builtin_printString(%String %.t_6)
    br label %label_match_continue_0
label_match_else_1:
    %.t_7 = getelementptr inbounds [18 x i8], [18 x i8]* @.string_literal_1, i64 0, i64 0
    %.t_8 = insertvalue %String undef, i8* %.t_7, 0
    %.t_9 = insertvalue %String %.t_8, i64 18, 1
    call void @builtin_printString(%String %.t_9)
    br label %label_match_continue_0
label_match_continue_0:
    %.t_10 = load i1, i1* %.s_0
    br i1 %.t_10, label %label_match_arm_5, label %label_match_else_4
label_match_arm_5:
    %.t_11 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_2, i64 0, i64 0
    %.t_12 = insertvalue %String undef, i8* %.t_11, 0
    %.t_13 = insertvalue %String %.t_12, i64 16, 1
    br label %label_match_continue_3
label_match_else_4:
    %.t_14 = getelementptr inbounds [18 x i8], [18 x i8]* @.string_literal_3, i64 0, i64 0
    %.t_15 = insertvalue %String undef, i8* %.t_14, 0
    %.t_16 = insertvalue %String %.t_15, i64 18, 1
    br label %label_match_continue_3
label_match_continue_3:
    %.t_17 = phi %String [%.t_13, %label_match_arm_5], [%.t_16, %label_match_else_4]
    call void @builtin_printString(%String %.t_17)
    %.t_18 = load i1, i1* %.s_0
    br i1 %.t_18, label %label_match_arm_8, label %label_match_else_7
label_match_arm_8:
    %.t_19 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_4, i64 0, i64 0
    %.t_20 = insertvalue %String undef, i8* %.t_19, 0
    %.t_21 = insertvalue %String %.t_20, i64 16, 1
    call void @builtin_printString(%String %.t_21)
    %.t_22 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_5, i64 0, i64 0
    %.t_23 = insertvalue %String undef, i8* %.t_22, 0
    %.t_24 = insertvalue %String %.t_23, i64 16, 1
    br label %label_match_continue_6
label_match_else_7:
    %.t_25 = getelementptr inbounds [18 x i8], [18 x i8]* @.string_literal_6, i64 0, i64 0
    %.t_26 = insertvalue %String undef, i8* %.t_25, 0
    %.t_27 = insertvalue %String %.t_26, i64 18, 1
    br label %label_match_continue_6
label_match_continue_6:
    %.t_28 = phi %String [%.t_24, %label_match_arm_8], [%.t_27, %label_match_else_7]
    call void @builtin_printString(%String %.t_28)
    %.t_29 = load i1, i1* %.s_0
    %.t_30 = icmp eq i1 %.t_29, 1
    br i1 %.t_30, label %label_match_arm_10, label %label_match_next_11
label_match_arm_10:
    %.t_31 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_7, i64 0, i64 0
    %.t_32 = insertvalue %String undef, i8* %.t_31, 0
    %.t_33 = insertvalue %String %.t_32, i64 16, 1
    call void @builtin_printString(%String %.t_33)
    br label %label_match_continue_9
label_match_next_11:
    br label %label_match_arm_12
label_match_arm_12:
    %.t_34 = getelementptr inbounds [14 x i8], [14 x i8]* @.string_literal_8, i64 0, i64 0
    %.t_35 = insertvalue %String undef, i8* %.t_34, 0
    %.t_36 = insertvalue %String %.t_35, i64 14, 1
    call void @builtin_printString(%String %.t_36)
    br label %label_match_continue_9
label_match_continue_9:
    ret i32 0

}
