const std = @import("std");
const Allocator = std.mem.Allocator;

const ecs = @import("../ecs.zig");
const Entity = ecs.Entity;

pub fn Component(comptime T: type) type {
    return struct {
        const Self = @This();

        sparse: SparseArray(OptionalIndex, .none),
        dense: std.MultiArrayList(struct {
            component: T,
            entity: Entity,
        }),

        pub const empty: Self = .{
            .sparse = .empty,
            .dense = .empty,
        };

        pub fn deinit(s: *Self, gpa: Allocator) void {
            s.sparse.deinit(gpa);
            s.dense.deinit(gpa);
        }

        pub fn get(s: *Self, entity: Entity) ?*T {
            const idx = s.sparse.get(@intFromEnum(entity));
            if (idx == .none) return null;
            return &s.dense.items(.component)[@intFromEnum(idx)];
        }

        /// Adds a new component to the entity, whether they already have one or not.
        /// It is recommended to use `setOrAppend` instead.
        pub fn append(s: *Self, gpa: Allocator, entity: Entity, component: T) Allocator.Error!void {
            try s.sparse.set(gpa, @intFromEnum(entity), @enumFromInt(s.dense.len));
            try s.dense.append(gpa, .{
                .component = component,
                .entity = entity,
            });
        }

        /// Checks whether the entity already has this component. If it is already known,
        /// use `append` if the entity does not have it, or `get` if it does.
        pub fn setOrAppend(s: *Self, gpa: Allocator, entity: Entity, component: T) Allocator.Error!void {
            const existing = s.get(entity);
            if (existing) |c| {
                c.* = component;
                return;
            }
            try s.append(gpa, entity, component);
        }

        /// Removes an entity from this component, assuming they have the component.
        pub fn remove(s: *Self, entity: Entity) void {
            const dense_idx = s.sparse.get(@intFromEnum(entity));
            const dense_last = s.dense.get(s.dense.len - 1);

            s.sparse.setNoEnsure(@intFromEnum(dense_last.entity), dense_idx);
            s.sparse.setNoEnsure(@intFromEnum(entity), .none);

            s.dense.set(@intFromEnum(dense_idx), dense_last);
            _ = s.dense.pop();
        }
    };
}

const OptionalIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,
};

/// A sparse array implementation
/// max_size - the maximum size of the sparse array. Must be a power of 2
/// T - the type to store
/// value_if_none - the value to return if no value could be found
fn SparseArray(comptime T: type, comptime value_if_none: T) type {
    return struct {
        const Self = @This();
        pub const blobSize: usize = 512;

        blobs: std.ArrayList(?[*]T),

        pub const empty: Self = .{
            .blobs = .empty,
        };

        fn ensureAtLeast(s: *Self, gpa: Allocator, idx: usize) Allocator.Error!void {
            const blob = blobFromIdx(idx);

            if (blob >= s.blobs.items.len) {
                const new_items = blob - s.blobs.items.len + 1;
                try s.blobs.ensureTotalCapacity(gpa, blob + 1);
                for (0..new_items) |_| {
                    s.blobs.appendAssumeCapacity(null);
                }
            }

            if (s.blobs.items[blob] == null) {
                s.blobs.items[blob] = (try gpa.alloc(T, blobSize)).ptr;
            }
        }

        fn blobFromIdx(idx: usize) usize {
            return idx / blobSize;
        }

        pub fn deinit(s: *Self, gpa: Allocator) void {
            for (s.blobs.items) |oblob| {
                if (oblob) |blob| {
                    const slice: []T = blob[0..blobSize];
                    gpa.free(slice);
                }
            }
            s.blobs.deinit(gpa);
        }

        pub fn get(s: *const Self, idx: usize) T {
            const blob = blobFromIdx(idx);
            if (blob >= s.blobs.items.len) return value_if_none;
            if (s.blobs.items[blob] == null) return value_if_none;
            return s.blobs.items[blob].?[idx % blobSize];
        }

        pub fn set(s: *Self, gpa: Allocator, idx: usize, item: T) Allocator.Error!void {
            try s.ensureAtLeast(gpa, idx);
            s.setNoEnsure(idx, item);
        }

        /// Sets item at `idx` to `item`, ignoring needed allocations
        pub fn setNoEnsure(s: *Self, idx: usize, item: T) void {
            const blob = blobFromIdx(idx);
            s.blobs.items[blob].?[idx % blobSize] = item;
        }
    };
}
