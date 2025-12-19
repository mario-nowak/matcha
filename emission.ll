; Formatting constant
@.str = private unnamed_addr constant [4 x i8] c"%d\0A\00"
; Tell LLVM C's printf exists
declare i32 @printf(i8*, ...)
define i32 @main() {
entry:


%.t_0 = mul i32 2, 3

%.t_1 = mul i32 %.t_0, 0


%.t_2 = mul i32 0, 0
%.t_3 = sub i32 %.t_1, %.t_2
    ; get pointer to @.str
    %fmtptr = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
    ; call printf with formatting string and last expression
    call i32 (i8*, ...) @printf(i8* %fmtptr, i32 %.t_3)

    ret i32 %.t_3
}