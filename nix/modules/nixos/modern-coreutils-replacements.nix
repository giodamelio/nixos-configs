{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    fd # find
    procs # ps
    sd # sed
    du-dust # du
  ];
}
