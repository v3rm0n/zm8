const std = @import("std");
const SDL = @import("sdl2");
const Font = @import("font.zig");

const FxCube = @This();

const default_nodes: [8][3]f32 = [8]f32{
    [3]f32{ -1, -1, -1 },
    [3]f32{ -1, -1, 1 },
    [3]f32{ -1, 1, -1 },
    [3]f32{ -1, 1, 1 },
    [3]f32{ 1, -1, -1 },
    [3]f32{ 1, -1, 1 },
    [3]f32{ 1, 1, -1 },
    [3]f32{ 1, 1, 1 },
};

var edges: [12][2]u32 = [12]u32{
    [2]u32{ 0, 1 },
    [2]u32{ 1, 3 },
    [2]u32{ 3, 2 },
    [2]u32{ 2, 0 },
    [2]u32{ 4, 5 },
    [2]u32{ 5, 7 },
    [2]u32{ 7, 6 },
    [2]u32{ 6, 4 },
    [2]u32{ 0, 4 },
    [2]u32{ 1, 5 },
    [2]u32{ 2, 6 },
    [2]u32{ 3, 7 },
};

var nodes: [8][3]f32 = undefined;
var center_x: usize = 320 / 2;
var center_y: usize = 240 / 2;

cube: SDL.Texture,
text: SDL.Texture,
renderer: SDL.Renderer,
line_color: SDL.Color,

pub fn init(renderer: SDL.Renderer, foreground_color: SDL.Color, font: Font) FxCube {
    const target = renderer.getTarget() orelse unreachable;

    const info = try target.query();

    const cube = try SDL.createTexture(renderer, .abgr8888, .target, info.width, info.height);
    const text = try SDL.createTexture(renderer, .abgr8888, .target, info.width, info.height);

    renderer.setTarget(text);
    renderer.setColorRGBA(0, 0, 0, 0xFF);
    renderer.clear();

    //Write text
    font.drawText(
        renderer,
        "DEVICE DISCONNECTED",
        .{ .x = info.width - font.inline_font.glyph_x * 19 - 21, .y = info.height - 12 },
        .black,
        .white,
    );
    font.drawText(
        renderer,
        "ZM8",
        .{ .x = 2, .y = 2 },
        .black,
        .white,
    );

    renderer.setTarget(target);
    @memcpy(nodes, default_nodes);

    scale(50, 50, 50);
    rotate(std.math.pi / 6, std.math.atan(std.math.sqrt(2)));

    cube.setBlendMode(.blend);
    text.setBlendMode(.blend);

    center_x = info.width / 2.0;
    center_y = info.height / 2.0;

    return .{ .cube = cube, .text = text, .renderer = renderer, .line_color = foreground_color };
}

fn scale(factor0: f32, factor1: f32, factor2: f32) void {
    for (nodes) |node| {
        node[0] *= factor0;
        node[1] *= factor1;
        node[2] *= factor2;
    }
}

fn rotate(angle_x: f32, angle_y: f32) void {
    const sin_x = std.math.sin(angle_x);
    const cos_x = std.math.cos(angle_x);
    const sin_y = std.math.sin(angle_y);
    const cos_y = std.math.cos(angle_y);
    for (nodes) |node| {
        const x = node[0];
        const y = node[1];
        const z = node[2];

        node[0] = x * cos_x - z * sin_x;
        node[2] = z * cos_x + x * sin_x;

        z = node[2];

        node[1] = y * cos_y - z * sin_y;
        node[2] = z * cos_y + y * sin_y;
    }
}

pub fn update(self: FxCube) void {
    var points: [24]SDL.Point = undefined;
    var points_counter = 0;
    const og_texture = self.renderer.getTarget();

    self.renderer.setTarget(self.cube);
    self.renderer.setColorRGBA(0, 0, 0, 0xFF);
    self.renderer.clear();

    const seconds: u32 = SDL.getTicks() / 1000;
    const scalefactor: f32 = 1 + std.math.sin(seconds) * 0.005;

    scale(scalefactor, scalefactor, scalefactor);
    rotate(std.math.pi / 180, std.math.pi / 270);

    for (0..12) |i| {
        const p1 = nodes[edges[i][0]];
        const p2 = nodes[edges[i][1]];
        points_counter += 1;
        points[points_counter] = .{ p1[0] + center_x, nodes[edges[i][0]][1] + center_y };
        points_counter += 1;
        points[points_counter] = .{ p2[0] + center_x, p2[1] + center_y };
    }

    self.renderer.copy(self.text, null, null);
    self.renderer.setColor(self.line_color);
    self.renderer.drawLines(points);

    self.renderer.setTarget(og_texture);
    self.renderer.copy(self.text, null, null);
}

pub fn deinit(self: FxCube) void {
    self.cube.destroy();
    self.text.destroy();
}
