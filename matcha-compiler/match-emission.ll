declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_print_string(ptr, i64)

%String = type { i8*, i64 }
%Array = type { i64, i64, ptr }

@.string_literal_0 = private unnamed_addr constant [16 x i8] c"I'm pretty happy"
@.string_literal_1 = private unnamed_addr constant [18 x i8] c"I'm not that happy"
@.string_literal_2 = private unnamed_addr constant [16 x i8] c"I'm pretty happy"
@.string_literal_3 = private unnamed_addr constant [18 x i8] c"I'm not that happy"
@.string_literal_4 = private unnamed_addr constant [16 x i8] c"Some side-effect"
@.string_literal_5 = private unnamed_addr constant [16 x i8] c"I'm pretty happy"
@.string_literal_6 = private unnamed_addr constant [18 x i8] c"I'm not that happy"
@.string_literal_7 = private unnamed_addr constant [16 x i8] c"Exhaustive happy"
@.string_literal_8 = private unnamed_addr constant [14 x i8] c"Exhaustive sad"

define i64 @matcha_function_0_myFunction(i64 %arg_0_parameter) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_parameter, ptr %.s_0
    %.t_0 = load i64, ptr %.s_0
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
    %.t_3 = load i64, ptr %.s_0
    br label %label_match_continue_0
label_match_continue_0:
    %.t_4 = phi i64 [1, %label_match_arm_2], [0, %label_match_arm_4], [%.t_3, %label_match_else_1]
    ret i64 %.t_4

}

define i32 @main() {
entry:
    %.s_0 = alloca i1

    %.t_0 = call i64 @matcha_function_0_myFunction(i64 0)
    call void @matcha_print_int(i64 %.t_0)
    %.t_1 = call i64 @matcha_function_0_myFunction(i64 1)
    call void @matcha_print_int(i64 %.t_1)
    %.t_2 = call i64 @matcha_function_0_myFunction(i64 2)
    call void @matcha_print_int(i64 %.t_2)
    store i1 1, ptr %.s_0
    %.t_3 = load i1, ptr %.s_0
    br i1 %.t_3, label %label_match_arm_2, label %label_match_else_1
label_match_arm_2:
    %.t_4 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_5 = insertvalue %String undef, i8* %.t_4, 0
    %.t_6 = insertvalue %String %.t_5, i64 16, 1
    %.t_7 = extractvalue %String %.t_6, 0
    %.t_8 = extractvalue %String %.t_6, 1
    call void @matcha_print_string(ptr %.t_7, i64 %.t_8)
    br label %label_match_continue_0
label_match_else_1:
    %.t_9 = getelementptr inbounds [18 x i8], [18 x i8]* @.string_literal_1, i64 0, i64 0
    %.t_10 = insertvalue %String undef, i8* %.t_9, 0
    %.t_11 = insertvalue %String %.t_10, i64 18, 1
    %.t_12 = extractvalue %String %.t_11, 0
    %.t_13 = extractvalue %String %.t_11, 1
    call void @matcha_print_string(ptr %.t_12, i64 %.t_13)
    br label %label_match_continue_0
label_match_continue_0:
    %.t_14 = load i1, ptr %.s_0
    br i1 %.t_14, label %label_match_arm_5, label %label_match_else_4
label_match_arm_5:
    %.t_15 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_2, i64 0, i64 0
    %.t_16 = insertvalue %String undef, i8* %.t_15, 0
    %.t_17 = insertvalue %String %.t_16, i64 16, 1
    br label %label_match_continue_3
label_match_else_4:
    %.t_18 = getelementptr inbounds [18 x i8], [18 x i8]* @.string_literal_3, i64 0, i64 0
    %.t_19 = insertvalue %String undef, i8* %.t_18, 0
    %.t_20 = insertvalue %String %.t_19, i64 18, 1
    br label %label_match_continue_3
label_match_continue_3:
    %.t_21 = phi %String [%.t_17, %label_match_arm_5], [%.t_20, %label_match_else_4]
    %.t_22 = extractvalue %String %.t_21, 0
    %.t_23 = extractvalue %String %.t_21, 1
    call void @matcha_print_string(ptr %.t_22, i64 %.t_23)
    %.t_24 = load i1, ptr %.s_0
    br i1 %.t_24, label %label_match_arm_8, label %label_match_else_7
label_match_arm_8:
    %.t_25 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_4, i64 0, i64 0
    %.t_26 = insertvalue %String undef, i8* %.t_25, 0
    %.t_27 = insertvalue %String %.t_26, i64 16, 1
    %.t_28 = extractvalue %String %.t_27, 0
    %.t_29 = extractvalue %String %.t_27, 1
    call void @matcha_print_string(ptr %.t_28, i64 %.t_29)
    %.t_30 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_5, i64 0, i64 0
    %.t_31 = insertvalue %String undef, i8* %.t_30, 0
    %.t_32 = insertvalue %String %.t_31, i64 16, 1
    br label %label_match_continue_6
label_match_else_7:
    %.t_33 = getelementptr inbounds [18 x i8], [18 x i8]* @.string_literal_6, i64 0, i64 0
    %.t_34 = insertvalue %String undef, i8* %.t_33, 0
    %.t_35 = insertvalue %String %.t_34, i64 18, 1
    br label %label_match_continue_6
label_match_continue_6:
    %.t_36 = phi %String [%.t_32, %label_match_arm_8], [%.t_35, %label_match_else_7]
    %.t_37 = extractvalue %String %.t_36, 0
    %.t_38 = extractvalue %String %.t_36, 1
    call void @matcha_print_string(ptr %.t_37, i64 %.t_38)
    %.t_39 = load i1, ptr %.s_0
    %.t_40 = icmp eq i1 %.t_39, 1
    br i1 %.t_40, label %label_match_arm_10, label %label_match_next_11
label_match_arm_10:
    %.t_41 = getelementptr inbounds [16 x i8], [16 x i8]* @.string_literal_7, i64 0, i64 0
    %.t_42 = insertvalue %String undef, i8* %.t_41, 0
    %.t_43 = insertvalue %String %.t_42, i64 16, 1
    %.t_44 = extractvalue %String %.t_43, 0
    %.t_45 = extractvalue %String %.t_43, 1
    call void @matcha_print_string(ptr %.t_44, i64 %.t_45)
    br label %label_match_continue_9
label_match_next_11:
    br label %label_match_arm_12
label_match_arm_12:
    %.t_46 = getelementptr inbounds [14 x i8], [14 x i8]* @.string_literal_8, i64 0, i64 0
    %.t_47 = insertvalue %String undef, i8* %.t_46, 0
    %.t_48 = insertvalue %String %.t_47, i64 14, 1
    %.t_49 = extractvalue %String %.t_48, 0
    %.t_50 = extractvalue %String %.t_48, 1
    call void @matcha_print_string(ptr %.t_49, i64 %.t_50)
    br label %label_match_continue_9
label_match_continue_9:
    ret i32 0

}
