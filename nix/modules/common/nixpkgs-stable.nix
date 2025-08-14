{
  inputs,
  pkgs,
  ...
}: {
  _module.args.pkgsStable = import inputs.nixpkgs-stable {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
}
