{ pkgs, ... }: {
  programs.rbw = {
    enable = true;
    settings = {
      email = "giodamelio@gmail.com";
    };
  };

  home.packages = with pkgs; [
    bitwarden-cli
  ];
}
