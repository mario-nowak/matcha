extern fn GC_init() void;
extern fn GC_malloc(size: usize) ?*anyopaque;
extern fn GC_malloc_atomic(size: usize) ?*anyopaque;

export fn matcha_initiate_garbage_collector() void {
    GC_init();
}

export fn matcha_allocate(size: usize) ?*anyopaque {
    return GC_malloc(size);
}

export fn matcha_allocate_atomic(size: usize) ?*anyopaque {
    return GC_malloc_atomic(size);
}
