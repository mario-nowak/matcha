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
    br i1 0, label %label_then_0, label %label_else_1
label_then_0:
    br label %label_continue_2
label_else_1:
    br label %label_continue_2
label_continue_2:
    br i1 0, label %label_then_3, label %label_else_4
label_then_3:
    br label %label_continue_5
label_else_4:
    br label %label_continue_5
label_continue_5:
    br i1 0, label %label_then_6, label %label_else_7
label_then_6:
    br label %label_continue_8
label_else_7:
    br label %label_continue_8
label_continue_8:
    %.t_11 = phi i64 [3, %label_then_6], [4, %label_else_7]
    br i1 1, label %label_then_9, label %label_else_10
label_then_9:
    br i1 0, label %label_then_12, label %label_else_13
label_then_12:
    br label %label_continue_14
label_else_13:
    br label %label_continue_14
label_continue_14:
    %.t_12 = phi i64 [1, %label_then_12], [2, %label_else_13]
    br label %label_continue_11
label_else_10:
    br label %label_continue_11
label_continue_11:
    %.t_13 = phi i64 [%.t_12, %label_continue_14], [3, %label_else_10]
    br i1 1, label %label_then_15, label %label_else_16
label_then_15:
    br i1 0, label %label_then_18, label %label_else_19
label_then_18:
    br label %label_continue_20
label_else_19:
    br label %label_continue_20
label_continue_20:
    %.t_14 = phi i64 [1, %label_then_18], [2, %label_else_19]
    br label %label_continue_17
label_else_16:
    br label %label_continue_17
label_continue_17:
    %.t_15 = phi i64 [%.t_14, %label_continue_20], [3, %label_else_16]
    %.t_16 = add i64 %.t_15, 4
    %.t_17 = sub i64 0, 1
    %.t_18 = add i64 1, 2
    %.t_19 = mul i64 %.t_8, 2
    %.t_20 = add i64 %.t_8, %.t_19
    br i1 0, label %label_then_21, label %label_else_22
label_then_21:
    br label %label_continue_23
label_else_22:
    br label %label_continue_23
label_continue_23:
    %.t_21 = phi i64 [1, %label_then_21], [2, %label_else_22]
    %.t_22 = add i64 %.t_20, %.t_21

    ; get pointer to @.str
    %fmtptr = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
    ; call printf with formatting string and last expression
    call i32 (i8*, ...) @printf(i8* %fmtptr, i64 %.t_22)
    ret i32 0
}