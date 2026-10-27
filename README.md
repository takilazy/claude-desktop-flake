# claude-desktop-flake

A Nix flake that repackages Anthropic's official **Claude Desktop for Linux**
`.deb` (from the [apt repository][docs]) into a self-contained Nix derivation —
no `apt`, no impurity.

The bundled Electron/Chromium binaries and native helpers (`node-pty`,
`claude-native`, `virtiofsd`) are patched against Nix libraries with
`autoPatchelfHook`, and launched through a `makeWrapper` shim.

Supports `x86_64-linux` and `aarch64-linux`, matching the architectures
Anthropic publishes.

> Claude Desktop is proprietary software. This flake only repackages the
> official build; the package is marked `unfree`, so enable `allowUnfree`.

## Quick start

```bash
# Run it directly (needs allowUnfree):
NIXPKGS_ALLOW_UNFREE=1 nix run --impure github:takilazy/claude-desktop-flake

# Or build it:
nix build github:takilazy/claude-desktop-flake#claude-desktop
```

## Use it in a flake-based NixOS config

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    claude-desktop.url = "github:takilazy/claude-desktop-flake";
    claude-desktop.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, claude-desktop, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        claude-desktop.nixosModules.default
        {
          nixpkgs.config.allowUnfree = true;
          programs.claude-desktop.enable = true; # installs the app + .desktop entry
        }
      ];
    };
  };
}
```

### Or just add the package

```nix
# with the overlay
nixpkgs.overlays = [ claude-desktop.overlays.default ];
environment.systemPackages = [ pkgs.claude-desktop ];

# or reference the output directly
environment.systemPackages = [ claude-desktop.packages.${pkgs.system}.default ];
```

## Notes

- **Sandbox** — the store copy of `chrome-sandbox` can't be setuid-root, so it's
  removed; Chromium falls back to its unprivileged user-namespace sandbox, which
  NixOS enables by default (the module makes that dependency explicit). No
  `--no-sandbox` weakening required.
- **Updates** — the desktop app doesn't self-update on Linux. A daily GitHub
  Actions workflow checks the apt indexes and commits new versions automatically.
  To update manually, run `python3 scripts/update-package.py`. The metadata comes
  from:
  `https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-{amd64,arm64}/Packages`.
- **What's not in the Linux beta** — Computer Use, dictation, and (on native
  Wayland) the Quick Entry global hotkey. See the [docs][docs].

[docs]: https://code.claude.com/docs/en/desktop-linux
