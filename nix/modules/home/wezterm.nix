{ perSystem, ... }: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    package = perSystem.nixpkgs-stable.wezterm;

    extraConfig = ''
      local action = wezterm.action
      local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")
      local smart_splits = wezterm.plugin.require('https://github.com/mrjones2014/smart-splits.nvim')

      local config = wezterm.config_builder()

      -- config.window_decorations = 'NONE'

      -- Color Scheme
      config.color_scheme = 'Molokai'

      -- Font Setup
      config.font = wezterm.font("JetBrainsMono Nerd Font")
      config.font_size = 12.0
      config.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' } -- Disable ligature

      config.hide_tab_bar_if_only_one_tab = false
      config.use_fancy_tab_bar = true

      -- TODO: Update this when there is highlighting support
      -- See: https://github.com/wezterm/wezterm/issues/4077
      config.hyperlink_rules = wezterm.default_hyperlink_rules()

        -- Minimize padding
      config.window_padding = {
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
      }

      -- Show scroll bar
      config.enable_scroll_bar = true

      -- Keep more scrollback lines
      config.scrollback_lines = 6000

      -- Key Bindings
      config.keys = {
        { key = 'l', mods = 'ALT', action = wezterm.action.ShowLauncher },
      }

      -- Make Mouse scrolling smaller then a page
      config.mouse_bindings = {
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

      -- bar.apply_to_config(config)
      tabline.setup({
        options = {
          icons_enabled = true,
          tabs_enabled = true,
          theme_overrides = {},
          section_separators = {
            left = wezterm.nerdfonts.pl_left_hard_divider,
            right = wezterm.nerdfonts.pl_right_hard_divider,
          },
          component_separators = {
            left = wezterm.nerdfonts.pl_left_soft_divider,
            right = wezterm.nerdfonts.pl_right_soft_divider,
          },
          tab_separators = {
            left = ''\'',
            right = ''\'',
          },
        },
        sections = {
          tabline_a = { 'workspace' },
          tabline_b = { 'window' },
          tabline_c = { },
          tab_active = {
            'index',
            { 'parent', padding = 0 },
            '/',
            { 'cwd', padding = { left = 0, right = 1 } },
            { 'zoomed', padding = 0 },
          },
          tab_inactive = { 'index', { 'process', padding = { left = 0, right = 1 } } },
          tabline_x = { },
          tabline_y = { },
          tabline_z = { 'hostname' },
        },
        extensions = {},
      })

      -- tabline.apply_to_config(config)

      smart_splits.apply_to_config(config, {
        direction_keys = { 'h', 'j', 'k', 'l' },
        modifiers = {
          move = 'CTRL',
          resize = 'META',
        },
      })

      return config
    '';
  };
}
