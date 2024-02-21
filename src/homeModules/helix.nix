{
  root,
  debug,
  ...
}: {pkgs, ...}: {
  programs.helix = {
    enable = true;
    settings = {
      theme = "tokyonight_storm";
    };
  };
}
