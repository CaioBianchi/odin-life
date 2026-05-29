# Simple, friendly build system for odin-life
# Works on macOS with Odin installed via Homebrew

ODIN := odin
BINARY := life

# Development build (with debug info, no optimization)
debug:
	$(ODIN) build . -out:$(BINARY) -debug

# Fast release build
release:
	$(ODIN) build . -out:$(BINARY) -o:speed

# Minimal binary (good default for this kind of program)
build:
	$(ODIN) build . -out:$(BINARY) -o:minimal

# Run after building
run: build
	./$(BINARY)

# Clean build artifacts
clean:
	rm -f $(BINARY)
	rm -rf build/

.PHONY: debug release build run clean
