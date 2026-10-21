# oci-base provides a minimal base for custom NixOS images on Oracle Cloud
# Infrastructure. Use it with nixpkgs' virtualisation/oci-image.nix (which
# provides the qcow2 builder, UEFI ESP layout, partition growth, serial
# console kernel params, and the qemu-guest profile: virtio drivers + DHCP).
#
# This module only does what the stock module doesn't:
#   - SSH hardening.
#   - a configurable user with authorised keys.
#   - Oracle's metadata-service NTP with public fallback.
#   - a default-allow-SSH firewall.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.oracle-nix;
in
{
  options.oracle-nix = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "nixci";
      description = "Primary login user for the image.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        SSH public keys added into the primary user's authorized_keys.
        These are public keys that are used as a fallback on top of
        the oci-image module's fetch-ssh-keys (which gets keys from the
        instance metadata service at boot).
      '';
    };
  };

  config = {
    users.mutableUsers = false;

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitEmptyPasswords = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    # Oracle guideline G06: use the OCI NTP service (metadata service IP).
    services.timesyncd = {
      enable = true;
      servers = [ "169.254.169.254" ];
      fallbackServers = [ "pool.ntp.org" ];
    };

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };

    # systemd-networkd config: OCI paravirtualized NIC (typically ens3) via DHCP
    networking.useNetworkd = true;
    systemd.network.networks."10-eth" = {
      matchConfig = {
        Name = "ens*";
        Type = "ether";
      };
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
    };

    users.users.${cfg.user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      # No password set => account locked => SSH key-only (guideline S16).
    };
    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      btop
      curl
      fastfetch
      git
      helix
      rsync
    ];

    # Use systemd-based initrd (faster, supports luks/dm-crypt etc)
    boot.initrd.systemd.enable = true;
    documentation.enable = false;

    system.stateVersion = lib.mkDefault "26.05";
  };
}
