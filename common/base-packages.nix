{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.vim
    pkgs.git
    pkgs.lshw
  ];
}
