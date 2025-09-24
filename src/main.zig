const std = @import("std");
const sdl3 = @import("sdl3");
const VM = @import("VM.zig");

const Allocator = std.mem.Allocator;

var allocator: Allocator = undefined;

fn loadRom(name: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(name, .{});

    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

fn sdlErrCallback(err: ?[:0]const u8) void {
    if (err) |e| {
        std.log.err("SDL error: {s}", .{e});
    } else {
        std.log.err("SDL error", .{});
    }
}

pub fn main() !void {
    try sdl3.init(.{ .video = true, .events = true });
    defer sdl3.quit(.{ .video = true, .events = true });

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const name = std.fs.path.basename(args.next().?);

    const rom_path = args.next() orelse {
        std.debug.print("Not enough arguments.\nUsage: {s} <path to rom>\n", .{name});
        return;
    };

    var width: usize = 640;
    var height: usize = 320;
    var scale: f32 = 0.0;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-w")) {
            if (args.next()) |a| {
                width = try std.fmt.parseInt(usize, a, 0);
            }
        } else if (std.mem.eql(u8, arg, "-h")) {
            if (args.next()) |a| {
                height = try std.fmt.parseInt(usize, a, 0);
            }
        } else if (std.mem.eql(u8, arg, "-s")) {
            if (args.next()) |a| {
                scale = try std.fmt.parseFloat(f32, a);
            }
        } else if (std.mem.eql(u8, arg, "-d")) {
            if (args.next()) |a| {
                var iter = std.mem.splitScalar(u8, a, 'x');
                const wd = iter.next() orelse return error.ExpectedWidth;
                const hd = iter.next() orelse return error.ExpectedHeight;
                width = try std.fmt.parseInt(usize, wd, 0);
                height = try std.fmt.parseInt(usize, hd, 0);
            }
        }
    }

    width = @intFromFloat(@as(f32, @floatFromInt(width)) * scale);
    height = @intFromFloat(@as(f32, @floatFromInt(height)) * scale);

    const window = try sdl3.video.Window.init("App", width, height, .{});
    defer window.deinit();

    sdl3.errors.error_callback = sdlErrCallback;
    const rom = try loadRom(rom_path);
    defer allocator.free(rom);

    var vm = VM.init(allocator, rom, window);

    try vm.run();
}
