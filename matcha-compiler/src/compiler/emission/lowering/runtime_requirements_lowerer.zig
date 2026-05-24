const semantic_analysis = @import("semantic_analysis");
const lowering_types = @import("lowering_types.zig");

pub const RuntimeRequirementsLowerer = struct {
    pub fn init() @This() {
        return .{};
    }

    pub fn lower(self: *const @This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.RuntimeRequirementsPlan {
        _ = self;

        var plan: lowering_types.RuntimeRequirementsPlan = .{};
        for (analyzed_program.resolved_program.program.statements) |*statement| {
            analyzeNode(statement, analyzed_program, &plan);
        }

        return plan;
    }

    fn analyzeNode(
        node: anytype,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        plan: *lowering_types.RuntimeRequirementsPlan,
    ) void {
        switch (node.kind) {
            .Declaration => |declaration| analyzeNode(declaration.value, analyzed_program, plan),
            .ItemDefinition => |item_definition| analyzeItemDefinition(item_definition, analyzed_program, plan),
            .Return => |return_statement| {
                if (return_statement.value) |value| {
                    analyzeNode(value, analyzed_program, plan);
                }
            },
            .IfStatement => |if_statement| {
                analyzeNode(if_statement.condition, analyzed_program, plan);
                analyzeNode(if_statement.then_branch, analyzed_program, plan);
            },
            .ExpressionStatement => |expression_statement| analyzeNode(expression_statement.expression, analyzed_program, plan),
            .Assignment => |assignment| {
                analyzeNode(assignment.target, analyzed_program, plan);
                analyzeNode(assignment.value, analyzed_program, plan);
            },
            .Loop => |loop| analyzeNode(loop.body_block, analyzed_program, plan),
            .Leave, .Continue, .Identifier, .IntegerLiteral, .BooleanLiteral, .StringLiteral, .UnitLiteral => {},
            .While => |while_statement| {
                analyzeNode(while_statement.condition, analyzed_program, plan);
                if (while_statement.update) |update| {
                    analyzeNode(update, analyzed_program, plan);
                }
                analyzeNode(while_statement.body_block, analyzed_program, plan);
            },
            .ForIn => |for_in| {
                analyzeNode(for_in.iterable, analyzed_program, plan);
                analyzeNode(for_in.body_block, analyzed_program, plan);
            },
            .IfExpression => |if_expression| {
                analyzeNode(if_expression.condition, analyzed_program, plan);
                analyzeNode(if_expression.then_block, analyzed_program, plan);
                analyzeNode(if_expression.else_block, analyzed_program, plan);
            },
            .MatchExpression => |match_expression| {
                if (match_expression.subject) |subject| {
                    analyzeNode(subject, analyzed_program, plan);
                    const subject_type_id = analyzed_program.type_by_node_id.get(subject.id) orelse unreachable;
                    if (subject_type_id == analyzed_program.type_store.string_type_id and match_expression.arms.len > 0) {
                        plan.string_compare = true;
                    }
                }
                for (match_expression.arms) |arm| {
                    analyzeNode(arm.pattern_or_condition, analyzed_program, plan);
                    analyzeNode(arm.body, analyzed_program, plan);
                }
                if (match_expression.else_arm) |else_arm| {
                    analyzeNode(else_arm, analyzed_program, plan);
                }
            },
            .CallExpression => |call_expression| analyzeCallExpression(node, &call_expression, analyzed_program, plan),
            .MemberAccess => |member_access| analyzeNode(member_access.base, analyzed_program, plan),
            .BinaryExpression => |binary_expression| analyzeBinaryExpression(&binary_expression, analyzed_program, plan),
            .UnaryExpression => |unary_expression| analyzeNode(unary_expression.operand, analyzed_program, plan),
            .Block => |block| {
                for (block.statements) |*statement| {
                    analyzeNode(statement, analyzed_program, plan);
                }
                if (block.result) |result| {
                    analyzeNode(result, analyzed_program, plan);
                }
            },
            .StructureConstruction => |structure_construction| analyzeStructureConstructionFields(structure_construction.fields, analyzed_program, plan),
            .AnonymousStructureLiteral => |anonymous_structure_literal| analyzeStructureConstructionFields(anonymous_structure_literal.fields, analyzed_program, plan),
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    analyzeNode(element, analyzed_program, plan);
                }
            },
            .IndexAccess => |index_access| {
                plan.panic_index_out_of_bounds = true;
                analyzeNode(index_access.base, analyzed_program, plan);
                analyzeNode(index_access.index, analyzed_program, plan);
            },
        }
    }

    fn analyzeItemDefinition(
        item_definition: anytype,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        plan: *lowering_types.RuntimeRequirementsPlan,
    ) void {
        switch (item_definition.item) {
            .Function => |function_definition| {
                analyzeNode(function_definition.body_expression, analyzed_program, plan);
            },
            .Structure => |structure_definition| {
                for (structure_definition.function_definitions) |*function_definition_node| {
                    analyzeNode(function_definition_node, analyzed_program, plan);
                }
            },
        }
    }

    fn analyzeStructureConstructionFields(
        fields: anytype,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        plan: *lowering_types.RuntimeRequirementsPlan,
    ) void {
        for (fields) |field| {
            analyzeNode(field.value, analyzed_program, plan);
        }
    }

    fn analyzeCallExpression(
        node: anytype,
        call_expression: anytype,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        plan: *lowering_types.RuntimeRequirementsPlan,
    ) void {
        analyzeNode(call_expression.callee, analyzed_program, plan);
        for (call_expression.arguments) |*argument| {
            analyzeNode(argument, analyzed_program, plan);
        }

        switch (call_expression.callee.kind) {
            .MemberAccess => {
                const member_access = analyzed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable;
                switch (member_access) {
                    .ArrayInstanceMethodAccess => |array_method| switch (array_method) {
                        .Append => plan.array_append_slot = true,
                    },
                    .StringInstanceMethodAccess => |string_method| switch (string_method) {
                        .Trim => plan.string_trim = true,
                        .Split => plan.string_split = true,
                        .ToInt => plan.string_to_int = true,
                    },
                    .IntegerInstanceMethodAccess => |integer_method| switch (integer_method) {
                        .ToString => plan.int_to_string = true,
                    },
                    else => {},
                }
                return;
            },
            else => {},
        }

        const callee_symbol_id = analyzed_program.resolved_program.symbol_id_by_node_id.get(call_expression.callee.id) orelse return;
        const callee_symbol = analyzed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
        const function_info = switch (callee_symbol.kind) {
            .Function => |function_info| function_info,
            else => return,
        };

        _ = node;
        switch (function_info.implementation) {
            .BuiltinPrintInt => plan.print_int = true,
            .BuiltinPrintString => plan.print_string = true,
            .BuiltinReadFile => plan.read_file = true,
            .BuiltinReadLine => plan.read_line = true,
            .BuiltinGetArguments => plan.get_arguments = true,
            .UserDefined => {},
        }
    }

    fn analyzeBinaryExpression(
        binary_expression: anytype,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        plan: *lowering_types.RuntimeRequirementsPlan,
    ) void {
        analyzeNode(binary_expression.left, analyzed_program, plan);
        analyzeNode(binary_expression.right, analyzed_program, plan);

        const left_operand_type_id = analyzed_program.type_by_node_id.get(binary_expression.left.id) orelse return;
        if (left_operand_type_id != analyzed_program.type_store.string_type_id) {
            return;
        }

        switch (binary_expression.operator) {
            .Add => plan.string_concatenate = true,
            .Equal, .NotEqual => plan.string_compare = true,
            else => {},
        }
    }
};
