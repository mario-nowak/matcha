const std = @import("std");
const expect = @import("testing").expect;
const setupRuntimeRepresentationAnalyzerFixture = @import("testing").setupRuntimeRepresentationAnalyzerFixture;

pub const RuntimeRepresentationAnalyzer = struct {
    pub const analyzeRuntimeRepresentations = struct {
        test "gives unit no runtime representation" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, "");
            const type_store = fixture.type_check_result.type_store;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_type_id.get(type_store.unit_type_id).?).toMatch(.None);
        }

        test "gives scalar types a runtime representation" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, "");
            const type_store = fixture.type_check_result.type_store;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_type_id.get(type_store.boolean_type_id).?).toMatch(.Present);
            try expect(result.runtime_representation_by_type_id.get(type_store.integer_type_id).?).toMatch(.Present);
            try expect(result.runtime_representation_by_type_id.get(type_store.string_type_id).?).toMatch(.Present);
        }

        test "gives a structure a runtime representation when all its fields are unit" {
            const source =
                \\item Empty = structure { value: unit; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, source);
            const structure_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id).?;
            const structure_type_id = fixture.type_check_result.type_id_by_symbol_id.get(structure_symbol_id).?;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_type_id.get(structure_type_id).?).toMatch(.Present);
        }

        test "gives a self-recursive structure a runtime representation" {
            const source =
                \\item Chain = structure { value: unit; next: Chain; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, source);
            const structure_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id).?;
            const structure_type_id = fixture.type_check_result.type_id_by_symbol_id.get(structure_symbol_id).?;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_type_id.get(structure_type_id).?).toMatch(.Present);
        }

        test "gives an array of unit elements a runtime representation" {
            const source =
                \\val values = [unit];
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, source);
            const array_node = fixture.resolved_program.program.statements[0].kind.BindingDeclaration.value;
            const array_type_id = fixture.type_check_result.type_id_by_node_id.get(array_node.id).?;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_type_id.get(array_type_id).?).toMatch(.Present);
        }

        test "gives a union a runtime representation when all its cases are unit" {
            const source =
                \\item Direction = union { Left, Right };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, source);
            const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id).?;
            const union_type_id = fixture.type_check_result.type_id_by_symbol_id.get(union_symbol_id).?;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_type_id.get(union_type_id).?).toMatch(.Present);
        }

        test "takes the runtime representation of the node's type" {
            const source =
                \\val nothing = unit;
                \\val number = 1;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, source);
            const statements = fixture.resolved_program.program.statements;
            const unit_node = statements[0].kind.BindingDeclaration.value;
            const integer_node = statements[1].kind.BindingDeclaration.value;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_node_id.get(unit_node.id).?).toMatch(.None);
            try expect(result.runtime_representation_by_node_id.get(integer_node.id).?).toMatch(.Present);
        }

        test "records a runtime representation for an implicit member expression" {
            const source =
                \\item Result = union { None, Some: int };
                \\val result: Result = .None;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRepresentationAnalyzerFixture(&arena, source);
            const implicit_member_node = fixture.resolved_program.program.statements[1].kind.BindingDeclaration.value;

            const result = try fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(&fixture.type_check_result);

            try expect(result.runtime_representation_by_node_id.get(implicit_member_node.id).?).toMatch(.Present);
        }
    };
};
