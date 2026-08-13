const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const runtime_call_emitter_module = @import("runtime_call_emitter.zig");
const function_ir_builder_module = @import("function_ir_builder.zig");
const function_symbol_generator_module = @import("function_symbol_generator.zig");
const symbol_generator_module = @import("symbol_generator.zig");
const string_literal_pool_module = @import("string_literal_pool.zig");
const string_literal_emitter_module = @import("string_literal_emitter.zig");

const control_flow = @import("control_flow.zig");
const values = @import("values.zig");
const calls = @import("calls.zig");
const places = @import("places.zig");
const aggregates = @import("aggregates.zig");

const Register = function_symbol_generator_module.Register;
const Storage = function_symbol_generator_module.Storage;
const FunctionIrBuilder = function_ir_builder_module.FunctionIrBuilder;
const FunctionSymbolGenerator = function_symbol_generator_module.FunctionSymbolGenerator;
const RuntimeCallEmitter = runtime_call_emitter_module.RuntimeCallEmitter;
const RuntimeStringParts = runtime_call_emitter_module.RuntimeStringParts;
const SymbolGenerator = symbol_generator_module.SymbolGenerator;
const StringLiteralPool = string_literal_pool_module.StringLiteralPool;
const StringLiteralEmitter = string_literal_emitter_module.StringLiteralEmitter;
const StorageBySymbolId = std.AutoHashMap(symbols.SymbolId, Storage);

pub const LoopContext = struct {
    continue_label: function_symbol_generator_module.Label,
    leave_label: function_symbol_generator_module.Label,
};

pub const Environment = struct {
    storage_by_symbol_id: StorageBySymbolId,
    loop_context: ?LoopContext,
    function_return_type_id: typing.TypeId,

    pub fn init(
        allocator: std.mem.Allocator,
        loop_context: ?LoopContext,
        function_return_type_id: typing.TypeId,
    ) @This() {
        return .{
            .storage_by_symbol_id = StorageBySymbolId.init(allocator),
            .loop_context = loop_context,
            .function_return_type_id = function_return_type_id,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.storage_by_symbol_id.deinit();
    }
};

/// Emit functions return the register holding the node's value, or null when
/// the node produces no value. Reachability is not threaded through calls:
/// it lives in the FunctionIrBuilder cursor (see its doc comment).
pub const NodeEmitter = struct {
    allocator: std.mem.Allocator,
    function_symbol_generator: *FunctionSymbolGenerator,
    function_ir_builder: *FunctionIrBuilder,
    symbol_generator: *SymbolGenerator,
    runtime_call_emitter: *const RuntimeCallEmitter,
    string_literal_pool: *StringLiteralPool,
    string_literal_emitter: *StringLiteralEmitter,

    pub fn init(
        allocator: std.mem.Allocator,
        function_symbol_generator: *FunctionSymbolGenerator,
        function_ir_builder: *FunctionIrBuilder,
        symbol_generator: *SymbolGenerator,
        runtime_call_emitter: *const RuntimeCallEmitter,
        string_literal_pool: *StringLiteralPool,
        string_literal_emitter: *StringLiteralEmitter,
    ) @This() {
        return .{
            .allocator = allocator,
            .function_symbol_generator = function_symbol_generator,
            .function_ir_builder = function_ir_builder,
            .symbol_generator = symbol_generator,
            .runtime_call_emitter = runtime_call_emitter,
            .string_literal_pool = string_literal_pool,
            .string_literal_emitter = string_literal_emitter,
        };
    }

    pub fn deinit(self: *const @This()) void {
        _ = self;
    }

    pub fn emitStringParts(self: *@This(), string_register: Register) RuntimeStringParts {
        const pointer_register = self.function_symbol_generator.generateRegister();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String {s}, 0",
            .{ pointer_register, string_register },
        ) catch unreachable;
        self.function_ir_builder.emitInstruction(pointer_instruction);

        const length_register = self.function_symbol_generator.generateRegister();
        const length_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String {s}, 1",
            .{ length_register, string_register },
        ) catch unreachable;
        self.function_ir_builder.emitInstruction(length_instruction);

        return .{
            .pointer_register = pointer_register,
            .length_register = length_register,
        };
    }

    pub fn emitNode(
        self: *@This(),
        node: *const ast.Node,
        lowered_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) ?Register {
        switch (node.kind) {
            .Return => |return_statement| return control_flow.emitReturn(
                self,
                &return_statement,
                lowered_program,
                environment,
            ),
            .IntegerLiteral => |token| return std.fmt.allocPrint(
                self.allocator,
                "{d}",
                .{token.kind.IntLiteral},
            ) catch unreachable,
            .BooleanLiteral => |token| return if (token.kind.BooleanLiteral) "1" else "0",
            .StringLiteral => |token| return self.string_literal_emitter.emitStringLiteralValue(
                self.string_literal_pool,
                node.id,
                token.kind.StringLiteral,
                self.function_symbol_generator,
                self.function_ir_builder,
            ),
            .UnitLiteral => unreachable,
            .Identifier => return values.emitIdentifier(self, node, lowered_program, environment),
            .Loop => |loop| return control_flow.emitLoop(self, &loop, lowered_program, environment),
            .While => |while_statement| return control_flow.emitWhile(
                self,
                &while_statement,
                lowered_program,
                environment,
            ),
            .ForIn => |for_in| return control_flow.emitForInArrayLoop(
                self,
                node,
                &for_in,
                lowered_program,
                environment,
            ),
            .Leave => {
                self.function_ir_builder.emitBranchInstruction(null, &.{environment.loop_context.?.leave_label});
                return null;
            },
            .Continue => {
                self.function_ir_builder.emitBranchInstruction(null, &.{environment.loop_context.?.continue_label});
                return null;
            },
            .CallExpression => |call_expression| return calls.emitCallExpression(
                self,
                node,
                &call_expression,
                lowered_program,
                environment,
            ),
            .MemberAccess => |member_access| return aggregates.emitMemberAccess(
                self,
                node,
                &member_access,
                lowered_program,
                environment,
            ),
            .BinaryExpression => |binary_expression| return values.emitBinaryExpression(
                self,
                node,
                &binary_expression,
                lowered_program,
                environment,
            ),
            .UnaryExpression => |unary_expression| return values.emitUnaryExpression(
                self,
                node,
                &unary_expression,
                lowered_program,
                environment,
            ),
            .Declaration => |value_declaration| return places.emitDeclaration(
                self,
                node,
                &value_declaration,
                lowered_program,
                environment,
            ),
            .Assignment => |assignment| return places.emitAssignment(
                self,
                node,
                &assignment,
                lowered_program,
                environment,
            ),
            .Block => |block| return control_flow.emitBlock(self, block, lowered_program, environment),
            .IfStatement => |if_statement| return control_flow.emitIfStatement(
                self,
                node,
                &if_statement,
                lowered_program,
                environment,
            ),
            .IfExpression => |if_expression| return control_flow.emitIfExpression(
                self,
                node,
                &if_expression,
                lowered_program,
                environment,
            ),
            .MatchExpression => |match_expression| return control_flow.emitMatchExpression(
                self,
                node,
                &match_expression,
                lowered_program,
                environment,
            ),
            .ExpressionStatement => |expression_statement| {
                _ = self.emitNode(expression_statement.expression, lowered_program, environment);
                return null;
            },
            .ItemDefinition => return null,
            .StructureConstruction => |structure_construction| return aggregates.emitStructureConstruction(
                self,
                node,
                structure_construction.fields,
                lowered_program,
                environment,
            ),
            .AnonymousStructureLiteral => |anonymous_structure_literal| return aggregates.emitStructureConstruction(
                self,
                node,
                anonymous_structure_literal.fields,
                lowered_program,
                environment,
            ),
            .ArrayLiteral => |array_literal| return aggregates.emitArrayLiteral(
                self,
                node,
                &array_literal,
                lowered_program,
                environment,
            ),
            .IndexAccess => |index_access| return aggregates.emitIndexAccess(
                self,
                node,
                &index_access,
                lowered_program,
                environment,
            ),
        }
    }
};
