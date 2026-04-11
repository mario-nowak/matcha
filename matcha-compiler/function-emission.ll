@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c"%d\0A\00"
declare i32 @printf(i8*, ...)

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
    %.t_1 = mul i64 %.t_0, 2
    ret i64 %.t_1

}

define i1 @matcha_1_myFunctionWithComplexBody(i64 %arg_0_parameter) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_parameter, i64* %.s_0
    %.t_0 = load i64, i64* %.s_0
    %.t_1 = icmp sge i64 %.t_0, 0
    br i1 %.t_1, label %label_then_0, label %label_else_1
label_then_0:
    ret i1 1
label_else_1:
    ret i1 0

}

define void @matcha_2_myFunctionToTestControlFlowValidation(i64 %arg_0_parameter) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_parameter, i64* %.s_0
    %.t_0 = load i64, i64* %.s_0
    %.t_1 = icmp eq i64 %.t_0, 0
    br i1 %.t_1, label %label_then_0, label %label_continue_1
label_then_0:
    ret void
label_continue_1:
    ret void

}

define i64 @matcha_3_g() {
entry:

    %.t_0 = add i64 3, 2
    ret i64 %.t_0

}

define i64 @matcha_4_f(i64 %arg_0_g) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_g, i64* %.s_0
    %.t_0 = load i64, i64* %.s_0
    ret i64 %.t_0

}

define i32 @main() {
entry:

    call void @matcha_2_myFunctionToTestControlFlowValidation(i64 3)
    %.t_0 = call i64 @matcha_4_f(i64 3)
    call void @builtin_printInt(i64 %.t_0)
    %.t_1 = call i64 @matcha_3_g()
    call void @builtin_printInt(i64 %.t_1)
    ret i32 0

}
