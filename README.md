# About
Neutron is a specialized slab-style memory allocator written in Odin.
It provides fast, type-segmented allocation for three fundamental data types — NUMERIC, STRING, and BOOL and supports both thread-safe and non-thread-safe modes.

# Overview
Neutron is not a general-purpose allocator.
It is purpose-built for systems that repeatedly allocate and release small fixed-type objects, such as scripting runtimes, VM heaps, and interpreters.


Neutron uses three static-style slabs (dynamic internally but not individually heap-allocated)

* numbers: holds numeric blocks
* strings: holds string blocks
* bools: holds boolean blocks

Each allocation is tracked in an internal registry (allocated_objs) with a data type, pointer and its slab membership.
When an object is freed, Neutron shifts and compacts the slab efficiently without invalidating existing pointers.

# Features
* Uses Three segregated slabs: NUMERIC, STRING, BOOL
* Thread-safe mode using a Mutex
* Uses only  `core:mem`, `base:runtime` and `core:sync`
* Compact free and realloc operations
