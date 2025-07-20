_: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;

    extraConfig = ''
      local action = wezterm.action

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
        },

        -- Show scroll bar
        enable_scroll_bar = true,

        -- Keep more scrollback lines
        scrollback_lines = 6000;

        -- Make Mouse scrolling smaller then a page
        mouse_bindings = {
          {
            event = { Down = { streak = 1, button = { WheelUp = 1 } } },
            mods = 'NONE',
            action = action.ScrollByLine(-3),
          },
          {
            event = { Down = { streak = 1, button = { WheelDown = 1 } } },
            mods = 'NONE',
            action = action.ScrollByLine(3),
          },
        }
      }
    '';
  };
}
