{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.vim
    pkgs.git
  ];
}
