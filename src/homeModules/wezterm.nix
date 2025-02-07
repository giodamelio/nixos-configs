{ perSystem }: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;

    package = perSystem.self.wezterm-patched;

    extraConfig = ''
      return {
        font = wezterm.font("JetBrainsMono Nerd Font"),
        font_size = 12.0,
        harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }, -- Disable ligatures

        hide_tab_bar_if_only_one_tab = true,

        -- Work around
        -- See: https://github.com/NixOS/nixpkgs/issues/336069
        front_end = 'WebGpu',

        -- Minimize padding
        window_padding = {
          left = 0,
          right = 0,
          top = 0,
          bottom = 0,
        }
      }
    '';
  };
}
