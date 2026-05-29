/*
    odin-life — A beautiful, interactive Game of Life powered by raylib

    This is written to be read, played with, and learned from.
    The goal is to show you how Odin feels for real systems/graphics work.

    Why raylib? It has zero fuss bindings in Odin (vendor:raylib) and lets us
    focus on the interesting parts: data, simulation, and interaction.

    Build:  odin build . -out:life -o:minimal
    Run:    ./life
*/

package main

import "core:fmt"
import "core:mem"
import "core:math/rand"
import "core:strings"
import "core:time"

import rl "vendor:raylib"

// ============================================================================
// THE RULES — showing off Odin's excellent bit_set type
// ============================================================================

// Rules describes exactly when cells are born or survive.
// Using bit_set[0..=8] here is extremely elegant — membership test is one CPU instruction.
Rules :: struct {
    name:    string,
    birth:   bit_set[0..=8],
    survive: bit_set[0..=8],
}

RULESETS := [?]Rules{
    { "Conway's Life",  {3},     {2, 3} },
    { "HighLife",       {3, 6},  {2, 3} },
    { "Seeds",          {2},     {} },
    { "Day & Night",    {3,6,7,8}, {3,4,6,7,8} },
}

// ============================================================================
// THE WORLD — plain data, no objects, very Odin
// ============================================================================

World :: struct {
    width:   int,
    height:  int,
    cells:   []u8,      // 0 = dead, 1 = alive. Contiguous for cache friendliness.
    next:    []u8,      // Double buffer so we don't need a third "temp" grid

    rules:   ^Rules,    // Which ruleset is active right now

    // Simulation tuning
    paused:          bool,
    generations_per_tick: int,
    tick_rate:       f64,   // Target ticks per second when running

    // Camera (we can zoom and pan — very nice with raylib)
    camera:      rl.Camera2D,

    // Mouse painting state
    brush_size:  int,
    drawing:     bool,

    // History for the little HUD graph
    history:     [128]int,
    history_head:int,
}

// A pattern is just a list of relative coordinates.
Pattern :: [] [2]int

// Some famous patterns to stamp with keys or the UI
GLIDER      := Pattern{{0,1}, {1,2}, {2,0}, {2,1}, {2,2}}
PULSAR      := Pattern{
    {2,0},{3,0},{4,0}, {8,0},{9,0},{10,0},
    {0,2},{5,2},{7,2},{12,2}, {0,3},{5,3},{7,3},{12,3},
    {2,4},{3,4},{4,4},{8,4},{9,4},{10,4},
    {2,5},{3,5},{4,5},{8,5},{9,5},{10,5},
    {2,7},{3,7},{4,7},{8,7},{9,7},{10,7},
    {0,8},{5,8},{7,8},{12,8}, {0,9},{5,9},{7,9},{12,9},
    {2,10},{3,10},{4,10},{8,10},{9,10},{10,10},
}
R_PENTOMINO := Pattern{{0,0},{1,0},{1,1},{1,2},{2,1}}
GOSPER_GUN  := Pattern{
    {0,4},{1,4},{0,5},{1,5},
    {10,4},{10,5},{10,6},{11,3},{11,7},{12,2},{12,8},{13,2},{13,8},{14,5},
    {15,3},{15,7},{16,4},{16,5},{16,6},{17,5},
    {20,2},{20,3},{20,4},{21,2},{21,3},{21,4},{22,1},{22,5},
    {24,0},{24,1},{24,5},{24,6},
    {34,2},{34,3},{35,2},{35,3},
}

// ============================================================================
// WORLD OPERATIONS
// ============================================================================

make_world :: proc(w, h: int, allocator := context.allocator) -> ^World {
    world := new(World, allocator)
    world.width  = w
    world.height = h
    world.cells  = make([]u8, w*h, allocator)
    world.next   = make([]u8, w*h, allocator)
    world.rules  = &RULESETS[0]
    world.brush_size = 1
    world.generations_per_tick = 1
    world.tick_rate = 12

    // Nice starting camera — origin at center of the world, reasonable zoom
    world.camera = {
        target = {f32(w)*0.5, f32(h)*0.5},
        offset = {640, 360},           // Will be corrected on first resize
        zoom   = 8.0,
        rotation = 0,
    }

    return world
}

destroy_world :: proc(w: ^World) {
    delete(w.cells)
    delete(w.next)
    free(w)
}

// Convert 2D to flat index (row-major)
index :: proc(w: ^World, x, y: int) -> int {
    return y * w.width + x
}

// Safe cell access with optional toroidal wrapping (very useful for Life)
cell_at :: proc(w: ^World, x, y: int, wrap := true) -> u8 {
    if wrap {
        nx := (x % w.width + w.width) % w.width
        ny := (y % w.height + w.height) % w.height
        return w.cells[index(w, nx, ny)]
    }
    if x < 0 || y < 0 || x >= w.width || y >= w.height {
        return 0
    }
    return w.cells[index(w, x, y)]
}

// Count the 8 neighbors. Deliberately simple and readable.
count_neighbors :: proc(w: ^World, x, y: int) -> int {
    n := 0
    for dy in -1..=1 {
        for dx in -1..=1 {
            if dx == 0 && dy == 0 { continue }
            n += int(cell_at(w, x+dx, y+dy))
        }
    }
    return n
}

// Advance the simulation one generation using the classic double-buffer swap.
step :: proc(w: ^World) {
    for y in 0..<w.height {
        for x in 0..<w.width {
            n := count_neighbors(w, x, y)
            i := index(w, x, y)
            alive := w.cells[i] == 1

            next_state := false
            if alive {
                next_state = n in w.rules.survive
            } else {
                next_state = n in w.rules.birth
            }
            w.next[i] = 1 if next_state else 0
        }
    }
    w.cells, w.next = w.next, w.cells

    // Record population for the HUD graph
    pop := population(w)
    w.history[w.history_head] = pop
    w.history_head = (w.history_head + 1) % len(w.history)
}

population :: proc(w: ^World) -> int {
    p := 0
    for c in w.cells { p += int(c) }
    return p
}

// Fill with random living cells
randomize :: proc(w: ^World, density: f32 = 0.12) {
    for i in 0..<len(w.cells) {
        w.cells[i] = 1 if rand.float32() < density else 0
    }
}

clear_world :: proc(w: ^World) {
    for i in 0..<len(w.cells) { w.cells[i] = 0 }
}

// Stamp a pattern centered-ish at the given world coordinates
stamp :: proc(w: ^World, p: Pattern, cx, cy: int) {
    min_x, min_y := 0, 0
    max_x, max_y := 0, 0
    for c in p {
        min_x = min(min_x, c[0]); max_x = max(max_x, c[0])
        min_y = min(min_y, c[1]); max_y = max(max_y, c[1])
    }
    off_x := cx - (max_x + min_x) / 2
    off_y := cy - (max_y + min_y) / 2

    for c in p {
        x := off_x + c[0]
        y := off_y + c[1]
        if x >= 0 && x < w.width && y >= 0 && y < w.height {
            w.cells[index(w, x, y)] = 1
        }
    }
}

// Paint a circular brush of live cells under the mouse
paint :: proc(w: ^World, world_x, world_y: f32, radius: int, value: u8) {
    cx := int(world_x + 0.5)
    cy := int(world_y + 0.5)
    r2 := radius * radius

    for y in -radius..=radius {
        for x in -radius..=radius {
            if x*x + y*y > r2 { continue }
            px := cx + x
            py := cy + y
            if px >= 0 && px < w.width && py >= 0 && py < w.height {
                w.cells[index(w, px, py)] = value
            }
        }
    }
}

// ============================================================================
// RENDERING
// ============================================================================

// A pleasant dark theme (close to Catppuccin Mocha)
BG          :: rl.Color{ 30,  30,  46, 255}
GRID        :: rl.Color{ 69,  71,  90, 255}
ALIVE       :: rl.Color{137, 180, 250, 255}
ALIVE_OLD   :: rl.Color{137, 180, 250, 120}
CURSOR      :: rl.Color{245, 194, 231, 255}
UI_TEXT     :: rl.Color{205, 214, 244, 255}
UI_ACCENT   :: rl.Color{250, 179, 135, 255}
UI_MUTED    :: rl.Color{147, 153, 178, 255}

draw :: proc(w: ^World) {
    rl.BeginDrawing()
    defer rl.EndDrawing()

    rl.ClearBackground(BG)

    // Draw the grid using the camera transform
    rl.BeginMode2D(w.camera)
    defer rl.EndMode2D()

    // We draw cells as little rectangles. At high zoom we can afford more detail.
    cell_size := f32(1.0)

    // Simple visible range culling based on camera
    // (for a learning project we keep it simple — still plenty fast)
    for y in 0..<w.height {
        for x in 0..<w.width {
            if w.cells[index(w, x, y)] == 0 { continue }

            // Very subtle "age" coloring could be added with a second buffer.
            // For now we just use a nice solid color.
            c := ALIVE
            rl.DrawRectangleV({f32(x), f32(y)}, {cell_size, cell_size}, c)
        }
    }

    // Draw a very faint grid so you can count cells easily
    if w.camera.zoom > 4 {
        for x in 0..=w.width {
            rl.DrawLineV({f32(x), 0}, {f32(x), f32(w.height)}, GRID)
        }
        for y in 0..=w.height {
            rl.DrawLineV({0, f32(y)}, {f32(w.width), f32(y)}, GRID)
        }
    }

    // Draw brush preview (a faint circle)
    if w.drawing || !w.paused {
        mouse_world := rl.GetScreenToWorld2D(rl.GetMousePosition(), w.camera)
        r := f32(w.brush_size) + 0.5
        rl.DrawCircleLines(i32(mouse_world.x), i32(mouse_world.y), r, CURSOR)
    }
}

// Draw the HUD on top of the world (screen space)
draw_hud :: proc(w: ^World, fps: i32, dt: f64) {
    // Top bar
    rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 38, {0,0,0,160})
    rl.DrawTextEx(
        rl.GetFontDefault(),
        fmt.ctprintf("odin-life  •  %s", w.rules.name),
        {16, 10}, 18, 1, UI_ACCENT,
    )

    pop := population(w)
    paused_str := "PAUSED" if w.paused else "RUNNING"
    rl.DrawTextEx(
        rl.GetFontDefault(),
        fmt.ctprintf("%s  •  %d cells  •  %d fps", paused_str, pop, fps),
        {16, 28}, 14, 1, UI_MUTED,
    )

    // Right side controls reminder
    help := "[1-4] rule  [space] pause  [r] random  [click] paint  [wheel] zoom  [q] quit"
    c_help := strings.clone_to_cstring(help, context.temp_allocator)
    w_measure := rl.MeasureText(c_help, 14)
    rl.DrawTextEx(
        rl.GetFontDefault(),
        c_help,
        {f32(rl.GetScreenWidth() - w_measure - 16), 10},
        14, 1, UI_MUTED,
    )

    // Tiny population sparkline in bottom left
    draw_sparkline(w, 16, rl.GetScreenHeight()-60)
}

draw_sparkline :: proc(w: ^World, x, y: i32) {
    max_pop := w.width * w.height
    if max_pop <= 0 { return }

    rl.DrawText("pop", x, y-18, 12, UI_MUTED)

    for i in 0..<len(w.history) {
        val := w.history[(w.history_head + i) % len(w.history)]
        if val == 0 { continue }

        h := f32(val) / f32(max_pop) * 32
        c := ALIVE if i > len(w.history)-8 else UI_MUTED
        rl.DrawRectangle(x + i32(i)*2, y - i32(h), 1, i32(h), c)
    }
}

// ============================================================================
// INPUT & CAMERA
// ============================================================================

handle_input :: proc(w: ^World) -> (should_quit: bool) {
    // Quit
    if rl.IsKeyPressed(.Q) || rl.IsKeyPressed(.ESCAPE) {
        return true
    }

    // Pause / play
    if rl.IsKeyPressed(.SPACE) {
        w.paused = !w.paused
    }

    // Single step when paused
    if w.paused && rl.IsKeyPressed(.ENTER) {
        step(w)
    }

    // Ruleset switching
    if rl.IsKeyPressed(.ONE)   { w.rules = &RULESETS[0] }
    if rl.IsKeyPressed(.TWO)   { w.rules = &RULESETS[1] }
    if rl.IsKeyPressed(.THREE) { w.rules = &RULESETS[2] }
    if rl.IsKeyPressed(.FOUR)  { w.rules = &RULESETS[3] }

    // Quick actions
    if rl.IsKeyPressed(.R) {
        randomize(w, 0.09)
    }
    if rl.IsKeyPressed(.C) {
        clear_world(w)
    }

    // Famous patterns under the mouse
    mp := rl.GetScreenToWorld2D(rl.GetMousePosition(), w.camera)
    mx := int(mp.x)
    my := int(mp.y)

    if rl.IsKeyPressed(.G) { stamp(w, GLIDER, mx, my) }
    if rl.IsKeyPressed(.P) { stamp(w, PULSAR, mx, my) }
    if rl.IsKeyPressed(.X) { stamp(w, R_PENTOMINO, mx, my) }
    if rl.IsKeyPressed(.U) { stamp(w, GOSPER_GUN, mx, my) }

    // Brush size
    if rl.IsKeyPressed(.LEFT_BRACKET)  { w.brush_size = max(1, w.brush_size-1) }
    if rl.IsKeyPressed(.RIGHT_BRACKET) { w.brush_size = min(12, w.brush_size+1) }

    // Speed
    if rl.IsKeyPressed(.MINUS)  { w.tick_rate = max_f64(1, w.tick_rate - 2) }
    if rl.IsKeyPressed(.EQUAL)  { w.tick_rate = min_f64(120, w.tick_rate + 2) }

    // Mouse painting
    if rl.IsMouseButtonDown(.LEFT) {
        paint(w, mp.x, mp.y, w.brush_size, 1)
        w.drawing = true
    } else if rl.IsMouseButtonDown(.RIGHT) {
        paint(w, mp.x, mp.y, w.brush_size, 0)
        w.drawing = true
    } else {
        w.drawing = false
    }

    // Camera controls — this is where raylib shines
    // Zoom with mouse wheel
    wheel := rl.GetMouseWheelMove()
    if wheel != 0 {
        // Zoom toward mouse position (classic camera behavior)
        mouse_world := rl.GetScreenToWorld2D(rl.GetMousePosition(), w.camera)
        w.camera.zoom *= 1.0 + (wheel * 0.15)
        w.camera.zoom = clamp(w.camera.zoom, 0.5, 64.0)

        new_mouse_world := rl.GetScreenToWorld2D(rl.GetMousePosition(), w.camera)
        w.camera.target += (mouse_world - new_mouse_world)
    }

    // Pan with middle mouse or arrow keys
    if rl.IsMouseButtonDown(.MIDDLE) {
        delta := rl.GetMouseDelta() * (1.0 / w.camera.zoom)
        w.camera.target -= delta
    }

    // Keyboard panning (arrow keys / WASD)
    pan_speed := 40.0 / w.camera.zoom
    if rl.IsKeyDown(.LEFT)  || rl.IsKeyDown(.A) { w.camera.target.x -= pan_speed }
    if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) { w.camera.target.x += pan_speed }
    if rl.IsKeyDown(.UP)    || rl.IsKeyDown(.W) { w.camera.target.y -= pan_speed }
    if rl.IsKeyDown(.DOWN)  || rl.IsKeyDown(.S) { w.camera.target.y += pan_speed }

    return false
}

// ============================================================================
// MAIN LOOP
// ============================================================================

main :: proc() {
    // Nice window size for learning + playing
    SCREEN_W :: 1280
    SCREEN_H :: 720

    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(SCREEN_W, SCREEN_H, "odin-life — cellular automata in Odin")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    // We use a small arena for long-lived data and temp_allocator for per-frame work.
    // This pattern is extremely common and powerful in Odin.
    arena_data := make([]byte, 8*1024*1024)
    defer delete(arena_data)
    arena: mem.Arena
    mem.arena_init(&arena, arena_data)
    context.allocator = mem.arena_allocator(&arena)

    // A reasonably sized world for nice patterns (not too big for cache)
    WORLD_W :: 180
    WORLD_H :: 110

    world := make_world(WORLD_W, WORLD_H)
    defer destroy_world(world)

    // Seed with some interesting life
    stamp(world, GLIDER, 30, 20)
    stamp(world, R_PENTOMINO, 80, 40)
    randomize(world, 0.04)

    // Timing for fixed-tick simulation (important for reproducibility)
    sim_accumulator: f64 = 0
    last_time := rl.GetTime()

    for !rl.WindowShouldClose() {
        now := rl.GetTime()
        dt := now - last_time
        last_time = now

        // Handle input (returns true if user wants to quit)
        if handle_input(world) {
            break
        }

        // Fixed-tick simulation (classic game loop pattern)
        if !world.paused {
            sim_accumulator += dt
            tick_interval := 1.0 / world.tick_rate
            steps := 0
            for sim_accumulator >= tick_interval && steps < 8 {
                for _ in 0..<world.generations_per_tick {
                    step(world)
                }
                sim_accumulator -= tick_interval
                steps += 1
            }
        }

        // Update camera offset when window is resized
        world.camera.offset = {f32(rl.GetScreenWidth()) * 0.5, f32(rl.GetScreenHeight()) * 0.5}

        // Draw everything
        draw(world)
        draw_hud(world, rl.GetFPS(), dt)

        // Extremely important: free everything that used temp_allocator this frame.
        // This is one of the things that makes Odin feel so good for real-time code.
        free_all(context.temp_allocator)
    }

    fmt.println("Thanks for exploring cellular automata with Odin!")
}

// Small helpers
min :: proc(a, b: int) -> int { return a if a < b else b }
max :: proc(a, b: int) -> int { return a if a > b else b }
clamp :: proc(x, lo, hi: $T) -> T { return lo if x < lo else hi if x > hi else x }

min_f64 :: proc(a, b: f64) -> f64 { return a if a < b else b }
max_f64 :: proc(a, b: f64) -> f64 { return a if a > b else b }
