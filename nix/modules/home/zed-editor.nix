_: {
  programs.zed-editor = {
    enable = true;
    installRemoteServer = true;
    extensions = [
      "nix"
      "rust"
    ];
  };
}
