const std = @import("std");
const rl = @import("raylib");

const Material = @import("Material.zig");

const cell_size: i32 = 2;
const screen_width = Sandbox.sandbox_width * cell_size;
const screen_height = Sandbox.sandbox_height * cell_size;

const Sandbox = @import("Sandbox.zig");

const Render = struct {
    color_buffer: []rl.Color,
    texture: rl.Texture2D,

    pub fn init(allocator: std.mem.Allocator) (std.mem.Allocator.Error || error{LoadTexture})!Render {
        const blank_image = rl.genImageColor(Sandbox.sandbox_width, Sandbox.sandbox_height, .blank);
        const result: Render = .{
            .color_buffer = try allocator.alloc(rl.Color, Sandbox.sandbox_width * Sandbox.sandbox_height),
            .texture = try .fromImage(blank_image),
        };

        rl.unloadImage(blank_image);

        return result;
    }

    pub fn deinit(r: *Render, allocator: std.mem.Allocator) void {
        allocator.free(r.color_buffer);
        rl.unloadTexture(r.texture);
    }

    pub fn render(r: *Render, s: *Sandbox) void {
        var idx: usize = 0;
        for (0..Sandbox.sandbox_height) |j| {
            for (0..Sandbox.sandbox_width) |i| {
                const cell = s.buffer[Sandbox.locToIndex(@intCast(i), @intCast(j))];

                r.color_buffer[idx] = Material.materials[@intFromEnum(cell.kind)].color;
                idx += 1;
            }
        }

        rl.updateTexture(r.texture, r.color_buffer.ptr);
    }
};

pub fn main(init: std.process.Init) !void {
    var sandbox: Sandbox = try .init(init.gpa);
    defer sandbox.deinit();

    rl.initWindow(screen_width, screen_height, "sandbox");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var brush_size: u8 = 1;
    var brush_material: Material.Index = .sand;

    var seed: u64 = undefined;
    init.io.random(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var render_ctx: Render = try .init(init.gpa);
    defer render_ctx.deinit(init.gpa);

    var paused = false;

    while (!rl.windowShouldClose()) {
        const mouse_pos = rl.getMousePosition();
        if (rl.isMouseButtonDown(.left)) {
            const x: i32 = @trunc(mouse_pos.x / cell_size - brush_size / 2);
            const y: i32 = @trunc(mouse_pos.y / cell_size - brush_size / 2);

            sandbox.fill(brush_material, x, y, brush_size, brush_size);
        } else if (rl.isMouseButtonDown(.right)) {
            const x: i32 = @trunc(mouse_pos.x / cell_size - brush_size / 2);
            const y: i32 = @trunc(mouse_pos.y / cell_size - brush_size / 2);

            sandbox.fill(.empty, x, y, brush_size, brush_size);
        }

        if (rl.isKeyPressed(.space)) paused = !paused;

        if (rl.isKeyDown(.minus)) brush_size -|= 1;
        if (rl.isKeyDown(.equal)) brush_size +|= 1;
        if (rl.isKeyPressed(.r)) @memset(sandbox.buffer, .{
            .kind = .empty,
            .next_kind = .none,
        });

        if (rl.isKeyPressed(.one)) brush_material = .sand;
        if (rl.isKeyPressed(.two)) brush_material = .water;
        if (rl.isKeyPressed(.three)) brush_material = .stone;

        if (!paused or rl.isKeyPressed(.right)) {
            try sandbox.update(init.io, random);
        }

        render_ctx.render(&sandbox);

        rl.beginDrawing();

        rl.clearBackground(.dark_gray);

        rl.drawTextureEx(render_ctx.texture, .init(0, 0), 0, cell_size, .white);

        rl.drawRectangleLines(
            @as(i32, @trunc(mouse_pos.x / cell_size - brush_size / 2)) * cell_size,
            @as(i32, @trunc(mouse_pos.y / cell_size - brush_size / 2)) * cell_size,
            brush_size * cell_size,
            brush_size * cell_size,
            .sky_blue,
        );

        rl.drawFPS(2, 2);
        rl.endDrawing();
    }
}
