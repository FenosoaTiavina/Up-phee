pub const sdl = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_gpu.h");
    @cInclude("SDL3/SDL_pixels.h");
    @cInclude("SDL3/SDL_video.h");
    @cInclude("SDL3/SDL_vulkan.h");
});
pub const stb = @cImport({
    @cInclude("stb/stb_image.h");
});
