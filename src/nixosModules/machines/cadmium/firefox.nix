_: {pkgs, ...}: {
  environment = {
    systemPackages = with pkgs; [
      firefox
    ];
  };
}
