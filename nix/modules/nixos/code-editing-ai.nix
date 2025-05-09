{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    aider-chat
    code-cursor
  ];
}
