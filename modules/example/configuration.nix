{ ... }:
{
  # Identity
  networking.hostName = "oracle-nix";
  time.timeZone = "Europe/London";

  # Primary user
  # NB: The oci-image module ALSO provides fetch-ssh-keys which gets
  # keys from OCI instance metadata at boot.
  oracle-nix.user = "nixci";
  oracle-nix.authorizedKeys = [
    # ADD YOUR PUBLIC KEY(S):
    # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB... user@host"
  ];

  # Can be extended with other rules, eg.., for the firewall, other users,
  # and all other Nix stuff.
}
