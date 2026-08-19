const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

pub const Entity = enum(u32) { _ };
pub const Component = @import("ECS/component.zig").Component;

/// Returns an Entity Component System context. Pass this around by pointer
/// and not value.
pub fn ECS(comptime C: []const type) type {
    const struct_fields = blk: {
        var component_names: [C.len][]const u8 = undefined;
        var components: [C.len]type = undefined;
        var field_attrs: [C.len]std.builtin.Type.StructField.Attributes = undefined;
        for (C, 0..) |c, i| {
            component_names[i] = @typeName(c);
            components[i] = Component(c);
            field_attrs[i] = .{
                .default_value_ptr = &components[i].empty,
            };
        }
        break :blk .{ component_names, components, field_attrs };
    };

    return struct {
        const Self = @This();

        const Components = @Struct(.auto, null, &struct_fields.@"0", &struct_fields.@"1", &struct_fields.@"2");

        pub fn Iterator(comptime components: []const type) type {
            return struct {
                const IteratorSelf = @This();
                const Return = blk: {
                    var ptr_type: [components.len]type = undefined;
                    for (components, 0..) |component, i| {
                        ptr_type[i] = *component;
                    }
                    break :blk @Tuple(&(.{Entity} ++ ptr_type));
                };

                const first_component_name = @typeName(components[0]);

                ecs: *Self,
                i: usize,

                pub fn next(s: *IteratorSelf) ?Return {
                    const first_component = &@field(s.ecs.components, first_component_name);

                    outer: while (s.i < first_component.dense.len) {
                        const entity = first_component.dense.items(.entity)[s.i];

                        s.i += 1;

                        var return_unit: Return = undefined;
                        return_unit.@"0" = entity;

                        inline for (components, 1..) |c, i| {
                            const compare_component = &@field(s.ecs.components, @typeName(c));

                            if (compare_component.get(entity)) |component| {
                                const return_unit_component = &@field(return_unit, std.fmt.comptimePrint("{d}", .{i}));
                                return_unit_component.* = component;
                            } else continue :outer;
                        }

                        return return_unit;
                    }

                    return null;
                }
            };
        }

        components: Components,
        free_list: std.ArrayList(Entity),
        next_entity_id: @typeInfo(Entity).@"enum".tag_type,

        pub fn init() Self {
            return .{
                .next_entity_id = 0,
                .components = .{},
                .free_list = .empty,
            };
        }

        pub fn deinit(s: *Self, gpa: Allocator) void {
            inline for (struct_fields.@"0") |name| {
                const component = &@field(s.components, name);
                component.deinit(gpa);
            }

            s.free_list.deinit(gpa);
        }

        /// Registers an entity in the system and returns it's id
        pub fn create(s: *Self) Entity {
            if (s.free_list.items.len > 0) return s.free_list.pop().?;
            const result: Entity = @enumFromInt(s.next_entity_id);
            s.next_entity_id += 1;
            return result;
        }

        /// Removes an entity from the system
        pub fn destroy(s: *Self, gpa: Allocator, entity: Entity) Allocator.Error!void {
            std.debug.assert(@intFromEnum(entity) < s.next_entity_id);

            inline for (struct_fields.@"0") |name| {
                const component = &@field(s.components, name);

                if (component.get(entity)) |_| {
                    component.remove(entity);
                }
            }
            try s.free_list.append(gpa, entity);
        }

        /// Adds a component to the entity, assuming the entity does not already have the component
        pub fn emplaceComponent(s: *Self, gpa: Allocator, entity: Entity, component: anytype) Allocator.Error!void {
            const entity_components = &@field(s.components, @typeName(@TypeOf(component)));
            try entity_components.append(gpa, entity, component);
        }

        /// Returns an iterator over the entities with the components
        pub fn iter(s: *Self, comptime components: []const type) Iterator(components) {
            return .{
                .ecs = s,
                .i = 0,
            };
        }
    };
}

test "view" {
    const Hittable = struct { health: u32 };
    const Named = struct { name: []const u8 };

    const gpa = std.testing.allocator;

    var ecs = ECS(&.{
        Hittable,
        Named,
    }).init();
    defer ecs.deinit(gpa);

    const enemy = ecs.create();
    defer ecs.destroy(gpa, enemy) catch {};

    try ecs.emplaceComponent(gpa, enemy, Hittable{ .health = 10 });
    try ecs.emplaceComponent(gpa, enemy, Named{ .name = "George" });

    var health_entities = ecs.iter(&.{ Hittable, Named });
    while (health_entities.next()) |entity_data| {
        const entity, const hittable, const named = entity_data;
        std.debug.print("Entity \"{s}\", id {d} has health {d}\n", .{ named.name, @intFromEnum(entity), hittable.health });
        named.name = "Fred";
    }

    var named_hittable_entities = ecs.iter(&.{ Hittable, Named });
    while (named_hittable_entities.next()) |entity_data| {
        const entity, const hittable, const named = entity_data;
        std.debug.print("Entity \"{s}\", id {d} has health {d}\n", .{ named.name, @intFromEnum(entity), hittable.health });
    }
}

test "many entities" {
    const RigidBody = struct {};

    const gpa = std.testing.allocator;

    var ecs = ECS(&.{RigidBody}).init();
    defer ecs.deinit(gpa);

    for (0..200000) |_| {
        const entity = ecs.create();
        try ecs.emplaceComponent(gpa, entity, RigidBody{});
    }

    var rigid_bodies = ecs.iter(&.{RigidBody});
    var rigid_body_count: usize = 0;
    while (rigid_bodies.next()) |_| {
        rigid_body_count += 1;
    }
    std.debug.print("There are {d} rigid bodies.\n", .{rigid_body_count});
}
