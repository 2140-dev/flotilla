{
  description = "2140.dev fleet — host configurations consuming roost";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    roost.url = "github:2140-dev/roost";
    roost.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      agenix,
      roost,
    }:
    let
      # Per-host extras let us scope opinionated modules (roost's
      # batteries-included default) to the host that actually uses them,
      # rather than carrying their assertions on every host.
      mkHost =
        name: extraModules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            agenix.nixosModules.default
            roost.nixosModules.hetzner-bare-metal
            ./modules/common.nix
            ./hosts/${name}
          ]
          ++ extraModules;
        };

      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      forAllLinux = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      nixosConfigurations = {
        finney = mkHost "finney" [ ];
        kingfisher = mkHost "kingfisher" [ roost.nixosModules.default ];
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixos-rebuild
              pkgs.nixos-anywhere
              agenix.packages.${system}.default
            ];
          };
        }
      );

      # Build every host's toplevel as a flake check. Surfaces eval errors
      # and module-composition mistakes; runs natively wherever invoked.
      checks = forAllLinux (system: {
        finney = self.nixosConfigurations.finney.config.system.build.toplevel;
        kingfisher = self.nixosConfigurations.kingfisher.config.system.build.toplevel;
      });
    };
}
