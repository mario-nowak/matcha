const std = @import("std");
const expect = @import("testing").expect;
const setupLlvmIrCodeGeneratorFixture = @import("testing").setupLlvmIrCodeGeneratorFixture;

pub const LlvmIrCodeGenerator = struct {
    pub const generateLlvmIr = struct {
        pub const structures = struct {
            test "lowers a structure passed to a function and printed" {
                const source =
                    \\item Point = structure { x: int; y: int; };
                    \\item sum(point: Point): int = point.x + point.y;
                    \\printInt(sum(Point { x = 1, y = 2 }));
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.builtin.function.printInt(i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\%matcha.structure.Point = type { i64, i64 }
                    \\
                    \\define i64 @matcha.function.sum(ptr %parameter.point) {
                    \\entry:
                    \\    %address.binding.point.0 = alloca ptr
                    \\    store ptr %parameter.point, ptr %address.binding.point.0
                    \\    %value.0 = load ptr, ptr %address.binding.point.0
                    \\    %value.1 = getelementptr inbounds %matcha.structure.Point, ptr %value.0, i32 0, i32 0
                    \\    %value.2 = load i64, ptr %value.1
                    \\    %value.3 = load ptr, ptr %address.binding.point.0
                    \\    %value.4 = getelementptr inbounds %matcha.structure.Point, ptr %value.3, i32 0, i32 1
                    \\    %value.5 = load i64, ptr %value.4
                    \\    %value.6 = add i64 %value.2, %value.5
                    \\    ret i64 %value.6
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.structure.Point, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.structure.Point, ptr %value.0, i32 0, i32 0
                    \\    store i64 1, ptr %value.1
                    \\    %value.2 = getelementptr inbounds %matcha.structure.Point, ptr %value.0, i32 0, i32 1
                    \\    store i64 2, ptr %value.2
                    \\    %value.3 = call i64 @matcha.function.sum(ptr %value.0)
                    \\    call void @matcha.compiler_module.builtin.function.printInt(i64 %value.3)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "allocates nothing when a field value returns early" {
                const source =
                    \\item Wrapper = structure {
                    \\    value: unit;
                    \\};
                    \\item make(): int = {
                    \\    val wrapper = Wrapper { value = {
                    \\        return 1;
                    \\    } };
                    \\    return 2;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i64 @matcha.function.make() {
                    \\entry:
                    \\    %address.binding.wrapper.0 = alloca ptr
                    \\    ret i64 1
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const unions = struct {
            test "renders a union method definition and calls it with the receiver" {
                const source =
                    \\item Result = union {
                    \\    None,
                    \\    Some: int,
                    \\    item valueOr(self: Result, fallback: int): int = match self {
                    \\        .None => fallback,
                    \\        .Some(value) => value,
                    \\    };
                    \\};
                    \\val value = Result.Some(4).valueOr(0);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\%matcha.union.Result.case.None = type { i32 }
                    \\%matcha.union.Result.case.Some = type { i32, i64 }
                    \\
                    \\define i64 @matcha.union.Result.function.valueOr(ptr %parameter.self, i64 %parameter.fallback) {
                    \\entry:
                    \\    %address.binding.self.0 = alloca ptr
                    \\    %address.binding.fallback.0 = alloca i64
                    \\    %address.binding.value.0 = alloca i64
                    \\    store ptr %parameter.self, ptr %address.binding.self.0
                    \\    store i64 %parameter.fallback, ptr %address.binding.fallback.0
                    \\    %value.0 = load ptr, ptr %address.binding.self.0
                    \\    %value.1 = load i32, ptr %value.0
                    \\    %value.2 = icmp eq i32 %value.1, 0
                    \\    br i1 %value.2, label %match.0.arm.0, label %match.0.arm.1.condition
                    \\match.0.arm.0:
                    \\    %value.3 = load i64, ptr %address.binding.fallback.0
                    \\    br label %match.0.end
                    \\match.0.arm.1.condition:
                    \\    br label %match.0.arm.1
                    \\match.0.arm.1:
                    \\    %value.4 = getelementptr inbounds %matcha.union.Result.case.Some, ptr %value.0, i32 0, i32 1
                    \\    %value.5 = load i64, ptr %value.4
                    \\    store i64 %value.5, ptr %address.binding.value.0
                    \\    %value.6 = load i64, ptr %address.binding.value.0
                    \\    br label %match.0.end
                    \\match.0.end:
                    \\    %value.7 = phi i64 [%value.3, %match.0.arm.0], [%value.6, %match.0.arm.1]
                    \\    ret i64 %value.7
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.value.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Result.case.Some, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.union.Result.case.Some, ptr %value.0, i32 0, i32 0
                    \\    store i32 1, ptr %value.1
                    \\    %value.2 = getelementptr inbounds %matcha.union.Result.case.Some, ptr %value.0, i32 0, i32 1
                    \\    store i64 4, ptr %value.2
                    \\    %value.3 = call i64 @matcha.union.Result.function.valueOr(ptr %value.0, i64 0)
                    \\    store i64 %value.3, ptr %address.binding.value.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers a case construction to an allocation with a case index store and a payload store" {
                const source =
                    \\item Offset = union { Horizontal: int, Vertical: int };
                    \\val offset = Offset.Vertical(-3);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\%matcha.union.Offset.case.Horizontal = type { i32, i64 }
                    \\%matcha.union.Offset.case.Vertical = type { i32, i64 }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.offset.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = sub i64 0, 3
                    \\    %value.1 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Offset.case.Vertical, ptr null, i64 1) to i64))
                    \\    %value.2 = getelementptr inbounds %matcha.union.Offset.case.Vertical, ptr %value.1, i32 0, i32 0
                    \\    store i32 1, ptr %value.2
                    \\    %value.3 = getelementptr inbounds %matcha.union.Offset.case.Vertical, ptr %value.1, i32 0, i32 1
                    \\    store i64 %value.0, ptr %value.3
                    \\    store ptr %value.1, ptr %address.binding.offset.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "stores only the case index when constructing a case with a unit payload" {
                const source =
                    \\item Signal = union { Off, On: unit };
                    \\val signal = Signal.On(unit);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\%matcha.union.Signal.case.Off = type { i32 }
                    \\%matcha.union.Signal.case.On = type { i32 }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.signal.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Signal.case.On, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.union.Signal.case.On, ptr %value.0, i32 0, i32 0
                    \\    store i32 1, ptr %value.1
                    \\    store ptr %value.0, ptr %address.binding.signal.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "allocates nothing when the payload returns early" {
                const source =
                    \\item Signal = union { Off, On: unit };
                    \\item make(): Signal = {
                    \\    val signal = Signal.On({
                    \\        return Signal.Off;
                    \\    });
                    \\    return signal;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\%matcha.union.Signal.case.Off = type { i32 }
                    \\%matcha.union.Signal.case.On = type { i32 }
                    \\
                    \\define ptr @matcha.function.make() {
                    \\entry:
                    \\    %address.binding.signal.0 = alloca ptr
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Signal.case.Off, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.union.Signal.case.Off, ptr %value.0, i32 0, i32 0
                    \\    store i32 0, ptr %value.1
                    \\    ret ptr %value.0
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const control_flow = struct {
            test "lowers an if expression with values to branches and a phi" {
                const source =
                    \\val flag = true;
                    \\val score = if flag { 2 } else { 1 };
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.flag.0 = alloca i1
                    \\    %address.binding.score.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    store i1 1, ptr %address.binding.flag.0
                    \\    %value.0 = load i1, ptr %address.binding.flag.0
                    \\    br i1 %value.0, label %if.0.then, label %if.0.else
                    \\if.0.then:
                    \\    br label %if.0.end
                    \\if.0.else:
                    \\    br label %if.0.end
                    \\if.0.end:
                    \\    %value.1 = phi i64 [2, %if.0.then], [1, %if.0.else]
                    \\    store i64 %value.1, ptr %address.binding.score.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers an if expression without a value to branches without a phi" {
                const source =
                    \\if true { val left = 1; } else { val right = 2; };
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.left.0 = alloca i64
                    \\    %address.binding.right.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    br i1 1, label %if.0.then, label %if.0.else
                    \\if.0.then:
                    \\    store i64 1, ptr %address.binding.left.0
                    \\    br label %if.0.end
                    \\if.0.else:
                    \\    store i64 2, ptr %address.binding.right.0
                    \\    br label %if.0.end
                    \\if.0.end:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "branches to the continue block when a statement if has no else" {
                const source =
                    \\if true { val value = 1; }
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.value.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    br i1 1, label %if.0.then, label %if.0.end
                    \\if.0.then:
                    \\    store i64 1, ptr %address.binding.value.0
                    \\    br label %if.0.end
                    \\if.0.end:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "routes continue in a while loop through the update clause" {
                const source =
                    \\var index = 0;
                    \\while index < 5 : index = index + 1 {
                    \\    continue;
                    \\}
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.index.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    store i64 0, ptr %address.binding.index.0
                    \\    br label %while.0.header
                    \\while.0.header:
                    \\    %value.0 = load i64, ptr %address.binding.index.0
                    \\    %value.1 = icmp slt i64 %value.0, 5
                    \\    br i1 %value.1, label %while.0.body, label %while.0.exit
                    \\while.0.body:
                    \\    br label %while.0.continue
                    \\while.0.continue:
                    \\    %value.2 = load i64, ptr %address.binding.index.0
                    \\    %value.3 = add i64 %value.2, 1
                    \\    store i64 %value.3, ptr %address.binding.index.0
                    \\    br label %while.0.header
                    \\while.0.exit:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers and to a branch around the right operand and a phi" {
                const source =
                    \\val left = false;
                    \\val both = left and true;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.left.0 = alloca i1
                    \\    %address.binding.both.0 = alloca i1
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    store i1 0, ptr %address.binding.left.0
                    \\    %value.0 = load i1, ptr %address.binding.left.0
                    \\    br i1 %value.0, label %and.0.right, label %and.0.end
                    \\and.0.right:
                    \\    br label %and.0.end
                    \\and.0.end:
                    \\    %value.1 = phi i1 [0, %entry], [1, %and.0.right]
                    \\    store i1 %value.1, ptr %address.binding.both.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers or to a branch around the right operand and a phi" {
                const source =
                    \\val left = true;
                    \\val either = left or false;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.left.0 = alloca i1
                    \\    %address.binding.either.0 = alloca i1
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    store i1 1, ptr %address.binding.left.0
                    \\    %value.0 = load i1, ptr %address.binding.left.0
                    \\    br i1 %value.0, label %or.0.end, label %or.0.right
                    \\or.0.right:
                    \\    br label %or.0.end
                    \\or.0.end:
                    \\    %value.1 = phi i1 [1, %entry], [0, %or.0.right]
                    \\    store i1 %value.1, ptr %address.binding.either.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers boolean operators and comparisons" {
                const source =
                    \\val negated = not false;
                    \\val greater = 2 >= 1;
                    \\val same = true == false;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.negated.0 = alloca i1
                    \\    %address.binding.greater.0 = alloca i1
                    \\    %address.binding.same.0 = alloca i1
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = xor i1 0, 1
                    \\    store i1 %value.0, ptr %address.binding.negated.0
                    \\    %value.1 = icmp sge i64 2, 1
                    \\    store i1 %value.1, ptr %address.binding.greater.0
                    \\    %value.2 = icmp eq i1 1, 0
                    \\    store i1 %value.2, ptr %address.binding.same.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const integer_division = struct {
            test "checks the divisor and the overflow case before dividing" {
                const source =
                    \\val dividend = 10;
                    \\val divisor = 2;
                    \\val quotient = dividend / divisor;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.runtime.function.panicDivisionByZero(i64, i64) noreturn
                    \\declare void @matcha.compiler_module.runtime.function.panicDivisionOverflow(i64, i64) noreturn
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.dividend.0 = alloca i64
                    \\    %address.binding.divisor.0 = alloca i64
                    \\    %address.binding.quotient.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    store i64 10, ptr %address.binding.dividend.0
                    \\    store i64 2, ptr %address.binding.divisor.0
                    \\    %value.0 = load i64, ptr %address.binding.dividend.0
                    \\    %value.1 = load i64, ptr %address.binding.divisor.0
                    \\    %value.2 = icmp eq i64 %value.1, 0
                    \\    br i1 %value.2, label %division.0.zero_divisor, label %division.0.nonzero_divisor
                    \\division.0.zero_divisor:
                    \\    call void @matcha.compiler_module.runtime.function.panicDivisionByZero(i64 3, i64 25)
                    \\    unreachable
                    \\division.0.nonzero_divisor:
                    \\    %value.3 = icmp eq i64 %value.0, -9223372036854775808
                    \\    %value.4 = icmp eq i64 %value.1, -1
                    \\    %value.5 = and i1 %value.3, %value.4
                    \\    br i1 %value.5, label %division.0.overflow, label %division.0.no_overflow
                    \\division.0.overflow:
                    \\    call void @matcha.compiler_module.runtime.function.panicDivisionOverflow(i64 3, i64 25)
                    \\    unreachable
                    \\division.0.no_overflow:
                    \\    %value.6 = sdiv i64 %value.0, %value.1
                    \\    store i64 %value.6, ptr %address.binding.quotient.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const match = struct {
            test "lowers a match with a subject to a compare and branch chain" {
                const source =
                    \\val score = match 2 {
                    \\    1 => 10,
                    \\    2 => 20,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.score.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = icmp eq i64 2, 1
                    \\    br i1 %value.0, label %match.0.arm.0, label %match.0.arm.1.condition
                    \\match.0.arm.0:
                    \\    br label %match.0.end
                    \\match.0.arm.1.condition:
                    \\    %value.1 = icmp eq i64 2, 2
                    \\    br i1 %value.1, label %match.0.arm.1, label %match.0.else
                    \\match.0.arm.1:
                    \\    br label %match.0.end
                    \\match.0.else:
                    \\    br label %match.0.end
                    \\match.0.end:
                    \\    %value.2 = phi i64 [10, %match.0.arm.0], [20, %match.0.arm.1], [0, %match.0.else]
                    \\    store i64 %value.2, ptr %address.binding.score.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers a match without a subject to condition branches" {
                const source =
                    \\val flag = true;
                    \\val score = match {
                    \\    flag => 1,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.flag.0 = alloca i1
                    \\    %address.binding.score.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    store i1 1, ptr %address.binding.flag.0
                    \\    %value.0 = load i1, ptr %address.binding.flag.0
                    \\    br i1 %value.0, label %subjectless_match.0.arm.0, label %subjectless_match.0.else
                    \\subjectless_match.0.arm.0:
                    \\    br label %subjectless_match.0.end
                    \\subjectless_match.0.else:
                    \\    br label %subjectless_match.0.end
                    \\subjectless_match.0.end:
                    \\    %value.1 = phi i64 [1, %subjectless_match.0.arm.0], [0, %subjectless_match.0.else]
                    \\    store i64 %value.1, ptr %address.binding.score.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "compares a string match subject with the runtime string compare" {
                const source =
                    \\val score = match "pro" {
                    \\    "pro" => 1,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare i1 @matcha.compiler_module.runtime.function.stringCompare(ptr, i64, ptr, i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\@matcha.string_literal.0 = private unnamed_addr constant [3 x i8] c"pro"
                    \\@matcha.string_literal.1 = private unnamed_addr constant [3 x i8] c"pro"
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.score.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = getelementptr inbounds [3 x i8], ptr @matcha.string_literal.0, i64 0, i64 0
                    \\    %value.1 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.0, 0
                    \\    %value.2 = insertvalue %matcha.compiler_module.builtin.type.string %value.1, i64 3, 1
                    \\    %value.3 = getelementptr inbounds [3 x i8], ptr @matcha.string_literal.1, i64 0, i64 0
                    \\    %value.4 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.3, 0
                    \\    %value.5 = insertvalue %matcha.compiler_module.builtin.type.string %value.4, i64 3, 1
                    \\    %value.6 = extractvalue %matcha.compiler_module.builtin.type.string %value.2, 0
                    \\    %value.7 = extractvalue %matcha.compiler_module.builtin.type.string %value.2, 1
                    \\    %value.8 = extractvalue %matcha.compiler_module.builtin.type.string %value.5, 0
                    \\    %value.9 = extractvalue %matcha.compiler_module.builtin.type.string %value.5, 1
                    \\    %value.10 = call i1 @matcha.compiler_module.runtime.function.stringCompare(ptr %value.6, i64 %value.7, ptr %value.8, i64 %value.9)
                    \\    br i1 %value.10, label %match.0.arm.0, label %match.0.else
                    \\match.0.arm.0:
                    \\    br label %match.0.end
                    \\match.0.else:
                    \\    br label %match.0.end
                    \\match.0.end:
                    \\    %value.11 = phi i64 [1, %match.0.arm.0], [0, %match.0.else]
                    \\    store i64 %value.11, ptr %address.binding.score.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            pub const unions = struct {
                test "lowers to case index comparisons and payload loads" {
                    const source =
                        \\item Offset = union { None, Horizontal: int, Vertical: int };
                        \\val offset = Offset.Horizontal(4);
                        \\val result = match offset {
                        \\    .None => 0,
                        \\    .Horizontal(value) => value,
                        \\    .Vertical(value) => value,
                        \\};
                    ;
                    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                    defer arena.deinit();
                    const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                    const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                    try expect(llvm_ir).toMatch(
                        \\target triple = "x86_64-unknown-linux-gnu"
                        \\
                        \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                        \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                        \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                        \\
                        \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                        \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                        \\
                        \\%matcha.union.Offset.case.None = type { i32 }
                        \\%matcha.union.Offset.case.Horizontal = type { i32, i64 }
                        \\%matcha.union.Offset.case.Vertical = type { i32, i64 }
                        \\
                        \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                        \\entry:
                        \\    %address.binding.offset.0 = alloca ptr
                        \\    %address.binding.value.0 = alloca i64
                        \\    %address.binding.value.1 = alloca i64
                        \\    %address.binding.result.0 = alloca i64
                        \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                        \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Offset.case.Horizontal, ptr null, i64 1) to i64))
                        \\    %value.1 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.0, i32 0, i32 0
                        \\    store i32 1, ptr %value.1
                        \\    %value.2 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.0, i32 0, i32 1
                        \\    store i64 4, ptr %value.2
                        \\    store ptr %value.0, ptr %address.binding.offset.0
                        \\    %value.3 = load ptr, ptr %address.binding.offset.0
                        \\    %value.4 = load i32, ptr %value.3
                        \\    %value.5 = icmp eq i32 %value.4, 0
                        \\    br i1 %value.5, label %match.0.arm.0, label %match.0.arm.1.condition
                        \\match.0.arm.0:
                        \\    br label %match.0.end
                        \\match.0.arm.1.condition:
                        \\    %value.6 = load i32, ptr %value.3
                        \\    %value.7 = icmp eq i32 %value.6, 1
                        \\    br i1 %value.7, label %match.0.arm.1, label %match.0.arm.2.condition
                        \\match.0.arm.1:
                        \\    %value.8 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.3, i32 0, i32 1
                        \\    %value.9 = load i64, ptr %value.8
                        \\    store i64 %value.9, ptr %address.binding.value.0
                        \\    %value.10 = load i64, ptr %address.binding.value.0
                        \\    br label %match.0.end
                        \\match.0.arm.2.condition:
                        \\    br label %match.0.arm.2
                        \\match.0.arm.2:
                        \\    %value.11 = getelementptr inbounds %matcha.union.Offset.case.Vertical, ptr %value.3, i32 0, i32 1
                        \\    %value.12 = load i64, ptr %value.11
                        \\    store i64 %value.12, ptr %address.binding.value.1
                        \\    %value.13 = load i64, ptr %address.binding.value.1
                        \\    br label %match.0.end
                        \\match.0.end:
                        \\    %value.14 = phi i64 [0, %match.0.arm.0], [%value.10, %match.0.arm.1], [%value.13, %match.0.arm.2]
                        \\    store i64 %value.14, ptr %address.binding.result.0
                        \\    ret i32 0
                        \\}
                        \\
                    );
                }

                test "loads no payload when a case pattern has no binding" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Horizontal(4);
                        \\val result = match offset {
                        \\    .Horizontal => 1,
                        \\    .Vertical => 2,
                        \\};
                    ;
                    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                    defer arena.deinit();
                    const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                    const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                    try expect(llvm_ir).toMatch(
                        \\target triple = "x86_64-unknown-linux-gnu"
                        \\
                        \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                        \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                        \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                        \\
                        \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                        \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                        \\
                        \\%matcha.union.Offset.case.Horizontal = type { i32, i64 }
                        \\%matcha.union.Offset.case.Vertical = type { i32, i64 }
                        \\
                        \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                        \\entry:
                        \\    %address.binding.offset.0 = alloca ptr
                        \\    %address.binding.result.0 = alloca i64
                        \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                        \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Offset.case.Horizontal, ptr null, i64 1) to i64))
                        \\    %value.1 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.0, i32 0, i32 0
                        \\    store i32 0, ptr %value.1
                        \\    %value.2 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.0, i32 0, i32 1
                        \\    store i64 4, ptr %value.2
                        \\    store ptr %value.0, ptr %address.binding.offset.0
                        \\    %value.3 = load ptr, ptr %address.binding.offset.0
                        \\    %value.4 = load i32, ptr %value.3
                        \\    %value.5 = icmp eq i32 %value.4, 0
                        \\    br i1 %value.5, label %match.0.arm.0, label %match.0.arm.1.condition
                        \\match.0.arm.0:
                        \\    br label %match.0.end
                        \\match.0.arm.1.condition:
                        \\    br label %match.0.arm.1
                        \\match.0.arm.1:
                        \\    br label %match.0.end
                        \\match.0.end:
                        \\    %value.6 = phi i64 [1, %match.0.arm.0], [2, %match.0.arm.1]
                        \\    store i64 %value.6, ptr %address.binding.result.0
                        \\    ret i32 0
                        \\}
                        \\
                    );
                }

                test "compares the last arm when the match has an else arm" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Horizontal(4);
                        \\val result = match offset {
                        \\    .Horizontal(value) => value,
                        \\    else => 0,
                        \\};
                    ;
                    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                    defer arena.deinit();
                    const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                    const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                    try expect(llvm_ir).toMatch(
                        \\target triple = "x86_64-unknown-linux-gnu"
                        \\
                        \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                        \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                        \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                        \\
                        \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                        \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                        \\
                        \\%matcha.union.Offset.case.Horizontal = type { i32, i64 }
                        \\%matcha.union.Offset.case.Vertical = type { i32, i64 }
                        \\
                        \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                        \\entry:
                        \\    %address.binding.offset.0 = alloca ptr
                        \\    %address.binding.value.0 = alloca i64
                        \\    %address.binding.result.0 = alloca i64
                        \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                        \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Offset.case.Horizontal, ptr null, i64 1) to i64))
                        \\    %value.1 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.0, i32 0, i32 0
                        \\    store i32 0, ptr %value.1
                        \\    %value.2 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.0, i32 0, i32 1
                        \\    store i64 4, ptr %value.2
                        \\    store ptr %value.0, ptr %address.binding.offset.0
                        \\    %value.3 = load ptr, ptr %address.binding.offset.0
                        \\    %value.4 = load i32, ptr %value.3
                        \\    %value.5 = icmp eq i32 %value.4, 0
                        \\    br i1 %value.5, label %match.0.arm.0, label %match.0.else
                        \\match.0.arm.0:
                        \\    %value.6 = getelementptr inbounds %matcha.union.Offset.case.Horizontal, ptr %value.3, i32 0, i32 1
                        \\    %value.7 = load i64, ptr %value.6
                        \\    store i64 %value.7, ptr %address.binding.value.0
                        \\    %value.8 = load i64, ptr %address.binding.value.0
                        \\    br label %match.0.end
                        \\match.0.else:
                        \\    br label %match.0.end
                        \\match.0.end:
                        \\    %value.9 = phi i64 [%value.8, %match.0.arm.0], [0, %match.0.else]
                        \\    store i64 %value.9, ptr %address.binding.result.0
                        \\    ret i32 0
                        \\}
                        \\
                    );
                }

                test "binds no payload address when a case pattern binds a unit payload" {
                    const source =
                        \\item Signal = union { Off, On: unit };
                        \\val signal = Signal.On(unit);
                        \\val result = match signal {
                        \\    .Off => 0,
                        \\    .On(nothing) => 1,
                        \\};
                    ;
                    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                    defer arena.deinit();
                    const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                    const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                    try expect(llvm_ir).toMatch(
                        \\target triple = "x86_64-unknown-linux-gnu"
                        \\
                        \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                        \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                        \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                        \\
                        \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                        \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                        \\
                        \\%matcha.union.Signal.case.Off = type { i32 }
                        \\%matcha.union.Signal.case.On = type { i32 }
                        \\
                        \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                        \\entry:
                        \\    %address.binding.signal.0 = alloca ptr
                        \\    %address.binding.result.0 = alloca i64
                        \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                        \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                        \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.union.Signal.case.On, ptr null, i64 1) to i64))
                        \\    %value.1 = getelementptr inbounds %matcha.union.Signal.case.On, ptr %value.0, i32 0, i32 0
                        \\    store i32 1, ptr %value.1
                        \\    store ptr %value.0, ptr %address.binding.signal.0
                        \\    %value.2 = load ptr, ptr %address.binding.signal.0
                        \\    %value.3 = load i32, ptr %value.2
                        \\    %value.4 = icmp eq i32 %value.3, 0
                        \\    br i1 %value.4, label %match.0.arm.0, label %match.0.arm.1.condition
                        \\match.0.arm.0:
                        \\    br label %match.0.end
                        \\match.0.arm.1.condition:
                        \\    br label %match.0.arm.1
                        \\match.0.arm.1:
                        \\    br label %match.0.end
                        \\match.0.end:
                        \\    %value.5 = phi i64 [0, %match.0.arm.0], [1, %match.0.arm.1]
                        \\    store i64 %value.5, ptr %address.binding.result.0
                        \\    ret i32 0
                        \\}
                        \\
                    );
                }
            };
        };

        pub const arrays = struct {
            test "lowers an array literal and a for in loop over it" {
                const source =
                    \\val numbers = [1, 2];
                    \\for value in numbers {
                    \\    printInt(value);
                    \\}
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.builtin.function.printInt(i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.numbers.0 = alloca ptr
                    \\    %address.binding.value.0 = alloca i64
                    \\    %address.synthetic.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.compiler_module.builtin.type.array, ptr null, i64 1) to i64))
                    \\    %value.1 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 2) to i64))
                    \\    %value.2 = getelementptr inbounds i64, ptr %value.1, i64 0
                    \\    store i64 1, ptr %value.2
                    \\    %value.3 = getelementptr inbounds i64, ptr %value.1, i64 1
                    \\    store i64 2, ptr %value.3
                    \\    %value.4 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 0
                    \\    store i64 2, ptr %value.4
                    \\    %value.5 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 1
                    \\    store i64 2, ptr %value.5
                    \\    %value.6 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 2
                    \\    store ptr %value.1, ptr %value.6
                    \\    store ptr %value.0, ptr %address.binding.numbers.0
                    \\    %value.7 = load ptr, ptr %address.binding.numbers.0
                    \\    store i64 0, ptr %address.synthetic.0
                    \\    %value.8 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.7, i32 0, i32 0
                    \\    %value.9 = load i64, ptr %value.8
                    \\    %value.10 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.7, i32 0, i32 2
                    \\    %value.11 = load ptr, ptr %value.10
                    \\    br label %for_in.0.header
                    \\for_in.0.header:
                    \\    %value.12 = load i64, ptr %address.synthetic.0
                    \\    %value.13 = icmp slt i64 %value.12, %value.9
                    \\    br i1 %value.13, label %for_in.0.body, label %for_in.0.exit
                    \\for_in.0.body:
                    \\    %value.14 = getelementptr inbounds i64, ptr %value.11, i64 %value.12
                    \\    %value.15 = load i64, ptr %value.14
                    \\    store i64 %value.15, ptr %address.binding.value.0
                    \\    %value.16 = load i64, ptr %address.binding.value.0
                    \\    call void @matcha.compiler_module.builtin.function.printInt(i64 %value.16)
                    \\    br label %for_in.0.continue
                    \\for_in.0.continue:
                    \\    %value.17 = load i64, ptr %address.synthetic.0
                    \\    %value.18 = add i64 %value.17, 1
                    \\    store i64 %value.18, ptr %address.synthetic.0
                    \\    br label %for_in.0.header
                    \\for_in.0.exit:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers indexed assignment to a bounds checked store" {
                const source =
                    \\val numbers = [1];
                    \\numbers[0] = 2;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.runtime.function.panicIndexOutOfBounds(i64, i64, i64, i64) noreturn
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.numbers.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.compiler_module.builtin.type.array, ptr null, i64 1) to i64))
                    \\    %value.1 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
                    \\    %value.2 = getelementptr inbounds i64, ptr %value.1, i64 0
                    \\    store i64 1, ptr %value.2
                    \\    %value.3 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 0
                    \\    store i64 1, ptr %value.3
                    \\    %value.4 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 1
                    \\    store i64 1, ptr %value.4
                    \\    %value.5 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 2
                    \\    store ptr %value.1, ptr %value.5
                    \\    store ptr %value.0, ptr %address.binding.numbers.0
                    \\    %value.6 = load ptr, ptr %address.binding.numbers.0
                    \\    %value.7 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.6, i32 0, i32 0
                    \\    %value.8 = load i64, ptr %value.7
                    \\    %value.9 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.6, i32 0, i32 2
                    \\    %value.10 = icmp slt i64 0, 0
                    \\    %value.11 = icmp sge i64 0, %value.8
                    \\    %value.12 = or i1 %value.10, %value.11
                    \\    br i1 %value.12, label %index.0.out_of_bounds, label %index.0.in_bounds
                    \\index.0.out_of_bounds:
                    \\    call void @matcha.compiler_module.runtime.function.panicIndexOutOfBounds(i64 2, i64 8, i64 0, i64 %value.8)
                    \\    unreachable
                    \\index.0.in_bounds:
                    \\    %value.13 = load ptr, ptr %value.9
                    \\    %value.14 = getelementptr inbounds i64, ptr %value.13, i64 0
                    \\    store i64 2, ptr %value.14
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers append to the runtime slot helper and a typed store" {
                const source =
                    \\val numbers = [1];
                    \\numbers.append(2);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare ptr @matcha.compiler_module.runtime.function.arrayAppendSlot(ptr, i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.numbers.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.compiler_module.builtin.type.array, ptr null, i64 1) to i64))
                    \\    %value.1 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
                    \\    %value.2 = getelementptr inbounds i64, ptr %value.1, i64 0
                    \\    store i64 1, ptr %value.2
                    \\    %value.3 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 0
                    \\    store i64 1, ptr %value.3
                    \\    %value.4 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 1
                    \\    store i64 1, ptr %value.4
                    \\    %value.5 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 2
                    \\    store ptr %value.1, ptr %value.5
                    \\    store ptr %value.0, ptr %address.binding.numbers.0
                    \\    %value.6 = load ptr, ptr %address.binding.numbers.0
                    \\    %value.7 = call ptr @matcha.compiler_module.runtime.function.arrayAppendSlot(ptr %value.6, i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
                    \\    store i64 2, ptr %value.7
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "appends to an array of unit without calling the runtime" {
                const source =
                    \\val values: unit[] = [unit];
                    \\values.append(unit);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.values.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.compiler_module.builtin.type.array, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 0
                    \\    store i64 1, ptr %value.1
                    \\    %value.2 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 1
                    \\    store i64 1, ptr %value.2
                    \\    %value.3 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 2
                    \\    store ptr null, ptr %value.3
                    \\    store ptr %value.0, ptr %address.binding.values.0
                    \\    %value.4 = load ptr, ptr %address.binding.values.0
                    \\    %value.5 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.4, i32 0, i32 0
                    \\    %value.6 = load i64, ptr %value.5
                    \\    %value.7 = add i64 %value.6, 1
                    \\    store i64 %value.7, ptr %value.5
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "allocates nothing when an element returns early" {
                const source =
                    \\item make(): int = {
                    \\    val values = [{
                    \\        return 1;
                    \\    }];
                    \\    return 2;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i64 @matcha.function.make() {
                    \\entry:
                    \\    %address.binding.values.0 = alloca ptr
                    \\    ret i64 1
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const unit_erasure = struct {
            test "erases unit fields and parameters" {
                const source =
                    \\item Mixed = structure { value: int; erased: unit; };
                    \\item consume(nothing: unit, mixed: Mixed): unit = unit;
                    \\consume(unit, Mixed { value = 1, erased = unit });
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\%matcha.structure.Mixed = type { i64 }
                    \\
                    \\define void @matcha.function.consume(ptr %parameter.mixed) {
                    \\entry:
                    \\    %address.binding.mixed.0 = alloca ptr
                    \\    store ptr %parameter.mixed, ptr %address.binding.mixed.0
                    \\    ret void
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.structure.Mixed, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.structure.Mixed, ptr %value.0, i32 0, i32 0
                    \\    store i64 1, ptr %value.1
                    \\    call void @matcha.function.consume(ptr %value.0)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "allocates a structure with only unit fields as a single byte" {
                const source =
                    \\item Empty = structure { value: unit; };
                    \\item choose(flag: boolean): Empty = if flag {
                    \\    Empty { value = unit }
                    \\} else {
                    \\    Empty { value = unit }
                    \\};
                    \\val chosen = choose(true);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define ptr @matcha.function.choose(i1 %parameter.flag) {
                    \\entry:
                    \\    %address.binding.flag.0 = alloca i1
                    \\    store i1 %parameter.flag, ptr %address.binding.flag.0
                    \\    %value.0 = load i1, ptr %address.binding.flag.0
                    \\    br i1 %value.0, label %if.0.then, label %if.0.else
                    \\if.0.then:
                    \\    %value.1 = call ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64 1)
                    \\    br label %if.0.end
                    \\if.0.else:
                    \\    %value.2 = call ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64 1)
                    \\    br label %if.0.end
                    \\if.0.end:
                    \\    %value.3 = phi ptr [%value.1, %if.0.then], [%value.2, %if.0.else]
                    \\    ret ptr %value.3
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.chosen.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.function.choose(i1 1)
                    \\    store ptr %value.0, ptr %address.binding.chosen.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "omits element storage for an array of unit" {
                const source =
                    \\val values: unit[] = [unit, unit];
                    \\printInt(values.length);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.builtin.function.printInt(i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.values.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.compiler_module.builtin.type.array, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 0
                    \\    store i64 2, ptr %value.1
                    \\    %value.2 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 1
                    \\    store i64 2, ptr %value.2
                    \\    %value.3 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.0, i32 0, i32 2
                    \\    store ptr null, ptr %value.3
                    \\    store ptr %value.0, ptr %address.binding.values.0
                    \\    %value.4 = load ptr, ptr %address.binding.values.0
                    \\    %value.5 = getelementptr inbounds %matcha.compiler_module.builtin.type.array, ptr %value.4, i32 0, i32 0
                    \\    %value.6 = load i64, ptr %value.5
                    \\    call void @matcha.compiler_module.builtin.function.printInt(i64 %value.6)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const assignment = struct {
            test "lowers a compound assignment to a load operate store sequence" {
                const source =
                    \\var value = 5;
                    \\value += 2;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.value.0 = alloca i64
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    store i64 5, ptr %address.binding.value.0
                    \\    %value.0 = load i64, ptr %address.binding.value.0
                    \\    %value.1 = add i64 %value.0, 2
                    \\    store i64 %value.1, ptr %address.binding.value.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers a structure field assignment to a gep and store" {
                const source =
                    \\item Point = structure { x: int; };
                    \\var point = Point { x = 1 };
                    \\point.x = 2;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\%matcha.structure.Point = type { i64 }
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.point.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = call ptr @matcha.compiler_module.runtime.function.allocate(i64 ptrtoint (ptr getelementptr (%matcha.structure.Point, ptr null, i64 1) to i64))
                    \\    %value.1 = getelementptr inbounds %matcha.structure.Point, ptr %value.0, i32 0, i32 0
                    \\    store i64 1, ptr %value.1
                    \\    store ptr %value.0, ptr %address.binding.point.0
                    \\    %value.2 = load ptr, ptr %address.binding.point.0
                    \\    %value.3 = getelementptr inbounds %matcha.structure.Point, ptr %value.2, i32 0, i32 0
                    \\    store i64 2, ptr %value.3
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const runtime_calls = struct {
            test "passes a string literal through a function to printString" {
                const source =
                    \\item echo(text: string): string = text;
                    \\printString(echo("hi"));
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.builtin.function.printString(ptr, i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\@matcha.string_literal.0 = private unnamed_addr constant [2 x i8] c"hi"
                    \\
                    \\define %matcha.compiler_module.builtin.type.string @matcha.function.echo(%matcha.compiler_module.builtin.type.string %parameter.text) {
                    \\entry:
                    \\    %address.binding.text.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    store %matcha.compiler_module.builtin.type.string %parameter.text, ptr %address.binding.text.0
                    \\    %value.0 = load %matcha.compiler_module.builtin.type.string, ptr %address.binding.text.0
                    \\    ret %matcha.compiler_module.builtin.type.string %value.0
                    \\}
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = getelementptr inbounds [2 x i8], ptr @matcha.string_literal.0, i64 0, i64 0
                    \\    %value.1 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.0, 0
                    \\    %value.2 = insertvalue %matcha.compiler_module.builtin.type.string %value.1, i64 2, 1
                    \\    %value.3 = call %matcha.compiler_module.builtin.type.string @matcha.function.echo(%matcha.compiler_module.builtin.type.string %value.2)
                    \\    %value.4 = extractvalue %matcha.compiler_module.builtin.type.string %value.3, 0
                    \\    %value.5 = extractvalue %matcha.compiler_module.builtin.type.string %value.3, 1
                    \\    call void @matcha.compiler_module.builtin.function.printString(ptr %value.4, i64 %value.5)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers the input builtins to runtime calls" {
                const source =
                    \\val line = readLine();
                    \\val input = readFile("input.txt");
                    \\val arguments = getArguments();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.builtin.function.readFile(ptr, ptr, i64)
                    \\declare void @matcha.compiler_module.builtin.function.readLine(ptr)
                    \\declare ptr @matcha.compiler_module.builtin.function.getArguments()
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\@matcha.string_literal.0 = private unnamed_addr constant [9 x i8] c"input.txt"
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.synthetic.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.line.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.synthetic.1 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.input.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.arguments.0 = alloca ptr
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    call void @matcha.compiler_module.builtin.function.readLine(ptr %address.synthetic.0)
                    \\    %value.0 = load %matcha.compiler_module.builtin.type.string, ptr %address.synthetic.0
                    \\    store %matcha.compiler_module.builtin.type.string %value.0, ptr %address.binding.line.0
                    \\    %value.1 = getelementptr inbounds [9 x i8], ptr @matcha.string_literal.0, i64 0, i64 0
                    \\    %value.2 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.1, 0
                    \\    %value.3 = insertvalue %matcha.compiler_module.builtin.type.string %value.2, i64 9, 1
                    \\    %value.4 = extractvalue %matcha.compiler_module.builtin.type.string %value.3, 0
                    \\    %value.5 = extractvalue %matcha.compiler_module.builtin.type.string %value.3, 1
                    \\    call void @matcha.compiler_module.builtin.function.readFile(ptr %address.synthetic.1, ptr %value.4, i64 %value.5)
                    \\    %value.6 = load %matcha.compiler_module.builtin.type.string, ptr %address.synthetic.1
                    \\    store %matcha.compiler_module.builtin.type.string %value.6, ptr %address.binding.input.0
                    \\    %value.7 = call ptr @matcha.compiler_module.builtin.function.getArguments()
                    \\    store ptr %value.7, ptr %address.binding.arguments.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers the string and integer methods to runtime calls" {
                const source =
                    \\val text = "1";
                    \\val trimmed = text.trim();
                    \\val parts = trimmed.split(",");
                    \\val number = trimmed.toInt();
                    \\val digits = number.toString();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.builtin.type.string.method.trim(ptr, ptr, i64)
                    \\declare ptr @matcha.compiler_module.builtin.type.string.method.split(ptr, i64, ptr, i64)
                    \\declare i64 @matcha.compiler_module.builtin.type.string.method.toInt(ptr, i64)
                    \\declare void @matcha.compiler_module.builtin.type.int.method.toString(ptr, i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\@matcha.string_literal.0 = private unnamed_addr constant [1 x i8] c"1"
                    \\@matcha.string_literal.1 = private unnamed_addr constant [1 x i8] c","
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.binding.text.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.synthetic.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.trimmed.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.parts.0 = alloca ptr
                    \\    %address.binding.number.0 = alloca i64
                    \\    %address.synthetic.1 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.digits.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = getelementptr inbounds [1 x i8], ptr @matcha.string_literal.0, i64 0, i64 0
                    \\    %value.1 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.0, 0
                    \\    %value.2 = insertvalue %matcha.compiler_module.builtin.type.string %value.1, i64 1, 1
                    \\    store %matcha.compiler_module.builtin.type.string %value.2, ptr %address.binding.text.0
                    \\    %value.3 = load %matcha.compiler_module.builtin.type.string, ptr %address.binding.text.0
                    \\    %value.4 = extractvalue %matcha.compiler_module.builtin.type.string %value.3, 0
                    \\    %value.5 = extractvalue %matcha.compiler_module.builtin.type.string %value.3, 1
                    \\    call void @matcha.compiler_module.builtin.type.string.method.trim(ptr %address.synthetic.0, ptr %value.4, i64 %value.5)
                    \\    %value.6 = load %matcha.compiler_module.builtin.type.string, ptr %address.synthetic.0
                    \\    store %matcha.compiler_module.builtin.type.string %value.6, ptr %address.binding.trimmed.0
                    \\    %value.7 = load %matcha.compiler_module.builtin.type.string, ptr %address.binding.trimmed.0
                    \\    %value.8 = getelementptr inbounds [1 x i8], ptr @matcha.string_literal.1, i64 0, i64 0
                    \\    %value.9 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.8, 0
                    \\    %value.10 = insertvalue %matcha.compiler_module.builtin.type.string %value.9, i64 1, 1
                    \\    %value.11 = extractvalue %matcha.compiler_module.builtin.type.string %value.7, 0
                    \\    %value.12 = extractvalue %matcha.compiler_module.builtin.type.string %value.7, 1
                    \\    %value.13 = extractvalue %matcha.compiler_module.builtin.type.string %value.10, 0
                    \\    %value.14 = extractvalue %matcha.compiler_module.builtin.type.string %value.10, 1
                    \\    %value.15 = call ptr @matcha.compiler_module.builtin.type.string.method.split(ptr %value.11, i64 %value.12, ptr %value.13, i64 %value.14)
                    \\    store ptr %value.15, ptr %address.binding.parts.0
                    \\    %value.16 = load %matcha.compiler_module.builtin.type.string, ptr %address.binding.trimmed.0
                    \\    %value.17 = extractvalue %matcha.compiler_module.builtin.type.string %value.16, 0
                    \\    %value.18 = extractvalue %matcha.compiler_module.builtin.type.string %value.16, 1
                    \\    %value.19 = call i64 @matcha.compiler_module.builtin.type.string.method.toInt(ptr %value.17, i64 %value.18)
                    \\    store i64 %value.19, ptr %address.binding.number.0
                    \\    %value.20 = load i64, ptr %address.binding.number.0
                    \\    call void @matcha.compiler_module.builtin.type.int.method.toString(ptr %address.synthetic.1, i64 %value.20)
                    \\    %value.21 = load %matcha.compiler_module.builtin.type.string, ptr %address.synthetic.1
                    \\    store %matcha.compiler_module.builtin.type.string %value.21, ptr %address.binding.digits.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers string operators to runtime calls" {
                const source =
                    \\val joined = "a" + "b";
                    \\val same = joined == "ab";
                    \\val different = joined != "ab";
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = try fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                    \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                    \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                    \\declare void @matcha.compiler_module.runtime.function.stringConcatenate(ptr, ptr, i64, ptr, i64)
                    \\declare i1 @matcha.compiler_module.runtime.function.stringCompare(ptr, i64, ptr, i64)
                    \\
                    \\%matcha.compiler_module.builtin.type.string = type { ptr, i64 }
                    \\%matcha.compiler_module.builtin.type.array = type { i64, i64, ptr }
                    \\
                    \\@matcha.string_literal.0 = private unnamed_addr constant [1 x i8] c"a"
                    \\@matcha.string_literal.1 = private unnamed_addr constant [1 x i8] c"b"
                    \\@matcha.string_literal.2 = private unnamed_addr constant [2 x i8] c"ab"
                    \\@matcha.string_literal.3 = private unnamed_addr constant [2 x i8] c"ab"
                    \\
                    \\define i32 @main(i32 %parameter.argc, ptr %parameter.argv) {
                    \\entry:
                    \\    %address.synthetic.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.joined.0 = alloca %matcha.compiler_module.builtin.type.string
                    \\    %address.binding.same.0 = alloca i1
                    \\    %address.binding.different.0 = alloca i1
                    \\    call void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                    \\    call void @matcha.compiler_module.runtime.function.initArguments(i32 %parameter.argc, ptr %parameter.argv)
                    \\    %value.0 = getelementptr inbounds [1 x i8], ptr @matcha.string_literal.0, i64 0, i64 0
                    \\    %value.1 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.0, 0
                    \\    %value.2 = insertvalue %matcha.compiler_module.builtin.type.string %value.1, i64 1, 1
                    \\    %value.3 = getelementptr inbounds [1 x i8], ptr @matcha.string_literal.1, i64 0, i64 0
                    \\    %value.4 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.3, 0
                    \\    %value.5 = insertvalue %matcha.compiler_module.builtin.type.string %value.4, i64 1, 1
                    \\    %value.6 = extractvalue %matcha.compiler_module.builtin.type.string %value.2, 0
                    \\    %value.7 = extractvalue %matcha.compiler_module.builtin.type.string %value.2, 1
                    \\    %value.8 = extractvalue %matcha.compiler_module.builtin.type.string %value.5, 0
                    \\    %value.9 = extractvalue %matcha.compiler_module.builtin.type.string %value.5, 1
                    \\    call void @matcha.compiler_module.runtime.function.stringConcatenate(ptr %address.synthetic.0, ptr %value.6, i64 %value.7, ptr %value.8, i64 %value.9)
                    \\    %value.10 = load %matcha.compiler_module.builtin.type.string, ptr %address.synthetic.0
                    \\    store %matcha.compiler_module.builtin.type.string %value.10, ptr %address.binding.joined.0
                    \\    %value.11 = load %matcha.compiler_module.builtin.type.string, ptr %address.binding.joined.0
                    \\    %value.12 = getelementptr inbounds [2 x i8], ptr @matcha.string_literal.2, i64 0, i64 0
                    \\    %value.13 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.12, 0
                    \\    %value.14 = insertvalue %matcha.compiler_module.builtin.type.string %value.13, i64 2, 1
                    \\    %value.15 = extractvalue %matcha.compiler_module.builtin.type.string %value.11, 0
                    \\    %value.16 = extractvalue %matcha.compiler_module.builtin.type.string %value.11, 1
                    \\    %value.17 = extractvalue %matcha.compiler_module.builtin.type.string %value.14, 0
                    \\    %value.18 = extractvalue %matcha.compiler_module.builtin.type.string %value.14, 1
                    \\    %value.19 = call i1 @matcha.compiler_module.runtime.function.stringCompare(ptr %value.15, i64 %value.16, ptr %value.17, i64 %value.18)
                    \\    store i1 %value.19, ptr %address.binding.same.0
                    \\    %value.20 = load %matcha.compiler_module.builtin.type.string, ptr %address.binding.joined.0
                    \\    %value.21 = getelementptr inbounds [2 x i8], ptr @matcha.string_literal.3, i64 0, i64 0
                    \\    %value.22 = insertvalue %matcha.compiler_module.builtin.type.string undef, ptr %value.21, 0
                    \\    %value.23 = insertvalue %matcha.compiler_module.builtin.type.string %value.22, i64 2, 1
                    \\    %value.24 = extractvalue %matcha.compiler_module.builtin.type.string %value.20, 0
                    \\    %value.25 = extractvalue %matcha.compiler_module.builtin.type.string %value.20, 1
                    \\    %value.26 = extractvalue %matcha.compiler_module.builtin.type.string %value.23, 0
                    \\    %value.27 = extractvalue %matcha.compiler_module.builtin.type.string %value.23, 1
                    \\    %value.28 = call i1 @matcha.compiler_module.runtime.function.stringCompare(ptr %value.24, i64 %value.25, ptr %value.26, i64 %value.27)
                    \\    %value.29 = xor i1 %value.28, 1
                    \\    store i1 %value.29, ptr %address.binding.different.0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };
    };
};
