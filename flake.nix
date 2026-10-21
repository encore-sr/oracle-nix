{
  description = "NixOS module for OCI (Ampere A1)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forSystems = lib.genAttrs systems;
    in
    {
      # Reusable modules for anyone needing NixOS on OCI Ampere A1.
      # Import alongside nixpkgs' virtualisation/oci-image.nix and set
      # oracle-nix.authorizedKeys.
      #
      # Example:
      #   imports = [
      #     "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
      #     inputs.oracle-nix.nixosModules.oci-base
      #   ];
      nixosModules = {
        default = self.nixosModules.oci-base;
        oci-base = import ./modules/oci-base.nix;
      };

      # Example configuration: builds a minimal NixOS qcow2 for OCI A1.
      # Users should fork this repo and replace ./modules/example/configuration.nix
      # with their own configuration.
      nixosConfigurations.oracle-nix = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          self.nixosModules.oci-base

          ./modules/example/configuration.nix
        ];
      };

      # Packages for both systems so `nix build .#oracle-nix-image` works everywhere
      # with `extra-platforms = aarch64-linux` configured.
      packages = forSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          oracle-nix-image = self.nixosConfigurations.oracle-nix.config.system.build.OCIImage;
          default = self.packages.${system}.oracle-nix-image;

          import-tools = pkgs.python3.withPackages (
            ps: with ps; [
              oci
              requests
            ]
          );
        }
      );

      formatter = forSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
