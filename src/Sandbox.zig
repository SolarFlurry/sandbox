const Sandbox = @This();

const std = @import("std");
const Material = @import("Material.zig");

const getMaterial = Material.getMaterial;

buffer: []Cell,
current_frame: u32 = 0,

pub const sandbox_width: u32 = 512;
pub const sandbox_height: u32 = 256;

const Cell = struct {
    kind: Material.Index,
    last_updated_frame: u32,
};
const MoveSuccess = enum {
    success,
    reserved,
    failed,
};

const FallDir = enum {
    left,
    right,
    down,
};

pub const Error = error{OutOfBounds};

pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Sandbox {
    const sandbox: Sandbox = .{
        .buffer = try allocator.alloc(Cell, @intCast(sandbox_width * sandbox_height)),
    };
    @memset(sandbox.buffer, .{
        .last_updated_frame = 0,
        .kind = .none,
    });
    return sandbox;
}

pub fn deinit(self: *Sandbox, allocator: std.mem.Allocator) void {
    allocator.free(self.buffer);
}

pub fn updateBottomTop(s: *Sandbox, random: std.Random) Sandbox.Error!void {
    for (0..256) |j| {
        const y_iter: i32 = 256 - @as(i32, @intCast(j)) - 1;
        if (y_iter < 0 or y_iter >= sandbox_height) continue;

        const process_row_left = random.boolean();

        for (0..512) |i| {
            const x_iter: i32 = if (process_row_left)
                @as(i32, @intCast(i))
            else
                512 - @as(i32, @intCast(i)) - 1;

            if (x_iter < 0 or x_iter >= sandbox_width) continue;

            const cell = s.get(x_iter, y_iter);

            if (cell.last_updated_frame == s.current_frame) continue;

            const fall_bias = random.enumValue(FallDir);

            switch (cell.kind) {
                .none => continue,
                .sand => s.updateSolid(fall_bias, x_iter, y_iter),
                .water => s.updateLiquid(fall_bias, x_iter, y_iter, 0),
                .stone => continue,
            }
        }
    }

    s.current_frame += 1;
}

pub fn update(s: *Sandbox, io: std.Io, random: std.Random) (Sandbox.Error || std.Io.Cancelable || std.Io.ConcurrentError)!void {
    var offsets: [4][2]u8 = .{
        .{ 0, 0 },
        .{ 0, 1 },
        .{ 1, 0 },
        .{ 1, 1 },
    };

    random.shuffle([2]u8, &offsets);

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

    s.current_frame += 1;
}

fn updateSquare(s: *Sandbox, seed: u64, x: i32, y: i32, row_biases: []bool) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    for (0..64) |j| {
        const y_iter: i32 = 64 - @as(i32, @intCast(j)) - 1 + y;
        if (y_iter < 0 or y_iter >= sandbox_height) continue;

        const process_row_left = row_biases[@intCast(y_iter)];

        for (0..64) |i| {
            const x_iter: i32 = if (process_row_left)
                @as(i32, @intCast(i)) + x
            else
                64 - @as(i32, @intCast(i)) - 1 + x;

            if (x_iter < 0 or x_iter >= sandbox_width) continue;

            const cell = s.get(x_iter, y_iter);

            if (cell.last_updated_frame == s.current_frame) continue;

            const fall_bias = random.enumValue(FallDir);

            switch (cell.kind) {
                .none => continue,
                .sand => s.updateSolid(fall_bias, x_iter, y_iter),
                .water => s.updateLiquid(fall_bias, x_iter, y_iter, x),
                .stone => continue,
            }
        }
    }
}

pub fn locToIndex(x: i32, y: i32) usize {
    return @intCast(y * sandbox_width + x);
}

pub fn get(self: *Sandbox, x: i32, y: i32) Cell {
    return self.buffer[locToIndex(x, y)];
}

pub fn set(self: *Sandbox, kind: Material.Index, x: i32, y: i32) void {
    self.buffer[locToIndex(x, y)] = .{
        .kind = kind,
        .last_updated_frame = self.current_frame,
    };
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
}

pub fn setNoUpdated(self: *Sandbox, kind: Material.Index, x: i32, y: i32) (Error || error{AlreadySet})!void {
    if (x < 0 or x >= sandbox_width or y < 0 or y >= sandbox_height) return Error.OutOfBounds;
    const idx = locToIndex(x, y);
    if (self.buffer[idx].last_updated_frame == self.current_frame) return error.AlreadySet;
    self.buffer[idx] = .{
        .kind = kind,
        .last_updated_frame = self.current_frame,
    };
}

pub fn getBoundsCheck(self: *Sandbox, x: i32, y: i32) ?Cell {
    if (x < 0 or x >= sandbox_width or y < 0 or y >= sandbox_height) return null;
    return self.get(x, y);
}

fn moveParticle(s: *Sandbox, x: i32, y: i32, x1: i32, y1: i32) MoveSuccess {
    const kind = s.get(x, y).kind;
    if (s.getBoundsCheck(x1, y1)) |cell| {
        const mat0 = getMaterial(kind);
        const mat1 = getMaterial(cell.kind);
        if (mat0.density > mat1.density) {
            s.setNoUpdated(kind, x1, y1) catch return .reserved;

            if (x != x1) {
                s.buffer[locToIndex(x, y)].kind = cell.kind;
            } else s.set(cell.kind, x, y);
            return .success;
        }
    }
    return .failed;
}

fn updateSolid(s: *Sandbox, bias: FallDir, x: i32, y: i32) void {
    if (y == sandbox_height) return;

    const offsets: [3]i32 = switch (bias) {
        .down => .{ 0, -1, 1 },
        .left => .{ -1, 0, 1 },
        .right => .{ 1, 0, -1 },
    };

    for (offsets) |offset| {
        if (s.moveParticle(x, y, x + offset, y + 1) == .success) return;
    }
}

fn disperseParticle(s: *Sandbox, x: i32, y: i32, dispersion_rate: u8, direction: i8) MoveSuccess {
    var dispersed = false;
    for (0..dispersion_rate) |i| {
        const old_x = x + @as(i32, @intCast(i)) * direction;
        const new_x = x + @as(i32, @intCast(i + 1)) * direction;

        const moved_down = s.moveParticle(old_x, y, new_x, y + 1);
        if (moved_down == .success) return .success;

        const result = s.moveParticle(old_x, y, new_x, y);
        if (result != .success) break;
        dispersed = true;
    }

    return if (dispersed) .success else .failed;
}

fn updateLiquid(s: *Sandbox, bias: FallDir, x: i32, y: i32, chunk_x: i32) void {
    if (y == sandbox_height) return;

    // const material = getMaterial(kind);

    const offsets: [5][2]i8 = switch (bias) {
        .down => .{ .{ 0, 1 }, .{ -1, 1 }, .{ 1, 1 }, .{ -1, 0 }, .{ 1, 0 } },
        .left => .{ .{ -1, 1 }, .{ 0, 1 }, .{ 1, 1 }, .{ -1, 0 }, .{ 1, 0 } },
        .right => .{ .{ 1, 1 }, .{ 0, 1 }, .{ -1, 1 }, .{ 1, 0 }, .{ -1, 0 } },
    };

    for (offsets) |offset| {
        const target_x = x + offset[0];
        const target_y = y + offset[1];

        if (offset[1] == 0 and x == chunk_x + 63) {
            if (s.getBoundsCheck(x + 1, target_y)) |cell| {
                if (cell.kind != .none) continue;
            }
        }
        if (offset[1] == 0 and x == chunk_x) {
            if (s.getBoundsCheck(x - 1, target_y)) |cell| {
                if (cell.kind != .none) continue;
            }
        }

        if (offset[1] == 0) {
            if (s.disperseParticle(x, y, 1, offset[0]) == .success) return;
        } else {
            if (s.moveParticle(x, y, target_x, target_y) == .success) return;
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
