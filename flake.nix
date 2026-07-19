{
  description = "Claude Desktop for Linux, repackaged from Anthropic's official .deb";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # Supported systems match the .deb architectures Anthropic publishes.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # nix build / nix run .#claude-desktop
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          claude-desktop = pkgs.callPackage ./package.nix { };
        in
        {
          inherit claude-desktop;
          default = claude-desktop;
        }
      );

      # nix run .  (launches the app)
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/claude-desktop";
        };
      });

      # Overlay so you can pull the package into an existing nixpkgs.
      overlays.default = final: prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };

      # NixOS module: enable with
      #   imports = [ inputs.claude-desktop.nixosModules.default ];
      #   programs.claude-desktop.enable = true;
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.claude-desktop;
        in
        {
          options.programs.claude-desktop = {
            enable = lib.mkEnableOption "Claude Desktop";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.claude-desktop;
              description = "The claude-desktop package to use.";
            };
          };
          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
            # Chromium's namespace sandbox needs unprivileged user namespaces,
            # which NixOS enables by default; make the dependency explicit.
            security.unprivilegedUsernsClone = lib.mkDefault true;
          };
        };
    };
}
