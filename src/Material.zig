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
