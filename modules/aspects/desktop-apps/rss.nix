# rss — NewsFlash feed reader. Converted from nix/modules/home/rss.nix.
_: {
  den.aspects.rss.homeManager = {pkgs, ...}: {
    home.packages = [
      pkgs.newsflash
    ];
  };
}
