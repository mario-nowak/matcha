; Formatting constant
@.str = private unnamed_addr constant [4 x i8] c"%d\0A\00"

; Tell LLVM C's printf exists
declare i32 @printf(i8*, ...)

define i32 @main() {
entry:
    ; Emit LLVM IR for first expression
    %variable.1 = add i32 2, 3
    %variable.2 = mul i32 %variable.1, 4
    %variable.3 = sub i32 3, 4
    %variable.4 = sub i32 0, %variable.3
    %variable.5 = mul i32 %variable.2, %variable.4
    %variable   = add i32 1, %variable.5

    ; Emit LLVM IR for second expression
    %otherVariable.1 = add i32 1, %variable
    %otherVariable   = mul i32 %otherVariable.1, 4

    %.intermediateVariable = add i32 %variable, %otherVariable

    ; print otherVariable
    ; get pointer to @.str
    %fmtptr = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
    ; call printf with formatting string and last expression
    call i32 (i8*, ...) @printf(i8* %fmtptr, i32 %otherVariable)

    ret i32 %otherVariable
}
