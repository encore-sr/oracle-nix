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

      nixosConfigurations.oracle-nix-image = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          self.nixosModules.oci-base
          ./example/configuration.nix
          # Override the OCIImage derivation to use our configuration instead of oci-config-user.nix
          (
            {
              config,
              lib,
              pkgs,
              ...
            }:
            {
              system.build.OCIImage = lib.mkForce (
                import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
                  inherit config lib pkgs;
                  diskSize = config.virtualisation.diskSize or (8 * 1024);
                  name = "oci-image";
                  baseName = config.image.baseName or "nixos-image-oci";
                  configFile = ./example/configuration.nix;
                  format = "qcow2";
                  partitionTableType = if config.oci.efi then "efi" else "legacy";
                }
              );
            }
          )
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
          oracle-nix-image = self.nixosConfigurations.oracle-nix-image.config.system.build.OCIImage;
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
