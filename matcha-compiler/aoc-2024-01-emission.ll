declare void @matcha_initiate_garbage_collector()
declare ptr @matcha_allocate(i64)
declare ptr @matcha_allocate_atomic(i64)
declare void @matcha_print_int(i64)
declare void @matcha_read_file(ptr, ptr, i64)
declare void @matcha_string_trim(ptr, ptr, i64)
declare ptr @matcha_string_split(ptr, i64, ptr, i64)
declare i64 @matcha_string_to_int(ptr, i64)
declare void @matcha_panic_index_out_of_bounds(i64, i64, i64, i64) noreturn
declare ptr @matcha_array_append_slot(ptr, i64)

%String = type { i8*, i64 }
%Array = type { i64, i64, ptr }

@.string_literal_0 = private unnamed_addr constant [21 x i8] c"aoc-2024-01-input.txt"
@.string_literal_1 = private unnamed_addr constant [1 x i8] c"\0A"
@.string_literal_2 = private unnamed_addr constant [2 x i8] c"  "

define i64 @matcha_function_0_absolute(i64 %arg_0_number) {
entry:
    %.s_0 = alloca i64

    store i64 %arg_0_number, ptr %.s_0
    %.t_0 = load i64, ptr %.s_0
    %.t_1 = icmp slt i64 %.t_0, 0
    br i1 %.t_1, label %label_match_arm_2, label %label_match_else_1
label_match_arm_2:
    %.t_2 = load i64, ptr %.s_0
    %.t_3 = sub i64 0, %.t_2
    br label %label_match_continue_0
label_match_else_1:
    %.t_4 = load i64, ptr %.s_0
    br label %label_match_continue_0
label_match_continue_0:
    %.t_5 = phi i64 [%.t_3, %label_match_arm_2], [%.t_4, %label_match_else_1]
    ret i64 %.t_5

}

define ptr @matcha_function_1_countSort(ptr %arg_0_array) {
entry:
    %.s_0 = alloca ptr
    %.s_1 = alloca i64
    %.s_2 = alloca i64
    %.s_3 = alloca i64
    %.s_4 = alloca ptr
    %.s_5 = alloca i64
    %.s_6 = alloca ptr

    store ptr %arg_0_array, ptr %.s_0
    %.t_0 = load ptr, ptr %.s_0
    %.t_1 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 0
    %.t_2 = load i64, ptr %.t_1
    store i64 %.t_2, ptr %.s_1
    %.t_3 = load ptr, ptr %.s_0
    %.t_4 = getelementptr inbounds %Array, ptr %.t_3, i32 0, i32 0
    %.t_5 = load i64, ptr %.t_4
    %.t_6 = getelementptr inbounds %Array, ptr %.t_3, i32 0, i32 2
    %.t_7 = load ptr, ptr %.t_6
    %.t_8 = icmp slt i64 0, 0
    %.t_9 = icmp sge i64 0, %.t_5
    %.t_10 = or i1 %.t_8, %.t_9
    br i1 %.t_10, label %label_index_panic_0, label %label_index_ok_1
label_index_panic_0:
    call void @matcha_panic_index_out_of_bounds(i64 10, i64 32, i64 0, i64 %.t_5)
    unreachable
label_index_ok_1:
    %.t_11 = getelementptr inbounds i64, ptr %.t_7, i64 0
    %.t_12 = load i64, ptr %.t_11
    store i64 %.t_12, ptr %.s_2
    store i64 0, ptr %.s_3
    br label %label_loop_header_2
label_loop_header_2:
    %.t_13 = load i64, ptr %.s_3
    %.t_14 = load i64, ptr %.s_1
    %.t_15 = icmp slt i64 %.t_13, %.t_14
    br i1 %.t_15, label %label_loop_body_3, label %label_loop_exit_5
label_loop_body_3:
    %.t_16 = load ptr, ptr %.s_0
    %.t_17 = load i64, ptr %.s_3
    %.t_18 = getelementptr inbounds %Array, ptr %.t_16, i32 0, i32 0
    %.t_19 = load i64, ptr %.t_18
    %.t_20 = getelementptr inbounds %Array, ptr %.t_16, i32 0, i32 2
    %.t_21 = load ptr, ptr %.t_20
    %.t_22 = icmp slt i64 %.t_17, 0
    %.t_23 = icmp sge i64 %.t_17, %.t_19
    %.t_24 = or i1 %.t_22, %.t_23
    br i1 %.t_24, label %label_index_panic_8, label %label_index_ok_9
label_index_panic_8:
    call void @matcha_panic_index_out_of_bounds(i64 13, i64 17, i64 %.t_17, i64 %.t_19)
    unreachable
label_index_ok_9:
    %.t_25 = getelementptr inbounds i64, ptr %.t_21, i64 %.t_17
    %.t_26 = load i64, ptr %.t_25
    %.t_27 = load i64, ptr %.s_2
    %.t_28 = icmp sgt i64 %.t_26, %.t_27
    br i1 %.t_28, label %label_then_7, label %label_continue_6
label_then_7:
    %.t_29 = load ptr, ptr %.s_0
    %.t_30 = load i64, ptr %.s_3
    %.t_31 = getelementptr inbounds %Array, ptr %.t_29, i32 0, i32 0
    %.t_32 = load i64, ptr %.t_31
    %.t_33 = getelementptr inbounds %Array, ptr %.t_29, i32 0, i32 2
    %.t_34 = load ptr, ptr %.t_33
    %.t_35 = icmp slt i64 %.t_30, 0
    %.t_36 = icmp sge i64 %.t_30, %.t_32
    %.t_37 = or i1 %.t_35, %.t_36
    br i1 %.t_37, label %label_index_panic_10, label %label_index_ok_11
label_index_panic_10:
    call void @matcha_panic_index_out_of_bounds(i64 14, i64 36, i64 %.t_30, i64 %.t_32)
    unreachable
label_index_ok_11:
    %.t_38 = getelementptr inbounds i64, ptr %.t_34, i64 %.t_30
    %.t_39 = load i64, ptr %.t_38
    store i64 %.t_39, ptr %.s_2
    br label %label_continue_6
label_continue_6:
    br label %label_loop_continue_4
label_loop_continue_4:
    %.t_40 = load i64, ptr %.s_3
    %.t_41 = add i64 %.t_40, 1
    store i64 %.t_41, ptr %.s_3
    br label %label_loop_header_2
label_loop_exit_5:
    %.t_42 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
    %.t_43 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 0) to i64))
    %.t_44 = getelementptr inbounds %Array, ptr %.t_42, i32 0, i32 0
    store i64 0, ptr %.t_44
    %.t_45 = getelementptr inbounds %Array, ptr %.t_42, i32 0, i32 1
    store i64 0, ptr %.t_45
    %.t_46 = getelementptr inbounds %Array, ptr %.t_42, i32 0, i32 2
    store ptr %.t_43, ptr %.t_46
    store ptr %.t_42, ptr %.s_4
    store i64 0, ptr %.s_3
    br label %label_loop_header_12
label_loop_header_12:
    %.t_47 = load i64, ptr %.s_3
    %.t_48 = load i64, ptr %.s_2
    %.t_49 = icmp sle i64 %.t_47, %.t_48
    br i1 %.t_49, label %label_loop_body_13, label %label_loop_exit_15
label_loop_body_13:
    %.t_50 = load ptr, ptr %.s_4
    %.t_51 = call ptr @matcha_array_append_slot(ptr %.t_50, i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
    store i64 0, ptr %.t_51
    br label %label_loop_continue_14
label_loop_continue_14:
    %.t_52 = load i64, ptr %.s_3
    %.t_53 = add i64 %.t_52, 1
    store i64 %.t_53, ptr %.s_3
    br label %label_loop_header_12
label_loop_exit_15:
    store i64 0, ptr %.s_3
    br label %label_loop_header_16
label_loop_header_16:
    %.t_54 = load i64, ptr %.s_3
    %.t_55 = load i64, ptr %.s_1
    %.t_56 = icmp slt i64 %.t_54, %.t_55
    br i1 %.t_56, label %label_loop_body_17, label %label_loop_exit_19
label_loop_body_17:
    %.t_57 = load ptr, ptr %.s_0
    %.t_58 = load i64, ptr %.s_3
    %.t_59 = getelementptr inbounds %Array, ptr %.t_57, i32 0, i32 0
    %.t_60 = load i64, ptr %.t_59
    %.t_61 = getelementptr inbounds %Array, ptr %.t_57, i32 0, i32 2
    %.t_62 = load ptr, ptr %.t_61
    %.t_63 = icmp slt i64 %.t_58, 0
    %.t_64 = icmp sge i64 %.t_58, %.t_60
    %.t_65 = or i1 %.t_63, %.t_64
    br i1 %.t_65, label %label_index_panic_20, label %label_index_ok_21
label_index_panic_20:
    call void @matcha_panic_index_out_of_bounds(i64 28, i64 26, i64 %.t_58, i64 %.t_60)
    unreachable
label_index_ok_21:
    %.t_66 = getelementptr inbounds i64, ptr %.t_62, i64 %.t_58
    %.t_67 = load i64, ptr %.t_66
    store i64 %.t_67, ptr %.s_5
    %.t_68 = load ptr, ptr %.s_4
    %.t_69 = load i64, ptr %.s_5
    %.t_70 = getelementptr inbounds %Array, ptr %.t_68, i32 0, i32 0
    %.t_71 = load i64, ptr %.t_70
    %.t_72 = getelementptr inbounds %Array, ptr %.t_68, i32 0, i32 2
    %.t_73 = load ptr, ptr %.t_72
    %.t_74 = icmp slt i64 %.t_69, 0
    %.t_75 = icmp sge i64 %.t_69, %.t_71
    %.t_76 = or i1 %.t_74, %.t_75
    br i1 %.t_76, label %label_index_panic_22, label %label_index_ok_23
label_index_panic_22:
    call void @matcha_panic_index_out_of_bounds(i64 29, i64 20, i64 %.t_69, i64 %.t_71)
    unreachable
label_index_ok_23:
    %.t_77 = getelementptr inbounds i64, ptr %.t_73, i64 %.t_69
    %.t_78 = load ptr, ptr %.s_4
    %.t_79 = load i64, ptr %.s_5
    %.t_80 = getelementptr inbounds %Array, ptr %.t_78, i32 0, i32 0
    %.t_81 = load i64, ptr %.t_80
    %.t_82 = getelementptr inbounds %Array, ptr %.t_78, i32 0, i32 2
    %.t_83 = load ptr, ptr %.t_82
    %.t_84 = icmp slt i64 %.t_79, 0
    %.t_85 = icmp sge i64 %.t_79, %.t_81
    %.t_86 = or i1 %.t_84, %.t_85
    br i1 %.t_86, label %label_index_panic_24, label %label_index_ok_25
label_index_panic_24:
    call void @matcha_panic_index_out_of_bounds(i64 29, i64 41, i64 %.t_79, i64 %.t_81)
    unreachable
label_index_ok_25:
    %.t_87 = getelementptr inbounds i64, ptr %.t_83, i64 %.t_79
    %.t_88 = load i64, ptr %.t_87
    %.t_89 = add i64 %.t_88, 1
    store i64 %.t_89, ptr %.t_77
    br label %label_loop_continue_18
label_loop_continue_18:
    %.t_90 = load i64, ptr %.s_3
    %.t_91 = add i64 %.t_90, 1
    store i64 %.t_91, ptr %.s_3
    br label %label_loop_header_16
label_loop_exit_19:
    store i64 1, ptr %.s_3
    br label %label_loop_header_26
label_loop_header_26:
    %.t_92 = load i64, ptr %.s_3
    %.t_93 = load i64, ptr %.s_2
    %.t_94 = icmp sle i64 %.t_92, %.t_93
    br i1 %.t_94, label %label_loop_body_27, label %label_loop_exit_29
label_loop_body_27:
    %.t_95 = load ptr, ptr %.s_4
    %.t_96 = load i64, ptr %.s_3
    %.t_97 = getelementptr inbounds %Array, ptr %.t_95, i32 0, i32 0
    %.t_98 = load i64, ptr %.t_97
    %.t_99 = getelementptr inbounds %Array, ptr %.t_95, i32 0, i32 2
    %.t_100 = load ptr, ptr %.t_99
    %.t_101 = icmp slt i64 %.t_96, 0
    %.t_102 = icmp sge i64 %.t_96, %.t_98
    %.t_103 = or i1 %.t_101, %.t_102
    br i1 %.t_103, label %label_index_panic_30, label %label_index_ok_31
label_index_panic_30:
    call void @matcha_panic_index_out_of_bounds(i64 35, i64 20, i64 %.t_96, i64 %.t_98)
    unreachable
label_index_ok_31:
    %.t_104 = getelementptr inbounds i64, ptr %.t_100, i64 %.t_96
    %.t_105 = load ptr, ptr %.s_4
    %.t_106 = load i64, ptr %.s_3
    %.t_107 = getelementptr inbounds %Array, ptr %.t_105, i32 0, i32 0
    %.t_108 = load i64, ptr %.t_107
    %.t_109 = getelementptr inbounds %Array, ptr %.t_105, i32 0, i32 2
    %.t_110 = load ptr, ptr %.t_109
    %.t_111 = icmp slt i64 %.t_106, 0
    %.t_112 = icmp sge i64 %.t_106, %.t_108
    %.t_113 = or i1 %.t_111, %.t_112
    br i1 %.t_113, label %label_index_panic_32, label %label_index_ok_33
label_index_panic_32:
    call void @matcha_panic_index_out_of_bounds(i64 35, i64 37, i64 %.t_106, i64 %.t_108)
    unreachable
label_index_ok_33:
    %.t_114 = getelementptr inbounds i64, ptr %.t_110, i64 %.t_106
    %.t_115 = load i64, ptr %.t_114
    %.t_116 = load ptr, ptr %.s_4
    %.t_117 = load i64, ptr %.s_3
    %.t_118 = sub i64 %.t_117, 1
    %.t_119 = getelementptr inbounds %Array, ptr %.t_116, i32 0, i32 0
    %.t_120 = load i64, ptr %.t_119
    %.t_121 = getelementptr inbounds %Array, ptr %.t_116, i32 0, i32 2
    %.t_122 = load ptr, ptr %.t_121
    %.t_123 = icmp slt i64 %.t_118, 0
    %.t_124 = icmp sge i64 %.t_118, %.t_120
    %.t_125 = or i1 %.t_123, %.t_124
    br i1 %.t_125, label %label_index_panic_34, label %label_index_ok_35
label_index_panic_34:
    call void @matcha_panic_index_out_of_bounds(i64 35, i64 54, i64 %.t_118, i64 %.t_120)
    unreachable
label_index_ok_35:
    %.t_126 = getelementptr inbounds i64, ptr %.t_122, i64 %.t_118
    %.t_127 = load i64, ptr %.t_126
    %.t_128 = add i64 %.t_115, %.t_127
    store i64 %.t_128, ptr %.t_104
    br label %label_loop_continue_28
label_loop_continue_28:
    %.t_129 = load i64, ptr %.s_3
    %.t_130 = add i64 %.t_129, 1
    store i64 %.t_130, ptr %.s_3
    br label %label_loop_header_26
label_loop_exit_29:
    %.t_131 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
    %.t_132 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 0) to i64))
    %.t_133 = getelementptr inbounds %Array, ptr %.t_131, i32 0, i32 0
    store i64 0, ptr %.t_133
    %.t_134 = getelementptr inbounds %Array, ptr %.t_131, i32 0, i32 1
    store i64 0, ptr %.t_134
    %.t_135 = getelementptr inbounds %Array, ptr %.t_131, i32 0, i32 2
    store ptr %.t_132, ptr %.t_135
    store ptr %.t_131, ptr %.s_6
    store i64 0, ptr %.s_3
    br label %label_loop_header_36
label_loop_header_36:
    %.t_136 = load i64, ptr %.s_3
    %.t_137 = load i64, ptr %.s_1
    %.t_138 = icmp slt i64 %.t_136, %.t_137
    br i1 %.t_138, label %label_loop_body_37, label %label_loop_exit_39
label_loop_body_37:
    %.t_139 = load ptr, ptr %.s_6
    %.t_140 = call ptr @matcha_array_append_slot(ptr %.t_139, i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
    store i64 0, ptr %.t_140
    br label %label_loop_continue_38
label_loop_continue_38:
    %.t_141 = load i64, ptr %.s_3
    %.t_142 = add i64 %.t_141, 1
    store i64 %.t_142, ptr %.s_3
    br label %label_loop_header_36
label_loop_exit_39:
    %.t_143 = load i64, ptr %.s_1
    %.t_144 = sub i64 %.t_143, 1
    store i64 %.t_144, ptr %.s_3
    br label %label_loop_header_40
label_loop_header_40:
    %.t_145 = load i64, ptr %.s_3
    %.t_146 = icmp sge i64 %.t_145, 0
    br i1 %.t_146, label %label_loop_body_41, label %label_loop_exit_43
label_loop_body_41:
    %.t_147 = load ptr, ptr %.s_6
    %.t_148 = load ptr, ptr %.s_4
    %.t_149 = load ptr, ptr %.s_0
    %.t_150 = load i64, ptr %.s_3
    %.t_151 = getelementptr inbounds %Array, ptr %.t_149, i32 0, i32 0
    %.t_152 = load i64, ptr %.t_151
    %.t_153 = getelementptr inbounds %Array, ptr %.t_149, i32 0, i32 2
    %.t_154 = load ptr, ptr %.t_153
    %.t_155 = icmp slt i64 %.t_150, 0
    %.t_156 = icmp sge i64 %.t_150, %.t_152
    %.t_157 = or i1 %.t_155, %.t_156
    br i1 %.t_157, label %label_index_panic_44, label %label_index_ok_45
label_index_panic_44:
    call void @matcha_panic_index_out_of_bounds(i64 47, i64 39, i64 %.t_150, i64 %.t_152)
    unreachable
label_index_ok_45:
    %.t_158 = getelementptr inbounds i64, ptr %.t_154, i64 %.t_150
    %.t_159 = load i64, ptr %.t_158
    %.t_160 = getelementptr inbounds %Array, ptr %.t_148, i32 0, i32 0
    %.t_161 = load i64, ptr %.t_160
    %.t_162 = getelementptr inbounds %Array, ptr %.t_148, i32 0, i32 2
    %.t_163 = load ptr, ptr %.t_162
    %.t_164 = icmp slt i64 %.t_159, 0
    %.t_165 = icmp sge i64 %.t_159, %.t_161
    %.t_166 = or i1 %.t_164, %.t_165
    br i1 %.t_166, label %label_index_panic_46, label %label_index_ok_47
label_index_panic_46:
    call void @matcha_panic_index_out_of_bounds(i64 47, i64 33, i64 %.t_159, i64 %.t_161)
    unreachable
label_index_ok_47:
    %.t_167 = getelementptr inbounds i64, ptr %.t_163, i64 %.t_159
    %.t_168 = load i64, ptr %.t_167
    %.t_169 = sub i64 %.t_168, 1
    %.t_170 = getelementptr inbounds %Array, ptr %.t_147, i32 0, i32 0
    %.t_171 = load i64, ptr %.t_170
    %.t_172 = getelementptr inbounds %Array, ptr %.t_147, i32 0, i32 2
    %.t_173 = load ptr, ptr %.t_172
    %.t_174 = icmp slt i64 %.t_169, 0
    %.t_175 = icmp sge i64 %.t_169, %.t_171
    %.t_176 = or i1 %.t_174, %.t_175
    br i1 %.t_176, label %label_index_panic_48, label %label_index_ok_49
label_index_panic_48:
    call void @matcha_panic_index_out_of_bounds(i64 47, i64 21, i64 %.t_169, i64 %.t_171)
    unreachable
label_index_ok_49:
    %.t_177 = getelementptr inbounds i64, ptr %.t_173, i64 %.t_169
    %.t_178 = load ptr, ptr %.s_0
    %.t_179 = load i64, ptr %.s_3
    %.t_180 = getelementptr inbounds %Array, ptr %.t_178, i32 0, i32 0
    %.t_181 = load i64, ptr %.t_180
    %.t_182 = getelementptr inbounds %Array, ptr %.t_178, i32 0, i32 2
    %.t_183 = load ptr, ptr %.t_182
    %.t_184 = icmp slt i64 %.t_179, 0
    %.t_185 = icmp sge i64 %.t_179, %.t_181
    %.t_186 = or i1 %.t_184, %.t_185
    br i1 %.t_186, label %label_index_panic_50, label %label_index_ok_51
label_index_panic_50:
    call void @matcha_panic_index_out_of_bounds(i64 47, i64 56, i64 %.t_179, i64 %.t_181)
    unreachable
label_index_ok_51:
    %.t_187 = getelementptr inbounds i64, ptr %.t_183, i64 %.t_179
    %.t_188 = load i64, ptr %.t_187
    store i64 %.t_188, ptr %.t_177
    %.t_189 = load ptr, ptr %.s_4
    %.t_190 = load ptr, ptr %.s_0
    %.t_191 = load i64, ptr %.s_3
    %.t_192 = getelementptr inbounds %Array, ptr %.t_190, i32 0, i32 0
    %.t_193 = load i64, ptr %.t_192
    %.t_194 = getelementptr inbounds %Array, ptr %.t_190, i32 0, i32 2
    %.t_195 = load ptr, ptr %.t_194
    %.t_196 = icmp slt i64 %.t_191, 0
    %.t_197 = icmp sge i64 %.t_191, %.t_193
    %.t_198 = or i1 %.t_196, %.t_197
    br i1 %.t_198, label %label_index_panic_52, label %label_index_ok_53
label_index_panic_52:
    call void @matcha_panic_index_out_of_bounds(i64 48, i64 26, i64 %.t_191, i64 %.t_193)
    unreachable
label_index_ok_53:
    %.t_199 = getelementptr inbounds i64, ptr %.t_195, i64 %.t_191
    %.t_200 = load i64, ptr %.t_199
    %.t_201 = getelementptr inbounds %Array, ptr %.t_189, i32 0, i32 0
    %.t_202 = load i64, ptr %.t_201
    %.t_203 = getelementptr inbounds %Array, ptr %.t_189, i32 0, i32 2
    %.t_204 = load ptr, ptr %.t_203
    %.t_205 = icmp slt i64 %.t_200, 0
    %.t_206 = icmp sge i64 %.t_200, %.t_202
    %.t_207 = or i1 %.t_205, %.t_206
    br i1 %.t_207, label %label_index_panic_54, label %label_index_ok_55
label_index_panic_54:
    call void @matcha_panic_index_out_of_bounds(i64 48, i64 20, i64 %.t_200, i64 %.t_202)
    unreachable
label_index_ok_55:
    %.t_208 = getelementptr inbounds i64, ptr %.t_204, i64 %.t_200
    %.t_209 = load ptr, ptr %.s_4
    %.t_210 = load ptr, ptr %.s_0
    %.t_211 = load i64, ptr %.s_3
    %.t_212 = getelementptr inbounds %Array, ptr %.t_210, i32 0, i32 0
    %.t_213 = load i64, ptr %.t_212
    %.t_214 = getelementptr inbounds %Array, ptr %.t_210, i32 0, i32 2
    %.t_215 = load ptr, ptr %.t_214
    %.t_216 = icmp slt i64 %.t_211, 0
    %.t_217 = icmp sge i64 %.t_211, %.t_213
    %.t_218 = or i1 %.t_216, %.t_217
    br i1 %.t_218, label %label_index_panic_56, label %label_index_ok_57
label_index_panic_56:
    call void @matcha_panic_index_out_of_bounds(i64 48, i64 50, i64 %.t_211, i64 %.t_213)
    unreachable
label_index_ok_57:
    %.t_219 = getelementptr inbounds i64, ptr %.t_215, i64 %.t_211
    %.t_220 = load i64, ptr %.t_219
    %.t_221 = getelementptr inbounds %Array, ptr %.t_209, i32 0, i32 0
    %.t_222 = load i64, ptr %.t_221
    %.t_223 = getelementptr inbounds %Array, ptr %.t_209, i32 0, i32 2
    %.t_224 = load ptr, ptr %.t_223
    %.t_225 = icmp slt i64 %.t_220, 0
    %.t_226 = icmp sge i64 %.t_220, %.t_222
    %.t_227 = or i1 %.t_225, %.t_226
    br i1 %.t_227, label %label_index_panic_58, label %label_index_ok_59
label_index_panic_58:
    call void @matcha_panic_index_out_of_bounds(i64 48, i64 44, i64 %.t_220, i64 %.t_222)
    unreachable
label_index_ok_59:
    %.t_228 = getelementptr inbounds i64, ptr %.t_224, i64 %.t_220
    %.t_229 = load i64, ptr %.t_228
    %.t_230 = sub i64 %.t_229, 1
    store i64 %.t_230, ptr %.t_208
    br label %label_loop_continue_42
label_loop_continue_42:
    %.t_231 = load i64, ptr %.s_3
    %.t_232 = sub i64 %.t_231, 1
    store i64 %.t_232, ptr %.s_3
    br label %label_loop_header_40
label_loop_exit_43:
    %.t_233 = load ptr, ptr %.s_6
    ret ptr %.t_233

}

define i32 @main() {
entry:
    %.s_0 = alloca %String
    %.s_1 = alloca %String
    %.s_2 = alloca ptr
    %.s_3 = alloca ptr
    %.s_4 = alloca ptr
    %.s_5 = alloca i64
    %.s_6 = alloca %String
    %.s_7 = alloca ptr
    %.s_8 = alloca %String
    %.s_9 = alloca %String
    %.s_10 = alloca ptr
    %.s_11 = alloca ptr
    %.s_12 = alloca i64

    %.t_0 = getelementptr inbounds [21 x i8], [21 x i8]* @.string_literal_0, i64 0, i64 0
    %.t_1 = insertvalue %String undef, i8* %.t_0, 0
    %.t_2 = insertvalue %String %.t_1, i64 21, 1
    %.t_3 = extractvalue %String %.t_2, 0
    %.t_4 = extractvalue %String %.t_2, 1
    call void @matcha_read_file(ptr %.s_0, ptr %.t_3, i64 %.t_4)
    %.t_5 = load %String, ptr %.s_0
    store %String %.t_5, ptr %.s_1
    %.t_6 = load %String, ptr %.s_1
    %.t_7 = getelementptr inbounds [1 x i8], [1 x i8]* @.string_literal_1, i64 0, i64 0
    %.t_8 = insertvalue %String undef, i8* %.t_7, 0
    %.t_9 = insertvalue %String %.t_8, i64 1, 1
    %.t_10 = extractvalue %String %.t_6, 0
    %.t_11 = extractvalue %String %.t_6, 1
    %.t_12 = extractvalue %String %.t_9, 0
    %.t_13 = extractvalue %String %.t_9, 1
    %.t_14 = call ptr @matcha_string_split(ptr %.t_10, i64 %.t_11, ptr %.t_12, i64 %.t_13)
    store ptr %.t_14, ptr %.s_2
    %.t_15 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
    %.t_16 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 0) to i64))
    %.t_17 = getelementptr inbounds %Array, ptr %.t_15, i32 0, i32 0
    store i64 0, ptr %.t_17
    %.t_18 = getelementptr inbounds %Array, ptr %.t_15, i32 0, i32 1
    store i64 0, ptr %.t_18
    %.t_19 = getelementptr inbounds %Array, ptr %.t_15, i32 0, i32 2
    store ptr %.t_16, ptr %.t_19
    store ptr %.t_15, ptr %.s_3
    %.t_20 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
    %.t_21 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 0) to i64))
    %.t_22 = getelementptr inbounds %Array, ptr %.t_20, i32 0, i32 0
    store i64 0, ptr %.t_22
    %.t_23 = getelementptr inbounds %Array, ptr %.t_20, i32 0, i32 1
    store i64 0, ptr %.t_23
    %.t_24 = getelementptr inbounds %Array, ptr %.t_20, i32 0, i32 2
    store ptr %.t_21, ptr %.t_24
    store ptr %.t_20, ptr %.s_4
    store i64 0, ptr %.s_5
    br label %label_loop_header_0
label_loop_header_0:
    %.t_25 = load i64, ptr %.s_5
    %.t_26 = load ptr, ptr %.s_2
    %.t_27 = getelementptr inbounds %Array, ptr %.t_26, i32 0, i32 0
    %.t_28 = load i64, ptr %.t_27
    %.t_29 = icmp slt i64 %.t_25, %.t_28
    br i1 %.t_29, label %label_loop_body_1, label %label_loop_exit_3
label_loop_body_1:
    %.t_30 = load ptr, ptr %.s_2
    %.t_31 = load i64, ptr %.s_5
    %.t_32 = getelementptr inbounds %Array, ptr %.t_30, i32 0, i32 0
    %.t_33 = load i64, ptr %.t_32
    %.t_34 = getelementptr inbounds %Array, ptr %.t_30, i32 0, i32 2
    %.t_35 = load ptr, ptr %.t_34
    %.t_36 = icmp slt i64 %.t_31, 0
    %.t_37 = icmp sge i64 %.t_31, %.t_33
    %.t_38 = or i1 %.t_36, %.t_37
    br i1 %.t_38, label %label_index_panic_4, label %label_index_ok_5
label_index_panic_4:
    call void @matcha_panic_index_out_of_bounds(i64 62, i64 19, i64 %.t_31, i64 %.t_33)
    unreachable
label_index_ok_5:
    %.t_39 = getelementptr inbounds %String, ptr %.t_35, i64 %.t_31
    %.t_40 = load %String, ptr %.t_39
    store %String %.t_40, ptr %.s_6
    %.t_41 = load %String, ptr %.s_6
    %.t_42 = getelementptr inbounds [2 x i8], [2 x i8]* @.string_literal_2, i64 0, i64 0
    %.t_43 = insertvalue %String undef, i8* %.t_42, 0
    %.t_44 = insertvalue %String %.t_43, i64 2, 1
    %.t_45 = extractvalue %String %.t_41, 0
    %.t_46 = extractvalue %String %.t_41, 1
    %.t_47 = extractvalue %String %.t_44, 0
    %.t_48 = extractvalue %String %.t_44, 1
    %.t_49 = call ptr @matcha_string_split(ptr %.t_45, i64 %.t_46, ptr %.t_47, i64 %.t_48)
    store ptr %.t_49, ptr %.s_7
    %.t_50 = load ptr, ptr %.s_3
    %.t_51 = load ptr, ptr %.s_7
    %.t_52 = getelementptr inbounds %Array, ptr %.t_51, i32 0, i32 0
    %.t_53 = load i64, ptr %.t_52
    %.t_54 = getelementptr inbounds %Array, ptr %.t_51, i32 0, i32 2
    %.t_55 = load ptr, ptr %.t_54
    %.t_56 = icmp slt i64 0, 0
    %.t_57 = icmp sge i64 0, %.t_53
    %.t_58 = or i1 %.t_56, %.t_57
    br i1 %.t_58, label %label_index_panic_6, label %label_index_ok_7
label_index_panic_6:
    call void @matcha_panic_index_out_of_bounds(i64 64, i64 30, i64 0, i64 %.t_53)
    unreachable
label_index_ok_7:
    %.t_59 = getelementptr inbounds %String, ptr %.t_55, i64 0
    %.t_60 = load %String, ptr %.t_59
    %.t_61 = extractvalue %String %.t_60, 0
    %.t_62 = extractvalue %String %.t_60, 1
    call void @matcha_string_trim(ptr %.s_8, ptr %.t_61, i64 %.t_62)
    %.t_63 = load %String, ptr %.s_8
    %.t_64 = extractvalue %String %.t_63, 0
    %.t_65 = extractvalue %String %.t_63, 1
    %.t_66 = call i64 @matcha_string_to_int(ptr %.t_64, i64 %.t_65)
    %.t_67 = call ptr @matcha_array_append_slot(ptr %.t_50, i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
    store i64 %.t_66, ptr %.t_67
    %.t_68 = load ptr, ptr %.s_4
    %.t_69 = load ptr, ptr %.s_7
    %.t_70 = getelementptr inbounds %Array, ptr %.t_69, i32 0, i32 0
    %.t_71 = load i64, ptr %.t_70
    %.t_72 = getelementptr inbounds %Array, ptr %.t_69, i32 0, i32 2
    %.t_73 = load ptr, ptr %.t_72
    %.t_74 = icmp slt i64 1, 0
    %.t_75 = icmp sge i64 1, %.t_71
    %.t_76 = or i1 %.t_74, %.t_75
    br i1 %.t_76, label %label_index_panic_8, label %label_index_ok_9
label_index_panic_8:
    call void @matcha_panic_index_out_of_bounds(i64 65, i64 31, i64 1, i64 %.t_71)
    unreachable
label_index_ok_9:
    %.t_77 = getelementptr inbounds %String, ptr %.t_73, i64 1
    %.t_78 = load %String, ptr %.t_77
    %.t_79 = extractvalue %String %.t_78, 0
    %.t_80 = extractvalue %String %.t_78, 1
    call void @matcha_string_trim(ptr %.s_9, ptr %.t_79, i64 %.t_80)
    %.t_81 = load %String, ptr %.s_9
    %.t_82 = extractvalue %String %.t_81, 0
    %.t_83 = extractvalue %String %.t_81, 1
    %.t_84 = call i64 @matcha_string_to_int(ptr %.t_82, i64 %.t_83)
    %.t_85 = call ptr @matcha_array_append_slot(ptr %.t_68, i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
    store i64 %.t_84, ptr %.t_85
    br label %label_loop_continue_2
label_loop_continue_2:
    %.t_86 = load i64, ptr %.s_5
    %.t_87 = add i64 %.t_86, 1
    store i64 %.t_87, ptr %.s_5
    br label %label_loop_header_0
label_loop_exit_3:
    %.t_88 = load ptr, ptr %.s_3
    %.t_89 = call ptr @matcha_function_1_countSort(ptr %.t_88)
    store ptr %.t_89, ptr %.s_10
    %.t_90 = load ptr, ptr %.s_4
    %.t_91 = call ptr @matcha_function_1_countSort(ptr %.t_90)
    store ptr %.t_91, ptr %.s_11
    store i64 0, ptr %.s_5
    store i64 0, ptr %.s_12
    br label %label_loop_header_10
label_loop_header_10:
    %.t_92 = load i64, ptr %.s_5
    %.t_93 = load ptr, ptr %.s_2
    %.t_94 = getelementptr inbounds %Array, ptr %.t_93, i32 0, i32 0
    %.t_95 = load i64, ptr %.t_94
    %.t_96 = icmp slt i64 %.t_92, %.t_95
    br i1 %.t_96, label %label_loop_body_11, label %label_loop_exit_13
label_loop_body_11:
    %.t_97 = load i64, ptr %.s_12
    %.t_98 = load ptr, ptr %.s_10
    %.t_99 = load i64, ptr %.s_5
    %.t_100 = getelementptr inbounds %Array, ptr %.t_98, i32 0, i32 0
    %.t_101 = load i64, ptr %.t_100
    %.t_102 = getelementptr inbounds %Array, ptr %.t_98, i32 0, i32 2
    %.t_103 = load ptr, ptr %.t_102
    %.t_104 = icmp slt i64 %.t_99, 0
    %.t_105 = icmp sge i64 %.t_99, %.t_101
    %.t_106 = or i1 %.t_104, %.t_105
    br i1 %.t_106, label %label_index_panic_14, label %label_index_ok_15
label_index_panic_14:
    call void @matcha_panic_index_out_of_bounds(i64 74, i64 53, i64 %.t_99, i64 %.t_101)
    unreachable
label_index_ok_15:
    %.t_107 = getelementptr inbounds i64, ptr %.t_103, i64 %.t_99
    %.t_108 = load i64, ptr %.t_107
    %.t_109 = load ptr, ptr %.s_11
    %.t_110 = load i64, ptr %.s_5
    %.t_111 = getelementptr inbounds %Array, ptr %.t_109, i32 0, i32 0
    %.t_112 = load i64, ptr %.t_111
    %.t_113 = getelementptr inbounds %Array, ptr %.t_109, i32 0, i32 2
    %.t_114 = load ptr, ptr %.t_113
    %.t_115 = icmp slt i64 %.t_110, 0
    %.t_116 = icmp sge i64 %.t_110, %.t_112
    %.t_117 = or i1 %.t_115, %.t_116
    br i1 %.t_117, label %label_index_panic_16, label %label_index_ok_17
label_index_panic_16:
    call void @matcha_panic_index_out_of_bounds(i64 74, i64 85, i64 %.t_110, i64 %.t_112)
    unreachable
label_index_ok_17:
    %.t_118 = getelementptr inbounds i64, ptr %.t_114, i64 %.t_110
    %.t_119 = load i64, ptr %.t_118
    %.t_120 = sub i64 %.t_108, %.t_119
    %.t_121 = call i64 @matcha_function_0_absolute(i64 %.t_120)
    %.t_122 = add i64 %.t_97, %.t_121
    store i64 %.t_122, ptr %.s_12
    br label %label_loop_continue_12
label_loop_continue_12:
    %.t_123 = load i64, ptr %.s_5
    %.t_124 = add i64 %.t_123, 1
    store i64 %.t_124, ptr %.s_5
    br label %label_loop_header_10
label_loop_exit_13:
    %.t_125 = load i64, ptr %.s_12
    call void @matcha_print_int(i64 %.t_125)
    ret i32 0

}
