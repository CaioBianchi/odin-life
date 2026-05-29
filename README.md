# odin-life

A beautiful, interactive, zoomable Game of Life (and friends) written in Odin using raylib.

> This project was created as a delightful way to learn Odin by doing something genuinely fun.

## Why this exists

Most language tutorials stop at "print hello". This one gives you:

- A complete, real-time simulation with proper fixed-tick game loop
- Clean data-oriented design (just slices of bytes + procedures)
- Odin's fantastic `bit_set` used for elegant, fast CA rules
- Excellent use of `vendor:raylib` (one of the best parts of the Odin ecosystem)
- Camera, mouse painting, keyboard patterns — the kind of interactivity that makes you want to experiment
- Heavy, friendly comments explaining both the algorithm and the language features

## Features

- **Four rulesets** hot-swappable with 1–4 keys:
  - Conway's Life (the classic)
  - HighLife (has replicators!)
  - Seeds (chaotic, everything dies)
  - Day & Night (gorgeous organic patterns)
- **Infinite zoom & pan** with mouse wheel + middle mouse / WASD / arrows
- **Live painting** with left/right mouse (different brush sizes with `[` `]`)
- **Famous patterns** at your cursor: `G` (glider), `P` (pulsar), `X` (R-pentomino), `U` (Gosper glider gun)
- **Randomize**, clear, pause, single-step
- **Population sparkline** in the corner so you can see stability at a glance
- Resizable window, VSync, 60 fps smooth

## Getting started

### Prerequisites

Odin + raylib (both come together via Homebrew on macOS):

```fish
mise use odin
```

This installs raylib as well and wires everything up.

### Build & run

```fish
cd odin-life
odin build . -out:life -o:minimal
./life
```

For development (better debug info, slower binary):

```fish
odin build . -out:life -debug
```

## Controls

| Input                    | Action                     |
| ------------------------ | -------------------------- |
| `1` `2` `3` `4`          | Switch ruleset             |
| `Space`                  | Pause / unpause            |
| `Enter` (when paused)    | Step one generation        |
| Left / Right click       | Paint live / dead cells    |
| Mouse wheel              | Zoom (centers on cursor)   |
| Middle mouse drag        | Pan                        |
| `W` `A` `S` `D` / arrows | Pan                        |
| `[` `]`                  | Smaller / larger brush     |
| `-` `=`                  | Slower / faster simulation |
| `G`                      | Stamp a glider             |
| `P`                      | Stamp a pulsar             |
| `X`                      | Stamp an R-pentomino       |
| `U`                      | Stamp a Gosper glider gun  |
| `R`                      | Random soup                |
| `C`                      | Clear the world            |
| `Q` or `Esc`             | Quit                       |

## Learning the language through this code

Read the file in roughly this order:

1. **The `Rules` struct + `RULESETS`** — see how `bit_set[0..=8]` makes cellular automata rules almost declarative.
2. **`World` struct** — notice there are no classes, no vtables, just plain data. This is data-oriented design.
3. **`step()`** — the double-buffer swap and neighbor counting. Dead simple, very fast.
4. **Input handling** — see how raylib makes mouse + camera interaction trivial.
5. **The main loop** — fixed timestep accumulator + `free_all(context.temp_allocator)` every frame. This pattern is pure Odin joy.
6. **Camera math** — zooming toward the mouse cursor is only a few lines.

## Experiments to try (highly recommended)

**Beginner**

- Add a fifth ruleset (search "Life-like cellular automata" on Wikipedia)
- Change the starting density or initial patterns
- Make the brush leave "embers" (cells that stay alive for a few frames)

**Intermediate**

- Add a "heatmap" mode that colors cells by how long they've been alive
- Implement copy/paste of rectangular regions
- Make the simulation wrap in only one axis (cylinder world)

**Advanced (you will learn a ton)**

- Implement **Hashlife** (Gosper's insanely fast algorithm for huge sparse patterns)
- Add a second simulation layer (e.g. simple "predator" particles that eat live cells)
- Add recording: dump frames to disk as images or a `.gif`
- Make the camera smoothly follow large moving patterns (like the glider gun)

## Project structure

```
odin-life/
├── main.odin     # Everything lives here (deliberately)
├── README.md
└── .gitignore
```

One file. No hidden magic. Read it, change it, break it, understand it.

## Further reading

- [Odin documentation](https://odin-lang.org/docs/)
- [vendor:raylib source](https://github.com/odin-lang/Odin/blob/master/vendor/raylib/raylib.odin) — the bindings are tiny and readable
- [ConwayLife.com](https://www.conwaylife.com/) — the greatest collection of patterns and knowledge
- The `demo/` folder that ships with Odin (`odin build $ODIN_ROOT/examples/demo`)

---

Enjoy playing with little pixels that make other pixels. That's the whole game.
