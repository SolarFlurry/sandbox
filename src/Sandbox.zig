const Sandbox = @This();

const std = @import("std");
const Material = @import("Material.zig");

const Allocator = std.mem.Allocator;

const getMaterial = Material.getMaterial;

allocator: Allocator,
buffer: []Cell,
chunks: [sandbox_width * sandbox_height / 64 / 64]Chunk,
current_frame: u32 = 0,

pub const sandbox_width: u32 = 512;
pub const sandbox_height: u32 = 256;

const Chunk = struct {
    dirty_rect: DirtyRect = .empty,
    next_frame_dirty_rect: DirtyRect = .empty,

    const DirtyRect = struct {
        const empty: DirtyRect = .{
            .min_x = 63,
            .min_y = 63,
            .max_x = 0,
            .max_y = 0,
        };

        const full: DirtyRect = .{
            .min_x = 0,
            .min_y = 0,
            .max_x = 63,
            .max_y = 63,
        };

        min_x: u8,
        min_y: u8,
        max_x: u8,
        max_y: u8,
    };
};

const Move = struct {
    from: u32,
    to: u32,
};

const Cell = struct {
    kind: Material.Index,
    // what the kind will be set to at the end of the frame
    next_kind: Material.OptionalIndex,
};
const MoveSuccess = enum {
    success,
    reserved,
    failed,
};

const FallDir = enum {
    left,
    right,
    down_left,
    down_right,
};

pub const Error = error{OutOfBounds};

pub fn init(allocator: Allocator) Allocator.Error!Sandbox {
    const sandbox: Sandbox = .{
        .allocator = allocator,
        .buffer = try allocator.alloc(Cell, @intCast(sandbox_width * sandbox_height)),
        .chunks = @splat(.{}),
    };
    @memset(sandbox.buffer, .{
        .kind = .empty,
        .next_kind = .none,
    });
    return sandbox;
}

pub fn deinit(s: *Sandbox) void {
    s.allocator.free(s.buffer);
}

pub fn update(s: *Sandbox, io: std.Io, random: std.Random) (Sandbox.Error || std.Io.Cancelable || std.Io.ConcurrentError || Allocator.Error)!void {
    const offsets: [4][2]u8 = .{
        .{ 0, 0 },
        .{ 0, 1 },
        .{ 1, 0 },
        .{ 1, 1 },
    };

    // random.shuffle([2]u8, &offsets);

    var group: std.Io.Group = .init;

    var row_biases: [sandbox_height]bool = undefined;
    for (&row_biases) |*x| {
        x.* = random.boolean();
    }

    const jitter_x = 0;
    const jitter_y = 0;

    for (offsets) |offset| {
        var idx: usize = 0;

        for (0..sandbox_height / 64 / 2) |j| {
            const y: i32 = (@as(i32, @intCast(j * 2)) * 64) + jitter_y + (offset[1] * 64);
            for (0..sandbox_width / 64 / 2) |i| {
                const x: i32 = (@as(i32, @intCast(i * 2)) * 64) + jitter_x + (offset[0] * 64);

                if (x >= sandbox_width or y >= sandbox_height or x < -64 or y < -64) continue;

                const seed = random.int(u64);
                group.async(io, updateSquare, .{ s, seed, x, y, &row_biases });

                idx += 1;
            }
        }

        try group.await(io);
    }

    for (s.buffer) |*cell| {
        if (cell.next_kind != .none) {
            cell.kind = .fromOptional(cell.next_kind);
        }
        cell.next_kind = .none;
    }

    s.updateDirtyRects();

    s.current_frame += 1;
}

fn updateSquare(s: *Sandbox, seed: u64, x: i32, y: i32, row_biases: []bool) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const chunk = &s.chunks[@as(usize, @intCast(y)) / 64 * (sandbox_width / 64) + @as(usize, @intCast(x)) / 64];
    const dirty_rect = chunk.dirty_rect;

    if (dirty_rect.min_y > dirty_rect.max_y or dirty_rect.min_x > dirty_rect.max_x) return;

    for (dirty_rect.min_y..dirty_rect.max_y + 1) |j| {
        // const y_iter: i32 = 64 - @as(i32, @intCast(j)) - 1 + y;
        const y_iter = @as(i32, @intCast(j)) + y;
        if (y_iter < 0 or y_iter >= sandbox_height) continue;

        const process_row_left = row_biases[@intCast(y_iter)];

        for (0..dirty_rect.max_x - dirty_rect.min_x + 1) |i| {
            const x_iter: i32 = if (process_row_left)
                @as(i32, @intCast(i)) + x + dirty_rect.min_x
            else
                dirty_rect.max_x - dirty_rect.min_x - @as(i32, @intCast(i)) + x + dirty_rect.min_x;

            if (x_iter < 0 or x_iter >= sandbox_width) continue;

            const cell = s.get(x_iter, y_iter);
            const material = getMaterial(cell.kind);

            if (cell.next_kind != .none) continue;

            const fall_bias = random.enumValue(FallDir);

            switch (cell.kind) {
                .empty => continue,
                .stone => continue,
                else => {},
            }

            if (material.is_fluid) {
                s.updateLiquid(chunk, fall_bias, x_iter, y_iter, x);
            } else {
                s.updateSolid(chunk, fall_bias, x_iter, y_iter);
            }
        }
    }

    // s.resolveMoves(chunk, random) catch {};
}

pub fn locToIndex(x: i32, y: i32) u32 {
    return @intCast(y * sandbox_width + x);
}

pub fn get(self: *Sandbox, x: i32, y: i32) Cell {
    return self.buffer[locToIndex(x, y)];
}

pub fn set(self: *Sandbox, kind: Material.Index, x: i32, y: i32) void {
    const idx = locToIndex(x, y);

    // if (kind != .none) self.buffer[idx].last_updated_frame = self.current_frame;

    self.buffer[idx].kind = kind;
}

pub fn setBoundsCheck(s: *Sandbox, kind: Material.Index, x: i32, y: i32) bool {
    if (x < 0 or x >= sandbox_width or y < 0 or y >= sandbox_height) return false;
    s.set(kind, x, y);
    return true;
}

pub fn fill(self: *Sandbox, kind: Material.Index, x: i32, y: i32, width: i32, height: i32) void {
    for (0..@intCast(width)) |i| {
        for (0..@intCast(height)) |j| {
            _ = self.setBoundsCheck(kind, x + @as(i32, @intCast(i)), y + @as(i32, @intCast(j)));
        }
    }

    self.addDirtyRectArea(x - 1, y - 1, width + 2, height + 2);
}

pub fn getBoundsCheck(self: *Sandbox, x: i32, y: i32) ?Cell {
    if (x < 0 or x >= sandbox_width or y < 0 or y >= sandbox_height) return null;
    return self.get(x, y);
}

// updates the dirty rect with an exclusive (excludes left_x+width and top_y+height) rectangle region
pub fn addDirtyRectArea(s: *Sandbox, left_x: i32, top_y: i32, width: i32, height: i32) void {
    const chunk_positions: [4][2]i32 = .{
        .{ @intCast(@divTrunc(left_x, 64)), @intCast(@divTrunc(top_y, 64)) },
        .{ @intCast(@divTrunc(left_x, 64)), @intCast(@divTrunc(top_y + height - 1, 64)) },
        .{ @intCast(@divTrunc(left_x + width - 1, 64)), @intCast(@divTrunc(top_y, 64)) },
        .{ @intCast(@divTrunc(left_x + width - 1, 64)), @intCast(@divTrunc(top_y + height - 1, 64)) },
    };

    for (chunk_positions) |chunk_pos| {
        const chunk_world_x = chunk_pos[0] * 64;
        const chunk_world_y = chunk_pos[1] * 64;

        const idx: usize = @intCast(chunk_pos[1] * @divTrunc(sandbox_width, 64) + chunk_pos[0]);
        if (idx >= s.chunks.len) continue;

        const chunk = &s.chunks[idx];

        chunk.next_frame_dirty_rect.min_x = @min(
            @max(left_x - chunk_world_x, 0),
            chunk.next_frame_dirty_rect.min_x,
        );
        chunk.next_frame_dirty_rect.max_x = @intCast(@max(
            @min(left_x + width - 1 - chunk_world_x, 63),
            chunk.next_frame_dirty_rect.max_x,
        ));

        chunk.next_frame_dirty_rect.min_y = @min(
            @max(top_y - chunk_world_y, 0),
            chunk.next_frame_dirty_rect.min_y,
        );
        chunk.next_frame_dirty_rect.max_y = @intCast(@max(
            @min(top_y + height - 1 - chunk_world_y, 63),
            chunk.next_frame_dirty_rect.max_y,
        ));
    }
}

pub fn updateDirtyRects(s: *Sandbox) void {
    for (&s.chunks) |*chunk| {
        chunk.dirty_rect = chunk.next_frame_dirty_rect;
        chunk.next_frame_dirty_rect = .empty;
    }
}

fn moveCell(s: *Sandbox, chunk: *Chunk, from: u32, to: u32) void {
    _ = chunk;

    const from_cell = &s.buffer[from];
    const to_cell = &s.buffer[to];

    if (to_cell.next_kind != .none) return;

    from_cell.next_kind = to_cell.kind.toOptional();
    to_cell.next_kind = from_cell.kind.toOptional();

    const from_x: i32 = @intCast(from % sandbox_width);
    const from_y: i32 = @intCast(from / sandbox_width);
    const to_x: i32 = @intCast(to % sandbox_width);
    const to_y: i32 = @intCast(to / sandbox_width);

    s.addDirtyRectArea(from_x - 2, from_y - 2, 4, 4);
    s.addDirtyRectArea(to_x - 2, to_y - 2, 4, 4);
}

fn updateSolid(s: *Sandbox, chunk: *Chunk, bias: FallDir, x: i32, y: i32) void {
    if (y == sandbox_height) return;

    const offsets: [3]i32 = switch (bias) {
        .down_left => .{ 0, -1, 1 },
        .down_right => .{ 0, 1, -1 },
        .left => .{ -1, 0, 1 },
        .right => .{ 1, 0, -1 },
    };

    for (offsets) |offset| {
        const target_x = x + offset;
        const target_y = y + 1;

        const target_cell = s.getBoundsCheck(target_x, target_y) orelse continue;

        // if (target_cell.last_updated_frame == s.current_frame) continue;

        const kind = s.get(x, y).kind;

        const mat0 = getMaterial(kind);
        const mat1 = getMaterial(target_cell.kind);

        if (mat1.density >= mat0.density) continue;

        const source_idx = locToIndex(x, y);
        const target_idx = locToIndex(target_x, target_y);

        s.moveCell(chunk, source_idx, target_idx);

        break;
    }
}

fn updateLiquid(s: *Sandbox, chunk: *Chunk, bias: FallDir, x: i32, y: i32, chunk_x: i32) void {
    if (y == sandbox_height) return;
    _ = chunk_x;

    const offsets: [3]i8 = switch (bias) {
        .down_left => .{ 0, -1, 1 },
        .down_right => .{ 0, 1, -1 },
        .left => .{ -1, 0, 1 },
        .right => .{ 1, 0, -1 },
    };

    const kind = s.get(x, y).kind;
    const mat0 = getMaterial(kind);

    outer: for (offsets) |dispersion_dir| {
        if (dispersion_dir == 0) {
            const target_cell = s.getBoundsCheck(x, y + 1) orelse continue;

            // if (target_cell.last_updated_frame == s.current_frame) continue;

            const mat1 = getMaterial(target_cell.kind);

            if (mat1.density >= mat0.density) continue;

            const source_idx = locToIndex(x, y);
            const target_idx = locToIndex(x, y + 1);

            s.moveCell(chunk, source_idx, target_idx);

            break;
        }

        for (0..mat0.dispersion_rate) |i| {
            const target_x = x + dispersion_dir * (@as(i8, @intCast(i)) + 1);

            const target_down_cell = s.getBoundsCheck(target_x, y + 1) orelse continue;

            const mat1 = getMaterial(target_down_cell.kind);

            if (mat1.density >= mat0.density) continue;

            const source_idx = locToIndex(x, y);
            const target_idx = locToIndex(target_x, y + 1);

            s.moveCell(chunk, source_idx, target_idx);

            break :outer;
        }

        for (0..mat0.dispersion_rate) |i| {
            const target_x = x + dispersion_dir * @as(i8, @intCast(mat0.dispersion_rate - i));

            const target_down_cell = s.getBoundsCheck(target_x, y) orelse continue;

            const mat1 = getMaterial(target_down_cell.kind);

            if (mat1.density >= mat0.density) continue;

            const source_idx = locToIndex(x, y);
            const target_idx = locToIndex(target_x, y);

            s.moveCell(chunk, source_idx, target_idx);

            break :outer;
        }
    }
    //
    // if (bias == .left) {
    //     if (s.disperseParticle(x, y, material.dispersion_rate, -1) == .success) return;
    //     if (s.disperseParticle(x, y, material.dispersion_rate, 1) == .success) return;
    // } else {
    //     if (s.disperseParticle(x, y, material.dispersion_rate, 1) == .success) return;
    //     if (s.disperseParticle(x, y, material.dispersion_rate, -1) == .success) return;
    // }
}
