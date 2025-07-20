_: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;

    extraConfig = ''
      return {
        font = wezterm.font("JetBrainsMono Nerd Font"),
        font_size = 12.0,
        harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }, -- Disable ligatures

        hide_tab_bar_if_only_one_tab = true,

        -- TODO: Update this when there is highlighting support
        -- See: https://github.com/wezterm/wezterm/issues/4077
        hyperlink_rules = wezterm.default_hyperlink_rules(),

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
