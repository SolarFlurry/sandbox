# sandbox

Sandboxes are cool.

---

This project is a 2D sandbox engine/simulation.

## Goals
- Customisable: easy to add new materials with custom behavior as well as changing the rendering for them.
- Performant: maintains as low tick time as possible, within a cap
- Aesthetically pleasing: supports shaders for materials and all materials look cool.

## Contributing
Either fork and PR or clone and push:
```sh
git clone https://github.com/SolarFlurry/sandbox.git
```

### Dependencies

- [Zig compiler](https://codeberg.org/ziglang/zig)

### Build and run

```sh
# build debug
zig build
# build release
zig build --release=fast

./zig-out/bin/sandbox
```
