@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c"%d\0A\00"
declare i32 @printf(i8*, ...)
define i32 @main() {
entry:
    %.s_0 = alloca i64

    store i64 0, i64* %.s_0
    br label %label_loop_header_0
label_loop_header_0:
    %.t_0 = load i64, i64* %.s_0
    %.t_1 = icmp slt i64 %.t_0, 10
    br i1 %.t_1, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_2 = load i64, i64* %.s_0
    %.t_3 = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0
    call i32 (i8*, ...) @printf(i8* %.t_3, i64 %.t_2)
    %.t_4 = load i64, i64* %.s_0
    %.t_5 = icmp sge i64 %.t_4, 5
    br i1 %.t_5, label %label_then_4, label %label_continue_5
label_then_4:
    br label %label_loop_exit_3
label_continue_5:
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_6 = load i64, i64* %.s_0
    %.t_7 = add i64 %.t_6, 1
    store i64 %.t_7, i64* %.s_0
    br label %label_loop_header_0
label_loop_exit_3:

    ret i32 0
}