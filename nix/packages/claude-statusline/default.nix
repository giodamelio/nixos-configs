{pkgs, ...}:
pkgs.writeShellApplication {
  name = "claude-statusline";
  # jj and starship come from the caller's PATH so they match the user's versions.
  runtimeInputs = with pkgs; [coreutils gnused jq natscli];
  runtimeEnv.CLAUDE_USAGE_NATS_URL = "nats://gallium.gio.ninja:4222";
  text = builtins.readFile ./claude-statusline.sh;
}
