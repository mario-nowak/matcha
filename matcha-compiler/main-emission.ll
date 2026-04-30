declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)

%String = type { i8*, i64 }

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
    store i64 %.t_4, ptr %.s_0
    %.t_5 = load i64, ptr %.s_0
    %.t_6 = add i64 1, %.t_5
    %.t_7 = mul i64 %.t_6, 4
    store i64 %.t_7, ptr %.s_1
    %.t_8 = load i64, ptr %.s_0
    %.t_9 = load i64, ptr %.s_0
    %.t_10 = mul i64 %.t_8, %.t_9
    %.t_11 = load i64, ptr %.s_1
    %.t_12 = add i64 %.t_10, %.t_11
    store i64 %.t_12, ptr %.s_2
    %.t_13 = load i64, ptr %.s_2
    %.t_14 = add i64 %.t_13, 1
    store i64 %.t_14, ptr %.s_3
    %.t_15 = load i64, ptr %.s_3
    %.t_16 = mul i64 %.t_15, 2
    store i64 %.t_16, ptr %.s_4
    store i1 0, ptr %.s_5
    %.t_17 = load i1, ptr %.s_5
    br i1 %.t_17, label %label_then_1, label %label_continue_0
label_then_1:
    store i64 4, ptr %.s_6
    br label %label_continue_0
label_continue_0:
    %.t_18 = load i1, ptr %.s_5
    br i1 %.t_18, label %label_then_4, label %label_else_3
label_then_4:
    store i64 3, ptr %.s_7
    br label %label_continue_2
label_else_3:
    store i64 5, ptr %.s_8
    br label %label_continue_2
label_continue_2:
    %.t_19 = load i1, ptr %.s_5
    br i1 %.t_19, label %label_then_7, label %label_else_6
label_then_7:
    br label %label_continue_5
label_else_6:
    br label %label_continue_5
label_continue_5:
    %.t_20 = phi i64 [3, %label_then_7], [4, %label_else_6]
    store i64 %.t_20, ptr %.s_9
    br i1 1, label %label_then_10, label %label_else_9
label_then_10:
    br i1 0, label %label_then_13, label %label_else_12
label_then_13:
    br label %label_continue_11
label_else_12:
    br label %label_continue_11
label_continue_11:
    %.t_21 = phi i64 [1, %label_then_13], [2, %label_else_12]
    br label %label_continue_8
label_else_9:
    br label %label_continue_8
label_continue_8:
    %.t_22 = phi i64 [%.t_21, %label_continue_11], [3, %label_else_9]
    store i64 %.t_22, ptr %.s_10
    br i1 1, label %label_then_16, label %label_else_15
label_then_16:
    br i1 0, label %label_then_19, label %label_else_18
label_then_19:
    br label %label_continue_17
label_else_18:
    br label %label_continue_17
label_continue_17:
    %.t_23 = phi i64 [1, %label_then_19], [2, %label_else_18]
    br label %label_continue_14
label_else_15:
    br label %label_continue_14
label_continue_14:
    %.t_24 = phi i64 [%.t_23, %label_continue_17], [3, %label_else_15]
    %.t_25 = add i64 %.t_24, 4
    store i64 %.t_25, ptr %.s_11
    store i1 1, ptr %.s_12
    store i1 1, ptr %.s_13
    store i64 2, ptr %.s_14
    %.t_26 = sub i64 0, 1
    store i64 %.t_26, ptr %.s_15
    %.t_27 = add i64 1, 2
    store i64 %.t_27, ptr %.s_16
    %.t_28 = load i64, ptr %.s_2
    store i64 %.t_28, ptr %.s_17
    %.t_29 = load i64, ptr %.s_2
    %.t_30 = mul i64 %.t_29, 2
    store i64 %.t_30, ptr %.s_18
    store i1 0, ptr %.s_19
    %.t_31 = load i64, ptr %.s_17
    %.t_32 = load i64, ptr %.s_18
    %.t_33 = add i64 %.t_31, %.t_32
    %.t_34 = load i1, ptr %.s_19
    %.t_35 = xor i1 %.t_34, 1
    br i1 %.t_35, label %label_then_22, label %label_else_21
label_then_22:
    br label %label_continue_20
label_else_21:
    br label %label_continue_20
label_continue_20:
    %.t_36 = phi i64 [1, %label_then_22], [2, %label_else_21]
    %.t_37 = add i64 %.t_33, %.t_36
    store i64 %.t_37, ptr %.s_20
    store i1 1, ptr %.s_21
    store i1 0, ptr %.s_22
    %.t_38 = load i1, ptr %.s_21
    %.t_39 = load i1, ptr %.s_22
    %.t_40 = or i1 %.t_38, %.t_39
    store i1 %.t_40, ptr %.s_23
    %.t_41 = load i1, ptr %.s_21
    %.t_42 = load i1, ptr %.s_22
    %.t_43 = and i1 %.t_41, %.t_42
    store i1 %.t_43, ptr %.s_24
    %.t_44 = load i1, ptr %.s_23
    br i1 %.t_44, label %label_then_25, label %label_else_24
label_then_25:
    %.t_45 = load i1, ptr %.s_24
    br i1 %.t_45, label %label_then_28, label %label_else_27
label_then_28:
    br label %label_continue_26
label_else_27:
    br label %label_continue_26
label_continue_26:
    %.t_46 = phi i64 [2, %label_then_28], [1, %label_else_27]
    br label %label_continue_23
label_else_24:
    br label %label_continue_23
label_continue_23:
    %.t_47 = phi i64 [%.t_46, %label_continue_26], [0, %label_else_24]
    store i64 %.t_47, ptr %.s_25
    %.t_48 = load i64, ptr %.s_25
    %.t_49 = icmp sge i64 %.t_48, 1
    store i1 %.t_49, ptr %.s_26
    %.t_50 = load i1, ptr %.s_26
    br i1 %.t_50, label %label_then_31, label %label_else_30
label_then_31:
    br label %label_continue_29
label_else_30:
    br label %label_continue_29
label_continue_29:
    %.t_51 = phi i64 [1, %label_then_31], [0, %label_else_30]
    store i64 %.t_51, ptr %.s_27
    store i64 10, ptr %.s_28
    %.t_52 = load i64, ptr %.s_28
    call void @matcha_print_int(i64 %.t_52)
    %.t_53 = load i64, ptr %.s_28
    %.t_54 = mul i64 %.t_53, 2
    store i64 %.t_54, ptr %.s_28
    %.t_55 = load i64, ptr %.s_28
    call void @matcha_print_int(i64 %.t_55)
    store i64 6, ptr %.s_29
    store i64 0, ptr %.s_30
    store i64 0, ptr %.s_31
    br label %label_loop_header_32
label_loop_header_32:
    br label %label_loop_body_33
label_loop_body_33:
    %.t_56 = load i64, ptr %.s_31
    %.t_57 = load i64, ptr %.s_29
    %.t_58 = icmp sge i64 %.t_56, %.t_57
    br i1 %.t_58, label %label_then_37, label %label_continue_36
label_then_37:
    br label %label_loop_exit_35
label_continue_36:
    store i64 1, ptr %.s_32
    br label %label_loop_header_38
label_loop_header_38:
    br label %label_loop_body_39
label_loop_body_39:
    %.t_59 = load i64, ptr %.s_30
    %.t_60 = load i64, ptr %.s_32
    %.t_61 = add i64 %.t_59, %.t_60
    store i64 %.t_61, ptr %.s_30
    %.t_62 = load i64, ptr %.s_32
    %.t_63 = add i64 %.t_62, 1
    store i64 %.t_63, ptr %.s_32
    %.t_64 = load i64, ptr %.s_32
    %.t_65 = load i64, ptr %.s_31
    %.t_66 = add i64 %.t_65, 1
    %.t_67 = icmp sgt i64 %.t_64, %.t_66
    br i1 %.t_67, label %label_then_43, label %label_continue_42
label_then_43:
    br label %label_loop_exit_41
label_continue_42:
    br label %label_loop_continue_40
label_loop_continue_40:
    br label %label_loop_header_38
label_loop_exit_41:
    %.t_68 = load i64, ptr %.s_31
    %.t_69 = add i64 %.t_68, 1
    store i64 %.t_69, ptr %.s_31
    br label %label_loop_continue_34
label_loop_continue_34:
    br label %label_loop_header_32
label_loop_exit_35:
    %.t_70 = load i64, ptr %.s_30
    call void @matcha_print_int(i64 %.t_70)
    call void @matcha_print_int(i64 0)
    store i64 5, ptr %.s_33
    store i1 0, ptr %.s_34
    store i64 0, ptr %.s_35
    store i64 1, ptr %.s_36
    br label %label_loop_header_44
label_loop_header_44:
    br label %label_loop_body_45
label_loop_body_45:
    %.t_71 = load i64, ptr %.s_36
    %.t_72 = load i64, ptr %.s_33
    %.t_73 = icmp sge i64 %.t_71, %.t_72
    br i1 %.t_73, label %label_then_49, label %label_continue_48
label_then_49:
    br label %label_loop_exit_47
label_continue_48:
    %.t_74 = load i1, ptr %.s_34
    br i1 %.t_74, label %label_then_52, label %label_else_51
label_then_52:
    %.t_75 = load i64, ptr %.s_36
    %.t_76 = add i64 %.t_75, 1
    store i64 %.t_76, ptr %.s_36
    %.t_77 = load i1, ptr %.s_34
    %.t_78 = xor i1 %.t_77, 1
    store i1 %.t_78, ptr %.s_34
    br label %label_loop_continue_46
label_else_51:
    %.t_79 = load i64, ptr %.s_35
    %.t_80 = load i64, ptr %.s_36
    %.t_81 = add i64 %.t_79, %.t_80
    store i64 %.t_81, ptr %.s_35
    %.t_82 = load i64, ptr %.s_35
    call void @matcha_print_int(i64 %.t_82)
    br label %label_continue_50
label_continue_50:
    %.t_83 = load i64, ptr %.s_36
    %.t_84 = add i64 %.t_83, 1
    store i64 %.t_84, ptr %.s_36
    %.t_85 = load i1, ptr %.s_34
    %.t_86 = xor i1 %.t_85, 1
    store i1 %.t_86, ptr %.s_34
    br label %label_loop_continue_46
label_loop_continue_46:
    br label %label_loop_header_44
label_loop_exit_47:
    call void @matcha_print_int(i64 0)
    %.t_87 = load i64, ptr %.s_35
    call void @matcha_print_int(i64 %.t_87)
    store i64 1, ptr %.s_37
    %.t_88 = load i64, ptr %.s_37
    %.t_89 = icmp sle i64 %.t_88, 10
    br i1 %.t_89, label %label_then_54, label %label_continue_53
label_then_54:
    %.t_90 = load i64, ptr %.s_37
    %.t_91 = add i64 %.t_90, 1
    store i64 %.t_91, ptr %.s_37
    br label %label_continue_53
label_continue_53:
    %.t_92 = load i64, ptr %.s_37
    call void @matcha_print_int(i64 %.t_92)
    store i1 1, ptr %.s_38
    br label %label_loop_header_55
label_loop_header_55:
    %.t_93 = load i1, ptr %.s_38
    br i1 %.t_93, label %label_loop_body_56, label %label_loop_exit_58
label_loop_body_56:
    store i1 0, ptr %.s_38
    br label %label_loop_continue_57
label_loop_continue_57:
    br label %label_loop_header_55
label_loop_exit_58:
    store i64 0, ptr %.s_39
    br label %label_loop_header_59
label_loop_header_59:
    %.t_94 = load i64, ptr %.s_39
    %.t_95 = icmp slt i64 %.t_94, 10
    br i1 %.t_95, label %label_loop_body_60, label %label_loop_exit_62
label_loop_body_60:
    %.t_96 = load i64, ptr %.s_39
    call void @matcha_print_int(i64 %.t_96)
    %.t_97 = load i64, ptr %.s_39
    %.t_98 = add i64 %.t_97, 1
    store i64 %.t_98, ptr %.s_39
    br label %label_loop_continue_61
label_loop_continue_61:
    br label %label_loop_header_59
label_loop_exit_62:
    ret i32 0

}
