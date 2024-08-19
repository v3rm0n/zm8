const SDL = @import("sdl2");

const texture_width = 320;
const texture_height = 240;

var dirty: bool = true;
var background_color: SDL.Color = SDL.Color.black;

const GUI = @This();

window: SDL.Window,
renderer: SDL.Renderer,
main_texture: SDL.Texture,
full_screen: bool,

pub fn init(full_screen: bool) !GUI {
    try SDL.init(SDL.InitFlags.everything);

    const window = try SDL.createWindow(
        "zm8",
        .{ .centered = {} },
        .{ .centered = {} },
        texture_width * 2,
        texture_height * 2,
        .{ .vis = .shown, .context = .opengl, .resizable = true, .dim = if (full_screen) .fullscreen else .default },
    );

    const renderer = try SDL.createRenderer(window, null, .{ .accelerated = true });
    try renderer.setLogicalSize(texture_width, texture_height);

    const main_texture = try SDL.createTexture(renderer, SDL.PixelFormatEnum.argb8888, SDL.Texture.Access.target, texture_width, texture_height);
    try renderer.setTarget(main_texture);

    try renderer.setColor(background_color);
    try renderer.clear();

    return GUI{ .window = window, .renderer = renderer, .main_texture = main_texture, .full_screen = full_screen };
}

pub fn toggleFullScreen(gui: GUI) void {
    gui.full_screen = !gui.full_screen;
    gui.window.setFullscreen(.{ .fullscreen = gui.full_screen });
    SDL.showCursor(true);
}

pub fn drawCharacter() void {}

pub fn render(gui: GUI) void {
    if (gui.dirty) {
        gui.dirty = 0;
        gui.renderer.setTarget(null);
        gui.renderer.setColorRGBA(gui.background_color);
        gui.renderer.clear();
        gui.renderer.copy(gui.main_texture, null, null);
        gui.renderer.present();
        gui.renderer.setTarget(gui.main_texture);
    }
}

pub fn destroy(gui: GUI) void {
    gui.window.destroy();
    gui.renderer.destroy();
    gui.main_texture.destroy();
    SDL.quit();
}
