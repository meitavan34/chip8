const Self = @This();

const std = @import("std");
const sdl3 = @import("sdl3");
const Allocator = std.mem.Allocator;

const display_width = 64;
const display_height = 32;

const mem_size = 4096;

mem: [mem_size]u8,
display: [display_width * display_height]bool,
key: [16]bool,
stack: [16]u16,
v: [16]u8,
allocator: Allocator,
window: sdl3.video.Window,
time_delta: u64,
timers_acc: u64,
I: u16,
pc: u16,
sp: u8,
dt: u8,
st: u8,
is_running: bool,
last_wait_input: ?Keys,

const sprites = [_][]const u8{
    \\****
    \\*  *
    \\*  *
    \\*  *
    \\****
    \\
    ,
    \\  *
    \\ **
    \\  *
    \\  *
    \\ ***
    \\
    ,
    \\****
    \\   *
    \\****
    \\*
    \\****
    \\
    ,
    \\****
    \\   *
    \\****
    \\   *
    \\****
    \\
    ,
    \\*  *
    \\*  *
    \\****
    \\   *
    \\   *
    \\
    ,
    \\****
    \\*
    \\****
    \\   *
    \\****
    \\
    ,
    \\****
    \\*
    \\****
    \\*  *
    \\****
    \\
    ,
    \\****
    \\   *
    \\  *
    \\ *
    \\ *
    \\
    ,
    \\****
    \\*  *
    \\****
    \\*  *
    \\****
    \\
    ,
    \\****
    \\*  *
    \\****
    \\   *
    \\****
    \\
    ,
    \\****
    \\*  *
    \\****
    \\*  *
    \\*  *
    \\
    ,
    \\***
    \\*  *
    \\***
    \\*  *
    \\***
    \\
    ,
    \\****
    \\*
    \\*
    \\*
    \\****
    \\
    ,
    \\***
    \\*  *
    \\*  *
    \\*  *
    \\***
    \\
    ,
    \\****
    \\*
    \\****
    \\*
    \\****
    \\
    ,
    \\****
    \\*
    \\****
    \\*
    \\*
    \\
};

pub fn init(allocator: Allocator, data: []u8, window: sdl3.video.Window) Self {
    var mem: [mem_size]u8 = .{0} ** mem_size;
    var pos: usize = 0;
    for (sprites) |sprite| {
        var line: u8 = 0;
        var i: u8 = 0;
        for (sprite) |ch| {
            if (ch == '\n') {
                mem[pos] = line;
                pos += 1;
                line = 0;
                i = 0;
                continue;
            } else if (ch != ' ') {
                const one: u8 = 1;
                line |= one << @intCast(7 - i);
            }
            i += 1;
        }
    }
    for (data, 0..) |byte, i| {
        mem[0x200 + i] = byte;
    }
    return .{
        .allocator = allocator,
        .window = window,
        .time_delta = 0.0,
        .timers_acc = 0,
        .mem = mem,
        .display = .{false} ** (display_width * display_height),
        .key = .{false} ** 16,
        .stack = .{0} ** 16,
        .v = .{0} ** 16,
        .I = 0,
        .pc = 0x200,
        .sp = 0,
        .dt = 0,
        .st = 0,
        .is_running = true,
        .last_wait_input = null,
    };
}

var rnd: std.Random.Xoshiro256 = undefined;

pub fn run(self: *Self) !void {
    rnd = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    var prev = sdl3.timer.getMillisecondsSinceInit();
    while (self.is_running) {
        self.processInput();
        self.dumpKeys();
        const next = sdl3.timer.getMillisecondsSinceInit();
        defer prev = next;
        self.time_delta = next - prev;
        self.decTimers();
        if (self.fetchU16()) |inst| {
            self.execute(inst);
        } else |_| {}

        try self.render();
        // self.dumpDisplay();
    }
}

fn render(self: *Self) !void {
    const surface = try self.window.getSurface();
    const size = try self.window.getSize();
    const xsize = size.width / display_width;
    const ysize = size.height / display_height;
    try surface.clear(.{});
    const w: i32 = @intCast(xsize);
    const h: i32 = @intCast(ysize);
    for (self.display, 0..) |pixel, pos| {
        if (pixel) {
            const tx: i32 = @intCast(pos % display_width);
            const ty: i32 = @intCast(pos / display_width);
            const x = tx * w;
            const y = ty * w;
            try surface.fillRect(.{ .x = x, .y = y, .w = w, .h = h }, sdl3.pixels.mapSurfaceRgb(surface, 0, 0xff, 0xff));
        }
    }
    try self.window.updateSurface();
}

fn keycodeToKey(keycode: sdl3.keycode.Keycode) ?Keys {
    return switch (keycode) {
        .one => .k1,
        .two => .k2,
        .three => .k3,
        .four => .kc,

        .q => .k4,
        .w => .k5,
        .e => .k6,
        .r => .kd,

        .a => .k7,
        .s => .k8,
        .d => .k9,
        .f => .ke,

        .z => .ka,
        .x => .k0,
        .c => .kb,
        .v => .kf,
        else => null,
    };
}

fn processInput(self: *Self) void {
    while (sdl3.events.poll()) |event| {
        switch (event) {
            .quit => {
                self.is_running = false;
            },
            .key_down => |key| {
                if (!std.meta.eql(key.mod, .{})) {
                    return;
                }
                if (key.key) |keycode| {
                    switch (keycode) {
                        .escape => {
                            self.is_running = false;
                        },
                        else => {},
                    }
                    if (keycodeToKey(keycode)) |k| {
                        self.keyDown(k);
                    }
                }
            },
            .key_up => |key| {
                if (!std.meta.eql(key.mod, .{})) {
                    return;
                }
                if (key.key) |keycode| {
                    if (keycodeToKey(keycode)) |k| {
                        self.keyUp(k);
                    }
                }
            },
            else => {},
        }
    }
}

fn waitKey(self: *Self) Keys {
    while (self.is_running) {
        sdl3.events.wait() catch unreachable;
        self.processInput();
        if (self.last_wait_input) |key| {
            self.last_wait_input = null;
            return key;
        }
    }
    return .k0;
}

const Keys = enum(u4) {
    k1,
    k2,
    k3,
    kc,

    k4,
    k5,
    k6,
    kd,

    k7,
    k8,
    k9,
    ke,

    ka,
    k0,
    kb,
    kf,

    pub fn fromInt(num: u4) Keys {
        const look_up = [16]Keys{
            .k0,
            .k1,
            .k2,
            .k3,
            .k4,
            .k5,
            .k6,
            .k7,
            .k8,
            .k9,
            .ka,
            .kb,
            .kc,
            .kd,
            .ke,
            .kf,
        };
        return look_up[num];
    }

    pub fn index(self: Keys) u4 {
        return @intFromEnum(self);
    }
};

fn keyDown(self: *Self, key: Keys) void {
    self.last_wait_input = key;
    self.key[key.index()] = true;
}

fn keyUp(self: *Self, key: Keys) void {
    self.key[key.index()] = false;
}

const timer_freq: f32 = 1000.0 / 60.0;

fn decTimers(self: *Self) void {
    self.timers_acc += self.time_delta;
    if (@as(f32, @floatFromInt(self.timers_acc)) >= timer_freq) {
        self.timers_acc = 0;
        if (self.dt > 0) {
            self.dt -= 1;
        }
        if (self.st > 0) {
            self.st -= 1;
        }
    }
}

fn clear(self: *Self) void {
    self.display = std.mem.zeroes(@TypeOf(self.display));
}

fn execute(self: *Self, inst: u16) void {
    const hi = n1(inst);
    switch (hi) {
        0x0 => {
            if (n2(inst) == 0) {
                switch (b2(inst)) {
                    0xe0 => {
                        self.clear();
                    },
                    0xee => {
                        self.sp -= 1;
                        self.pc = self.stack[self.sp];
                    },
                    else => {},
                }
            } else {
                std.log.debug("ignore", .{});
            }
        },
        0x1 => {
            self.pc = addr(inst);
        },
        0x2 => {
            self.stack[self.sp] = self.pc;
            self.sp += 1;
            self.pc = addr(inst);
        },
        0x3 => {
            if (self.v[n2(inst)] == b2(inst)) {
                self.pc += 2;
            }
        },
        0x4 => {
            if (self.v[n2(inst)] != b2(inst)) {
                self.pc += 2;
            }
        },
        0x5 => {
            if (self.v[n2(inst)] == self.v[n3(inst)]) {
                self.pc += 2;
            }
        },
        0x6 => {
            self.v[n2(inst)] = b2(inst);
        },
        0x7 => {
            self.v[n2(inst)] +%= b2(inst);
        },
        0x8 => {
            const a = self.v[n2(inst)];
            const b = self.v[n3(inst)];
            var vf = self.v[0xf];
            const r = blk: switch (n4(inst)) {
                0x0 => {
                    break :blk b;
                },
                0x1 => {
                    break :blk a | b;
                },
                0x2 => {
                    break :blk a & b;
                },
                0x3 => {
                    break :blk a ^ b;
                },
                0x4 => {
                    const r: u16 = @as(u16, @intCast(a)) + @as(u16, @intCast(b));
                    vf = @intFromBool(r > 255);
                    break :blk b2(r);
                },
                0x5 => {
                    vf = @intFromBool(a >= b);
                    break :blk a -% b;
                },
                0x6 => {
                    vf = a & 0x1;
                    break :blk a >> 1;
                },
                0x7 => {
                    vf = @intFromBool(b >= a);
                    break :blk b -% a;
                },
                0xe => {
                    vf = a >> 7;
                    break :blk a << 1;
                },
                else => unreachable,
            };
            self.v[n2(inst)] = r;
            self.v[0xf] = vf;
        },
        0x9 => {
            if (self.v[n2(inst)] != self.v[n3(inst)]) {
                self.pc += 2;
            }
        },
        0xa => {
            self.I = addr(inst);
        },
        0xb => {
            self.pc = addr(inst) + self.v[0];
        },
        0xc => {
            self.v[n2(inst)] = rand() & b2(inst);
        },
        0xd => {
            const x = self.v[n2(inst)];
            const y = self.v[n3(inst)];
            const n = n4(inst);
            const sprite = self.mem[self.I .. self.I + n];
            // dumpSprite(sprite);
            self.draw(sprite, x, y);
        },
        0xe => {
            const val: u4 = @intCast(self.v[n2(inst)]);
            switch (b2(inst)) {
                0x9e => {
                    if (self.key[Keys.fromInt(val).index()]) {
                        self.pc += 2;
                    }
                },
                0xa1 => {
                    if (!self.key[Keys.fromInt(val).index()]) {
                        self.pc += 2;
                    }
                },
                else => unreachable,
            }
        },
        0xf => {
            switch (b2(inst)) {
                0x07 => {
                    self.v[n2(inst)] = self.dt;
                },
                0x0a => {
                    const key = self.waitKey();
                    self.v[n2(inst)] = key.index();
                },
                0x15 => {
                    self.dt = self.v[n2(inst)];
                },
                0x18 => {
                    self.st = self.v[n2(inst)];
                },
                0x1e => {
                    self.I += self.v[n2(inst)];
                },
                0x29 => {
                    const ch = self.v[n2(inst)];
                    self.I = ch * 5;
                },
                0x33 => {
                    const n = self.v[n2(inst)];
                    const hundreds = n / 100;
                    const rest = n % 100;
                    const tens = rest / 10;
                    const ones = rest % 10;
                    self.mem[self.I] = hundreds;
                    self.mem[self.I + 1] = tens;
                    self.mem[self.I + 2] = ones;
                },
                0x55 => {
                    const n = @as(u8, n2(inst)) + 1;
                    for (0..n) |i| {
                        self.mem[self.I + i] = self.v[i];
                    }
                },
                0x65 => {
                    const n = @as(u8, n2(inst)) + 1;
                    for (0..n) |i| {
                        self.v[i] = self.mem[self.I + i];
                    }
                },
                else => {
                    std.debug.print("unreachable 0x{x:02} at {}\n", .{ b2(inst), self.pc });
                },
            }
        },
    }
}

fn dumpSprite(sprite: []const u8) void {
    for (sprite) |line| {
        for (0..8) |i| {
            const one: u8 = 1;
            const sh = 7 - @as(u3, @intCast(i));
            const value = line & (one << sh) != 0;
            std.debug.print("{s}", .{if (value) "*" else " "});
        }
        std.debug.print("\n", .{});
    }
}

fn dumpDisplay(self: *Self) void {
    for (self.display, 0..) |pixel, pos| {
        std.debug.print("{s}", .{if (pixel) "*" else " "});
        if ((pos + 1) % display_width == 0) {
            std.debug.print("\n", .{});
        }
    }
}

fn dumpRegisters(self: *Self) void {
    for (self.v, 0..) |v, i| {
        std.log.debug("v{}: {}", .{ i, v });
    }
}

fn dumpKeys(self: *Self) void {
    var written = false;
    for (self.key, 0..) |k, i| {
        if (k) {
            const key: Keys = @enumFromInt(i);
            std.debug.print("{any} ", .{key});
            written = true;
        }
    }
    if (written)
        std.debug.print("\n", .{});
}

fn draw(self: *Self, sprite: []const u8, x: u8, y: u8) void {
    for (sprite, 0..) |line, i| {
        const pos = x + (y + i) * display_width;
        for (0..8) |j| {
            const index = pos + j;
            if (index >= self.display.len) break;
            const one: u8 = 1;
            const sh = 7 - @as(u3, @intCast(j));
            const value = line & (one << sh) != 0;
            const prev = self.display[index];
            self.v[0xf] = @intFromBool(prev and value == false);
            self.display[index] = prev ^ value;
        }
    }
    // self.dumpDisplay();
}

fn rand() u8 {
    return rnd.random().int(u8);
}

fn addr(inst: u16) u12 {
    return @intCast(inst & 0x0fff);
}

fn n1(inst: u16) u4 {
    return @intCast((inst & 0xf000) >> (4 * 3));
}

fn n2(inst: u16) u4 {
    return @intCast((inst & 0x0f00) >> (4 * 2));
}

fn n3(inst: u16) u4 {
    return @intCast((inst & 0x00f0) >> 4);
}

fn n4(inst: u16) u4 {
    return @intCast(inst & 0x000f);
}

fn b1(inst: u16) u8 {
    return @intCast((inst & 0xff00) >> 8);
}

fn b2(inst: u16) u8 {
    return @intCast(inst & 0x00ff);
}

fn fetchU16(self: *Self) !u16 {
    if (self.pc + 1 >= self.mem.len) {
        return error.Eof;
    }
    const high = self.mem[self.pc];
    const low = self.mem[self.pc + 1];
    self.pc += 2;
    return (@as(u16, high) << 8) | low;
}

test "helpers" {
    const value = 0x1234;
    std.debug.assert(n1(value) == 0x1);
    std.debug.assert(n2(value) == 0x2);
    std.debug.assert(n3(value) == 0x3);
    std.debug.assert(n4(value) == 0x4);

    std.debug.assert(b1(value) == 0x12);
    std.debug.assert(b2(value) == 0x34);

    std.debug.assert(addr(value) == 0x234);
}
