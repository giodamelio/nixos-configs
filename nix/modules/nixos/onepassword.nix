{
  flake,
  pkgs,
  ...
}: let
  inherit (flake.packages.${pkgs.stdenv.system}) sync-1password-secrets;
in {
  # Password manager
  programs._1password = {
    enable = true;
  };

  environment.systemPackages = [
    sync-1password-secrets
  ];
}
