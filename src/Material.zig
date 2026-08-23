const Material = @This();

const std = @import("std");
const rl = @import("raylib");

color: rl.Color,
density: u32,
is_fluid: bool,
dispersion_rate: u8,

pub const Index = enum(u8) {
    empty = 0,
    sand,
    water,
    stone,

    // assumes optional is not none
    pub fn fromOptional(optional: OptionalIndex) Index {
        return @enumFromInt(@intFromEnum(optional));
    }

    pub fn toOptional(index: Index) OptionalIndex {
        return @enumFromInt(@intFromEnum(index));
    }
};

pub const OptionalIndex = optional_index: {
    const index_info = @typeInfo(Index).@"enum";

    var field_names: [index_info.fields.len + 1][]const u8 = undefined;
    var field_values: [index_info.fields.len + 1]index_info.tag_type = undefined;

    field_names[index_info.fields.len] = "none";
    field_values[index_info.fields.len] = std.math.maxInt(index_info.tag_type);

    for (index_info.fields, 0..) |field, i| {
        field_names[i] = field.name;
        field_values[i] = field.value;
    }

    break :optional_index @Enum(
        index_info.tag_type,
        .exhaustive,
        &field_names,
        &field_values,
    );
};

pub fn getMaterial(index: Index) Material {
    return materials[@intFromEnum(index)];
}

pub const materials: []const Material = &.{
    // none
    Material{
        .color = .blank,
        .density = 0,
        .is_fluid = false,
        .dispersion_rate = 0,
    },
    // sand
    Material{
        .color = .yellow,
        .density = 10,
        .is_fluid = false,
        .dispersion_rate = 0,
    },
    // water
    Material{
        .color = .blue,
        .density = 1,
        .is_fluid = true,
        .dispersion_rate = 2,
    },
    // stone
    Material{
        .color = .light_gray,
        .density = 20,
        .is_fluid = false,
        .dispersion_rate = 12,
    },
};
