const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {
    rl.initWindow(1250, 600, "Bilinear Interpolation");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const tile = try rl.loadTexture("tiletest.jpeg");
    defer tile.unload();

    const tile_bilerp: rl.RenderTexture2D = try .init(tile.width * 8, tile.height * 8);
    defer tile_bilerp.unload();

    const bilerp_shader = try rl.loadShader(null, "src/shaders/bilerp.frag");
    defer bilerp_shader.unload();

    const cellular_carve_shader = try rl.loadShader(null, "src/shaders/cellular_carving.frag");
    defer cellular_carve_shader.unload();

    const seed_loc = rl.getShaderLocation(bilerp_shader, "u_seed");
    const world_space_loc = rl.getShaderLocation(bilerp_shader, "u_worldSpace");

    const seed: f32 = 37.809381;

    rl.setShaderValue(bilerp_shader, seed_loc, &seed, .float);
    rl.setShaderValue(bilerp_shader, world_space_loc, &[2]f32{ 0, 0 }, .vec2);

    const cellular_a: rl.RenderTexture2D = try .init(tile.width * 8, tile.height * 8);
    defer cellular_a.unload();
    const cellular_b: rl.RenderTexture2D = try .init(tile.width * 8, tile.height * 8);
    defer cellular_b.unload();

    while (!rl.windowShouldClose()) {
        var src = &cellular_a;
        var dst = &cellular_b;
        {
            rl.beginTextureMode(src.*);
            defer rl.endTextureMode();

            rl.clearBackground(.blank);

            rl.beginShaderMode(bilerp_shader);
            defer rl.endShaderMode();

            rl.drawTexturePro(
                tile,
                .init(0, 0, @floatFromInt(tile.width), @floatFromInt(-tile.height)),
                .init(0, 0, @floatFromInt(tile.width * 8), @floatFromInt(tile.height * 8)),
                .init(0, 0),
                0,
                .white,
            );
        }

        for (0..5) |_| {
            rl.beginTextureMode(dst.*);
            defer rl.endTextureMode();

            rl.beginShaderMode(cellular_carve_shader);
            defer rl.endShaderMode();

            rl.clearBackground(.blank);

            rl.drawTexturePro(
                src.texture,
                .init(0, 0, @floatFromInt(tile.width * 8), @floatFromInt(-tile.height * 8)),
                .init(0, 0, @floatFromInt(tile.width * 8), @floatFromInt(tile.height * 8)),
                .init(0, 0),
                0,
                .white,
            );

            std.mem.swap(*const rl.RenderTexture, &src, &dst);
        }

        rl.beginDrawing();

        rl.clearBackground(.ray_white);

        rl.drawTextureEx(src.texture, .init(0, 0), 0, @as(f32, @floatFromInt(600)) / @as(f32, @floatFromInt(tile.height * 8)), .white);
        rl.drawTextureEx(tile, .init(650, 0), 0, @as(f32, @floatFromInt(600)) / @as(f32, @floatFromInt(tile.height)), .white);

        rl.endDrawing();
    }
}
