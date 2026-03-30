; Formatting constant
@.str = private unnamed_addr constant [4 x i8] c"%d\0A\00"
; Tell LLVM C's printf exists
declare i32 @printf(i8*, ...)
define i32 @main() {
entry:
    %.t_0 = add i64 2, 3
    %.t_1 = mul i64 %.t_0, 4
    %.t_2 = sub i64 3, 4
    %.t_3 = mul i64 %.t_1, %.t_2
    %.t_4 = add i64 1, %.t_3
    %.t_5 = add i64 1, %.t_4
    %.t_6 = mul i64 %.t_5, 4
    %.t_7 = mul i64 %.t_4, %.t_4
    %.t_8 = add i64 %.t_7, %.t_6
    %.t_9 = add i64 %.t_8, 1
    %.t_10 = mul i64 %.t_9, 2
    br i1 0, label %label_then_0, label %label_continue_1
label_then_0:
    br label %label_continue_1
label_continue_1:
    br i1 0, label %label_then_2, label %label_else_3
label_then_2:
    br label %label_continue_4
label_else_3:
    br label %label_continue_4
label_continue_4:
    br i1 0, label %label_then_5, label %label_else_6
label_then_5:
    br label %label_continue_7
label_else_6:
    br label %label_continue_7
label_continue_7:
    %.t_11 = phi i64 [3, %label_then_5], [4, %label_else_6]
    br i1 1, label %label_then_8, label %label_else_9
label_then_8:
    br i1 0, label %label_then_11, label %label_else_12
label_then_11:
    br label %label_continue_13
label_else_12:
    br label %label_continue_13
label_continue_13:
    %.t_12 = phi i64 [1, %label_then_11], [2, %label_else_12]
    br label %label_continue_10
label_else_9:
    br label %label_continue_10
label_continue_10:
    %.t_13 = phi i64 [%.t_12, %label_continue_13], [3, %label_else_9]
    br i1 1, label %label_then_14, label %label_else_15
label_then_14:
    br i1 0, label %label_then_17, label %label_else_18
label_then_17:
    br label %label_continue_19
label_else_18:
    br label %label_continue_19
label_continue_19:
    %.t_14 = phi i64 [1, %label_then_17], [2, %label_else_18]
    br label %label_continue_16
label_else_15:
    br label %label_continue_16
label_continue_16:
    %.t_15 = phi i64 [%.t_14, %label_continue_19], [3, %label_else_15]
    %.t_16 = add i64 %.t_15, 4
    %.t_17 = sub i64 0, 1
    %.t_18 = add i64 1, 2
    %.t_19 = mul i64 %.t_8, 2
    %.t_20 = add i64 %.t_8, %.t_19
    %.t_21 = xor i1 0, 1
    br i1 %.t_21, label %label_then_20, label %label_else_21
label_then_20:
    br label %label_continue_22
label_else_21:
    br label %label_continue_22
label_continue_22:
    %.t_22 = phi i64 [1, %label_then_20], [2, %label_else_21]
    %.t_23 = add i64 %.t_20, %.t_22
    %.t_24 = or i1 1, 0
    %.t_25 = and i1 1, 0
    br i1 %.t_24, label %label_then_23, label %label_else_24
label_then_23:
    br i1 %.t_25, label %label_then_26, label %label_else_27
label_then_26:
    br label %label_continue_28
label_else_27:
    br label %label_continue_28
label_continue_28:
    %.t_26 = phi i64 [2, %label_then_26], [1, %label_else_27]
    br label %label_continue_25
label_else_24:
    br label %label_continue_25
label_continue_25:
    %.t_27 = phi i64 [%.t_26, %label_continue_28], [0, %label_else_24]
    %.t_28 = icmp sge i64 %.t_27, 1
    br i1 %.t_28, label %label_then_29, label %label_else_30
label_then_29:
    br label %label_continue_31
label_else_30:
    br label %label_continue_31
label_continue_31:
    %.t_29 = phi i64 [1, %label_then_29], [0, %label_else_30]

    ; get pointer to @.str
    %fmtptr = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
    ; call printf with formatting string and last expression
    call i32 (i8*, ...) @printf(i8* %fmtptr, i64 %.t_29)
    ret i32 0
}