_: {
  pkgs,
  lib,
  ...
}: {
  nixpkgs.config = {
    allowUnfreePredicate = pkg: (builtins.elem (lib.getName pkg) [
      "obsidian"
    ]);
  };
  environment = {
    systemPackages = with pkgs; [
      bitwarden-cli
      bitwarden-menu
      thunderbird
      obsidian
    ];
  };
}
