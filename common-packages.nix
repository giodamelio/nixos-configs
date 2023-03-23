{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.vim
  ];
}
