{
  description = "Exemplar NixOS config for OCI (Ampere A1)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    oracle-nix.url = "github:encore-sr/oracle-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      oracle-nix,
      ...
    }:
    {
      nixosConfigurations.oracle-nix = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
          oracle-nix.nixosModules.oci-base
          ./configuration.nix
        ];
      };

      # For building: nix build .#oracle-nix-image
      packages.aarch64-linux.oracle-nix-image =
        self.nixosConfigurations.oracle-nix.config.system.build.OCIImage;
      packages.x86_64-linux.oracle-nix-image = self.packages.aarch64-linux.oracle-nix-image;
    };
}
