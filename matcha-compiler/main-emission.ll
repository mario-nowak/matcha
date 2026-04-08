@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c"%d\0A\00"
declare i32 @printf(i8*, ...)
define i32 @main() {
entry:
    %.s_0 = alloca i64
    %.s_1 = alloca i64
    %.s_2 = alloca i64
    %.s_3 = alloca i64
    %.s_4 = alloca i64
    %.s_5 = alloca i1
    %.s_6 = alloca i64
    %.s_7 = alloca i64
    %.s_8 = alloca i64
    %.s_9 = alloca i64
    %.s_10 = alloca i64
    %.s_11 = alloca i64
    %.s_12 = alloca i1
    %.s_13 = alloca i1
    %.s_14 = alloca i64
    %.s_15 = alloca i64
    %.s_16 = alloca i64
    %.s_17 = alloca i64
    %.s_18 = alloca i64
    %.s_19 = alloca i1
    %.s_20 = alloca i64
    %.s_21 = alloca i1
    %.s_22 = alloca i1
    %.s_23 = alloca i1
    %.s_24 = alloca i1
    %.s_25 = alloca i64
    %.s_26 = alloca i1
    %.s_27 = alloca i64
    %.s_28 = alloca i64
    %.s_29 = alloca i64
    %.s_30 = alloca i64
    %.s_31 = alloca i64
    %.s_32 = alloca i64
    %.s_33 = alloca i64
    %.s_34 = alloca i1
    %.s_35 = alloca i64
    %.s_36 = alloca i64
    %.s_37 = alloca i64
    %.s_38 = alloca i1
    %.s_39 = alloca i64

    %.t_0 = add i64 2, 3
    %.t_1 = mul i64 %.t_0, 4
    %.t_2 = sub i64 3, 4
    %.t_3 = mul i64 %.t_1, %.t_2
    %.t_4 = add i64 1, %.t_3
    store i64 %.t_4, i64* %.s_0
    %.t_5 = load i64, i64* %.s_0
    %.t_6 = add i64 1, %.t_5
    %.t_7 = mul i64 %.t_6, 4
    store i64 %.t_7, i64* %.s_1
    %.t_8 = load i64, i64* %.s_0
    %.t_9 = load i64, i64* %.s_0
    %.t_10 = mul i64 %.t_8, %.t_9
    %.t_11 = load i64, i64* %.s_1
    %.t_12 = add i64 %.t_10, %.t_11
    store i64 %.t_12, i64* %.s_2
    %.t_13 = load i64, i64* %.s_2
    %.t_14 = add i64 %.t_13, 1
    store i64 %.t_14, i64* %.s_3
    %.t_15 = load i64, i64* %.s_3
    %.t_16 = mul i64 %.t_15, 2
    store i64 %.t_16, i64* %.s_4
    store i1 0, i1* %.s_5
    %.t_17 = load i1, i1* %.s_5
    br i1 %.t_17, label %label_then_0, label %label_continue_1
label_then_0:
    store i64 4, i64* %.s_6
    br label %label_continue_1
label_continue_1:
    %.t_18 = load i1, i1* %.s_5
    br i1 %.t_18, label %label_then_2, label %label_else_3
label_then_2:
    store i64 3, i64* %.s_7
    br label %label_continue_4
label_else_3:
    store i64 5, i64* %.s_8
    br label %label_continue_4
label_continue_4:
    %.t_19 = load i1, i1* %.s_5
    br i1 %.t_19, label %label_then_5, label %label_else_6
label_then_5:
    br label %label_continue_7
label_else_6:
    br label %label_continue_7
label_continue_7:
    %.t_20 = phi i64 [3, %label_then_5], [4, %label_else_6]
    store i64 %.t_20, i64* %.s_9
    br i1 1, label %label_then_8, label %label_else_9
label_then_8:
    br i1 0, label %label_then_11, label %label_else_12
label_then_11:
    br label %label_continue_13
label_else_12:
    br label %label_continue_13
label_continue_13:
    %.t_21 = phi i64 [1, %label_then_11], [2, %label_else_12]
    br label %label_continue_10
label_else_9:
    br label %label_continue_10
label_continue_10:
    %.t_22 = phi i64 [%.t_21, %label_continue_13], [3, %label_else_9]
    store i64 %.t_22, i64* %.s_10
    br i1 1, label %label_then_14, label %label_else_15
label_then_14:
    br i1 0, label %label_then_17, label %label_else_18
label_then_17:
    br label %label_continue_19
label_else_18:
    br label %label_continue_19
label_continue_19:
    %.t_23 = phi i64 [1, %label_then_17], [2, %label_else_18]
    br label %label_continue_16
label_else_15:
    br label %label_continue_16
label_continue_16:
    %.t_24 = phi i64 [%.t_23, %label_continue_19], [3, %label_else_15]
    %.t_25 = add i64 %.t_24, 4
    store i64 %.t_25, i64* %.s_11
    store i1 1, i1* %.s_12
    store i1 1, i1* %.s_13
    store i64 2, i64* %.s_14
    %.t_26 = sub i64 0, 1
    store i64 %.t_26, i64* %.s_15
    %.t_27 = add i64 1, 2
    store i64 %.t_27, i64* %.s_16
    %.t_28 = load i64, i64* %.s_2
    store i64 %.t_28, i64* %.s_17
    %.t_29 = load i64, i64* %.s_2
    %.t_30 = mul i64 %.t_29, 2
    store i64 %.t_30, i64* %.s_18
    store i1 0, i1* %.s_19
    %.t_31 = load i64, i64* %.s_17
    %.t_32 = load i64, i64* %.s_18
    %.t_33 = add i64 %.t_31, %.t_32
    %.t_34 = load i1, i1* %.s_19
    %.t_35 = xor i1 %.t_34, 1
    br i1 %.t_35, label %label_then_20, label %label_else_21
label_then_20:
    br label %label_continue_22
label_else_21:
    br label %label_continue_22
label_continue_22:
    %.t_36 = phi i64 [1, %label_then_20], [2, %label_else_21]
    %.t_37 = add i64 %.t_33, %.t_36
    store i64 %.t_37, i64* %.s_20
    store i1 1, i1* %.s_21
    store i1 0, i1* %.s_22
    %.t_38 = load i1, i1* %.s_21
    %.t_39 = load i1, i1* %.s_22
    %.t_40 = or i1 %.t_38, %.t_39
    store i1 %.t_40, i1* %.s_23
    %.t_41 = load i1, i1* %.s_21
    %.t_42 = load i1, i1* %.s_22
    %.t_43 = and i1 %.t_41, %.t_42
    store i1 %.t_43, i1* %.s_24
    %.t_44 = load i1, i1* %.s_23
    br i1 %.t_44, label %label_then_23, label %label_else_24
label_then_23:
    %.t_45 = load i1, i1* %.s_24
    br i1 %.t_45, label %label_then_26, label %label_else_27
label_then_26:
    br label %label_continue_28
label_else_27:
    br label %label_continue_28
label_continue_28:
    %.t_46 = phi i64 [2, %label_then_26], [1, %label_else_27]
    br label %label_continue_25
label_else_24:
    br label %label_continue_25
label_continue_25:
    %.t_47 = phi i64 [%.t_46, %label_continue_28], [0, %label_else_24]
    store i64 %.t_47, i64* %.s_25
    %.t_48 = load i64, i64* %.s_25
    %.t_49 = icmp sge i64 %.t_48, 1
    store i1 %.t_49, i1* %.s_26
    %.t_50 = load i1, i1* %.s_26
    br i1 %.t_50, label %label_then_29, label %label_else_30
label_then_29:
    br label %label_continue_31
label_else_30:
    br label %label_continue_31
label_continue_31:
    %.t_51 = phi i64 [1, %label_then_29], [0, %label_else_30]
    store i64 %.t_51, i64* %.s_27
    store i64 10, i64* %.s_28
    %.t_52 = load i64, i64* %.s_28
    %.t_53 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_53, i64 %.t_52)
    %.t_54 = load i64, i64* %.s_28
    %.t_55 = mul i64 %.t_54, 2
    store i64 %.t_55, i64* %.s_28
    %.t_56 = load i64, i64* %.s_28
    %.t_57 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_57, i64 %.t_56)
    store i64 6, i64* %.s_29
    store i64 0, i64* %.s_30
    store i64 0, i64* %.s_31
    br label %label_loop_header_32
label_loop_header_32:
    br label %label_loop_body_33
label_loop_body_33:
    %.t_58 = load i64, i64* %.s_31
    %.t_59 = load i64, i64* %.s_29
    %.t_60 = icmp sge i64 %.t_58, %.t_59
    br i1 %.t_60, label %label_then_36, label %label_continue_37
label_then_36:
    br label %label_loop_exit_35
label_continue_37:
    store i64 1, i64* %.s_32
    br label %label_loop_header_38
label_loop_header_38:
    br label %label_loop_body_39
label_loop_body_39:
    %.t_61 = load i64, i64* %.s_30
    %.t_62 = load i64, i64* %.s_32
    %.t_63 = add i64 %.t_61, %.t_62
    store i64 %.t_63, i64* %.s_30
    %.t_64 = load i64, i64* %.s_32
    %.t_65 = add i64 %.t_64, 1
    store i64 %.t_65, i64* %.s_32
    %.t_66 = load i64, i64* %.s_32
    %.t_67 = load i64, i64* %.s_31
    %.t_68 = add i64 %.t_67, 1
    %.t_69 = icmp sgt i64 %.t_66, %.t_68
    br i1 %.t_69, label %label_then_42, label %label_continue_43
label_then_42:
    br label %label_loop_exit_41
label_continue_43:
    br label %label_loop_continue_40
label_loop_continue_40:
    br label %label_loop_header_38
label_loop_exit_41:
    %.t_70 = load i64, i64* %.s_31
    %.t_71 = add i64 %.t_70, 1
    store i64 %.t_71, i64* %.s_31
    br label %label_loop_continue_34
label_loop_continue_34:
    br label %label_loop_header_32
label_loop_exit_35:
    %.t_72 = load i64, i64* %.s_30
    %.t_73 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_73, i64 %.t_72)
    %.t_74 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_74, i64 0)
    store i64 5, i64* %.s_33
    store i1 0, i1* %.s_34
    store i64 0, i64* %.s_35
    store i64 1, i64* %.s_36
    br label %label_loop_header_44
label_loop_header_44:
    br label %label_loop_body_45
label_loop_body_45:
    %.t_75 = load i64, i64* %.s_36
    %.t_76 = load i64, i64* %.s_33
    %.t_77 = icmp sge i64 %.t_75, %.t_76
    br i1 %.t_77, label %label_then_48, label %label_continue_49
label_then_48:
    br label %label_loop_exit_47
label_continue_49:
    %.t_78 = load i1, i1* %.s_34
    br i1 %.t_78, label %label_then_50, label %label_else_51
label_then_50:
    %.t_79 = load i64, i64* %.s_36
    %.t_80 = add i64 %.t_79, 1
    store i64 %.t_80, i64* %.s_36
    %.t_81 = load i1, i1* %.s_34
    %.t_82 = xor i1 %.t_81, 1
    store i1 %.t_82, i1* %.s_34
    br label %label_loop_continue_46
label_else_51:
    %.t_83 = load i64, i64* %.s_35
    %.t_84 = load i64, i64* %.s_36
    %.t_85 = add i64 %.t_83, %.t_84
    store i64 %.t_85, i64* %.s_35
    %.t_86 = load i64, i64* %.s_35
    %.t_87 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_87, i64 %.t_86)
    br label %label_continue_52
label_continue_52:
    %.t_88 = load i64, i64* %.s_36
    %.t_89 = add i64 %.t_88, 1
    store i64 %.t_89, i64* %.s_36
    %.t_90 = load i1, i1* %.s_34
    %.t_91 = xor i1 %.t_90, 1
    store i1 %.t_91, i1* %.s_34
    br label %label_loop_continue_46
label_loop_continue_46:
    br label %label_loop_header_44
label_loop_exit_47:
    %.t_92 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_92, i64 0)
    %.t_93 = load i64, i64* %.s_35
    %.t_94 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_94, i64 %.t_93)
    store i64 1, i64* %.s_37
    %.t_95 = load i64, i64* %.s_37
    %.t_96 = icmp sle i64 %.t_95, 10
    br i1 %.t_96, label %label_then_53, label %label_continue_54
label_then_53:
    %.t_97 = load i64, i64* %.s_37
    %.t_98 = add i64 %.t_97, 1
    store i64 %.t_98, i64* %.s_37
    br label %label_continue_54
label_continue_54:
    %.t_99 = load i64, i64* %.s_37
    %.t_100 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_100, i64 %.t_99)
    store i1 1, i1* %.s_38
    br label %label_loop_header_55
label_loop_header_55:
    %.t_101 = load i1, i1* %.s_38
    br i1 %.t_101, label %label_loop_body_56, label %label_loop_exit_58
label_loop_body_56:
    store i1 0, i1* %.s_38
    br label %label_loop_continue_57
label_loop_continue_57:
    br label %label_loop_header_55
label_loop_exit_58:
    store i64 0, i64* %.s_39
    br label %label_loop_header_59
label_loop_header_59:
    %.t_102 = load i64, i64* %.s_39
    %.t_103 = icmp slt i64 %.t_102, 10
    br i1 %.t_103, label %label_loop_body_60, label %label_loop_exit_62
label_loop_body_60:
    %.t_104 = load i64, i64* %.s_39
    %.t_105 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_105, i64 %.t_104)
    %.t_106 = load i64, i64* %.s_39
    %.t_107 = add i64 %.t_106, 1
    store i64 %.t_107, i64* %.s_39
    br label %label_loop_continue_61
label_loop_continue_61:
    br label %label_loop_header_59
label_loop_exit_62:

    ret i32 0
}