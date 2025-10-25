package Neutron

import "base:runtime"
import "core:sync"

NEUTRON_ALLOCATOR_INIT_SIZE: int = 128

DataType :: enum {
    NUMERIC,
    STRING,
    BOOL,
}

// Each allocated object stores type, pointer, and size
@(private)
NeutronAllocatorObj :: struct {
    type: DataType,
    data_ptr: rawptr,
    size: int,
}

// Non-thread-safe allocator structure
@(private)
NeutronAllocator :: struct {
    numbers: [dynamic]rawptr,
    strings: [dynamic]rawptr,
    bools:   [dynamic]rawptr,

    allocated_objs: [dynamic]NeutronAllocatorObj
}

// ----------------------------
// Initialize allocator
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, require_results, private)
init_neutron_allocator :: proc() -> ^NeutronAllocator {
    allocator := cast(^NeutronAllocator)runtime.heap_alloc(size_of(NeutronAllocator))
    if allocator == nil {
        panic("NEUTRON_ALLOCATOR.INIT.ERROR.GOT_NIL_PTR")
    }

    allocator.numbers = make([dynamic]rawptr, 0, NEUTRON_ALLOCATOR_INIT_SIZE)
    allocator.strings = make([dynamic]rawptr, 0, NEUTRON_ALLOCATOR_INIT_SIZE)
    allocator.bools   = make([dynamic]rawptr, 0, NEUTRON_ALLOCATOR_INIT_SIZE)
    allocator.allocated_objs = make([dynamic]NeutronAllocatorObj, 0, NEUTRON_ALLOCATOR_INIT_SIZE*3)

    return allocator
}

// ----------------------------
// Allocate a new block
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, require_results, private)
alloc :: proc(t: DataType, size: int, allocator: ^NeutronAllocator) -> rawptr {
    ptr := runtime.heap_alloc(size)
    if ptr == nil {
        panic("NEUTRON_ALLOCATOR.ALLOC.FAIL.GOT_NIL_PTR")
    }

    obj := NeutronAllocatorObj{ t, ptr, size }
    append(&allocator.allocated_objs, obj)

    slab: ^[dynamic]rawptr
    switch t {
    case .NUMERIC: slab = &allocator.numbers
    case .STRING:  slab = &allocator.strings
    case .BOOL:    slab = &allocator.bools
    }
    append(slab, ptr)

    return ptr
}

// ----------------------------
// Reallocate an existing block
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, require_results, private)
realloc :: proc(old_ptr: rawptr, new_size: int, allocator: ^NeutronAllocator) -> rawptr {
    new_ptr := runtime.heap_alloc(new_size)
    if new_ptr == nil {
        panic("NEUTRON_ALLOCATOR.REALLOC.FAIL.GOT_NIL_PTR")
    }

    for obj, i in allocator.allocated_objs {
        if obj.data_ptr == old_ptr {
            // copy only up to the smaller of the old and new sizes
            copy_size := obj.size < new_size ? obj.size : new_size
            runtime.mem_copy(new_ptr, old_ptr, copy_size)

            allocator.allocated_objs[i].data_ptr = new_ptr
            allocator.allocated_objs[i].size = new_size

            slab: ^[dynamic]rawptr
            switch obj.type {
            case .NUMERIC: slab = &allocator.numbers
            case .STRING:  slab = &allocator.strings
            case .BOOL:    slab = &allocator.bools
            }
            for j := 0; j < len(slab); j += 1 {
                if slab[j] == old_ptr {
                    slab[j] = new_ptr
                    break
                }
            }

            runtime.heap_free(old_ptr)
            break
        }
    }

    return new_ptr
}

// ----------------------------
// Free a block
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, private)
free :: proc(ptr: rawptr, allocator: ^NeutronAllocator) {
    for obj, i in allocator.allocated_objs {
        if obj.data_ptr == ptr {
            last_index := len(allocator.allocated_objs) - 1
            if i != last_index {
                allocator.allocated_objs[i] = allocator.allocated_objs[last_index]
            }
            resize(&allocator.allocated_objs, last_index)

            slab: ^[dynamic]rawptr
            switch obj.type {
            case .NUMERIC: slab = &allocator.numbers
            case .STRING:  slab = &allocator.strings
            case .BOOL:    slab = &allocator.bools
            }
            for j := 0; j < len(slab); j += 1 {
                if slab[j] == ptr {
                    last_slab := len(slab) - 1
                    if j != last_slab {
                        slab[j] = slab[last_slab]
                    }
                    resize(slab, last_slab)
                    break
                }
            }

            runtime.heap_free(ptr)
            break
        }
    }
}

// ----------------------------
// Delete allocator
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, private)
delete_neutron_allocator :: proc(allocator: ^NeutronAllocator) {
    for obj in allocator.allocated_objs {
        runtime.heap_free(obj.data_ptr)
    }
    delete(allocator.numbers)
    delete(allocator.strings)
    delete(allocator.bools)
    delete(allocator.allocated_objs)
}

// ============================
// Thread-safe version
// ============================

@(private)
NeutronAllocatorThreadSafe :: struct {
    numbers: [dynamic]rawptr,
    strings: [dynamic]rawptr,
    bools:   [dynamic]rawptr,
    allocated_objs: [dynamic]NeutronAllocatorObj,
    _mutex: ^sync.Mutex
}

@(no_sanitize_address, no_sanitize_memory, require_results, private)
init_neutron_allocator_thread_safe :: proc() -> ^NeutronAllocatorThreadSafe {
    allocator := cast(^NeutronAllocatorThreadSafe)runtime.heap_alloc(size_of(NeutronAllocatorThreadSafe))
    if allocator == nil {
        panic("NEUTRON_ALLOCATOR.THREADSAFE.INIT.FAIL")
    }

    allocator.numbers = make([dynamic]rawptr, 0, NEUTRON_ALLOCATOR_INIT_SIZE)
    allocator.strings = make([dynamic]rawptr, 0, NEUTRON_ALLOCATOR_INIT_SIZE)
    allocator.bools   = make([dynamic]rawptr, 0, NEUTRON_ALLOCATOR_INIT_SIZE)
    allocator.allocated_objs = make([dynamic]NeutronAllocatorObj, 0, NEUTRON_ALLOCATOR_INIT_SIZE*3)
    allocator._mutex = cast(^sync.Mutex)runtime.heap_alloc(size_of(sync.Mutex))

    return allocator
}

// ----------------------------
// Thread-safe alloc
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, require_results, private)
alloc_threadsafe :: proc(t: DataType, size: int, allocator: ^NeutronAllocatorThreadSafe) -> rawptr {
    sync.lock(allocator._mutex)
    defer sync.unlock(allocator._mutex)

    ptr := runtime.heap_alloc(size)
    if ptr == nil {
        panic("NEUTRON_ALLOCATOR.THREADSAFE.ALLOC.FAIL")
    }

    obj := NeutronAllocatorObj{t, ptr, size}
    append(&allocator.allocated_objs, obj)

    slab: ^[dynamic]rawptr
    switch t {
    case .NUMERIC: slab = &allocator.numbers
    case .STRING:  slab = &allocator.strings
    case .BOOL:    slab = &allocator.bools
    }
    append(slab, ptr)

    return ptr
}

// ----------------------------
// Thread-safe realloc
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, require_results, private)
realloc_threadsafe :: proc(old_ptr: rawptr, new_size: int, allocator: ^NeutronAllocatorThreadSafe) -> rawptr {
    sync.lock(allocator._mutex)
    defer sync.unlock(allocator._mutex)

    new_ptr := runtime.heap_alloc(new_size)
    if new_ptr == nil {
        panic("NEUTRON_ALLOCATOR.THREADSAFE.REALLOC.FAIL")
    }

    for obj, i in allocator.allocated_objs {
        if obj.data_ptr == old_ptr {
            copy_size := obj.size < new_size ? obj.size : new_size
            runtime.mem_copy(new_ptr, old_ptr, copy_size)

            allocator.allocated_objs[i].data_ptr = new_ptr
            allocator.allocated_objs[i].size = new_size

            slab: ^[dynamic]rawptr
            switch obj.type {
            case .NUMERIC: slab = &allocator.numbers
            case .STRING:  slab = &allocator.strings
            case .BOOL:    slab = &allocator.bools
            }
            for j := 0; j < len(slab); j += 1 {
                if slab[j] == old_ptr {
                    slab[j] = new_ptr
                    break
                }
            }

            runtime.heap_free(old_ptr)
            break
        }
    }

    return new_ptr
}

// ----------------------------
// Thread-safe free
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, private)
free_threadsafe :: proc(ptr: rawptr, allocator: ^NeutronAllocatorThreadSafe) {
    sync.lock(allocator._mutex)
    defer sync.unlock(allocator._mutex)

    for obj, i in allocator.allocated_objs {
        if obj.data_ptr == ptr {
            last_index := len(allocator.allocated_objs) - 1
            if i != last_index {
                allocator.allocated_objs[i] = allocator.allocated_objs[last_index]
            }
            resize(&allocator.allocated_objs, last_index)

            slab: ^[dynamic]rawptr
            switch obj.type {
            case .NUMERIC: slab = &allocator.numbers
            case .STRING:  slab = &allocator.strings
            case .BOOL:    slab = &allocator.bools
            }
            for j := 0; j < len(slab); j += 1 {
                if slab[j] == ptr {
                    last_slab := len(slab) - 1
                    if j != last_slab {
                        slab[j] = slab[last_slab]
                    }
                    resize(slab, last_slab)
                    break
                }
            }

            runtime.heap_free(ptr)
            break
        }
    }
}

// ----------------------------
// Thread-safe delete
// ----------------------------
@(no_sanitize_address, no_sanitize_memory, private)
delete_neutron_allocator_threadsafe :: proc(allocator: ^NeutronAllocatorThreadSafe) {
    for obj in allocator.allocated_objs {
        runtime.heap_free(obj.data_ptr)
    }

    delete(allocator.numbers)
    delete(allocator.strings)
    delete(allocator.bools)
    delete(allocator.allocated_objs)
    runtime.heap_free(allocator._mutex)
}

// ============================
// Public API
// ============================

Allocator :: struct {
    is_thread_safe: bool,
    _allocator: ^NeutronAllocator,
    _threadsafe_allocator: ^NeutronAllocatorThreadSafe
}

@(require_results)
InitAllocator :: proc(is_thread_safe: bool) -> ^Allocator {
    allocator := new(Allocator)
    allocator.is_thread_safe = is_thread_safe

    if is_thread_safe {
        allocator._threadsafe_allocator = init_neutron_allocator_thread_safe()
    } else {
        allocator._allocator = init_neutron_allocator()
    }
    return allocator
}

@(require_results)
Alloc :: proc(t: DataType, size: int, allocator: ^Allocator) -> rawptr {
    if allocator.is_thread_safe {
        return alloc_threadsafe(t, size, allocator._threadsafe_allocator)
    }
    return alloc(t, size, allocator._allocator)
}

@(require_results)
Realloc :: proc(old_ptr: rawptr, new_size: int, allocator: ^Allocator) -> rawptr {
    if allocator.is_thread_safe {
        return realloc_threadsafe(old_ptr, new_size, allocator._threadsafe_allocator)
    }
    return realloc(old_ptr, new_size, allocator._allocator)
}

Free :: proc(ptr: rawptr, allocator: ^Allocator) {
    if allocator.is_thread_safe {
        free_threadsafe(ptr, allocator._threadsafe_allocator)
    } else {
        free(ptr, allocator._allocator)
    }
}

DeleteAllocator :: proc(allocator: ^Allocator) {
    if allocator.is_thread_safe {
        delete_neutron_allocator_threadsafe(allocator._threadsafe_allocator)
    } else {
        delete_neutron_allocator(allocator._allocator)
    }
    runtime.free(allocator)
}
