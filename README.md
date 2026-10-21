# oracle-nix

NixOS module for Oracle Cloud Infrastructure (Ampere A1).

## Quick start (for users)

```bash
# 1. Create your own repo from the example:
git clone https://github.com/encore-sr/oracle-nix my-oracle-nix
cd my-oracle-nix
cp -r modules/example my-config
# Edit my-config/configuration.nix with your settings

# 2. Build the qcow2 locally:
#   ./scripts/build-image.sh

# 3. Import into OCI (one-time):
nix run github:encore-sr/oracle-nix#import-tools -- scripts/import-image.py result/nixos-image-oci-*.qcow2
# -> prints IMAGE_ID=ocid1.image...

# 4. The image will now be available under "My Images - Custom" via "Custom images"
# Use it to create an instance as you normally would.

# 5. SSH in and update as normal:
nixos-rebuild switch --flake .#oracle-nix --target-host ubuntu@<public-ip>
```
