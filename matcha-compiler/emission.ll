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
    %.t_11 = sub i64 0, 1
    %.t_12 = add i64 1, 2
    %.t_13 = mul i64 %.t_8, 2
    %.t_14 = add i64 %.t_8, %.t_13
    %.t_15 = add i64 %.t_14, 1

    ; get pointer to @.str
    %fmtptr = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
    ; call printf with formatting string and last expression
    call i32 (i8*, ...) @printf(i8* %fmtptr, i64 %.t_15)
    ret i32 0
}