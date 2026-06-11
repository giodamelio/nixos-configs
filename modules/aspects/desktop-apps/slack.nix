# slack — work chat. Converted from nix/modules/home/slack.nix.
_: {
  den.aspects.slack.homeManager = {pkgs, ...}: {
    home.packages = [
      pkgs.slack
    ];
  };
}
