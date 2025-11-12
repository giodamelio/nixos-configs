{perSystem, ...}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    package = perSystem.nixpkgs-stable.wezterm;

    extraConfig = ''
      local io = require 'io'
      local os = require 'os'

      local wezterm = require 'wezterm'
      local action = wezterm.action
      local smart_splits = wezterm.plugin.require('https://github.com/mrjones2014/smart-splits.nvim')

      local config = wezterm.config_builder()

      -- Color Scheme
      config.color_scheme = 'Molokai'

      -- Font Setup
      config.font = wezterm.font_with_fallback({
        "JetBrainsMono Nerd Font Mono",
        -- "Inconsolata Nerd Font",
        "Symbols Nerd Font Mono",
        "Noto Sans Mono",
        "Noto Sans Symbols",
        "Noto Sans Symbols 2",
      })
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
        {
          key = 'E',
          mods = 'CTRL',
          action = action.EmitEvent 'trigger-vim-with-scrollback',
        },
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

      -- Windows only settings
      if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
        -- Load NixOS WSL2 by default
        config.default_domain = 'WSL:NixOS'
      end

      smart_splits.apply_to_config(config, {
        direction_keys = { 'h', 'j', 'k', 'l' },
        modifiers = {
          move = 'CTRL',
          resize = 'META',
        },
      })

      -- Allow opening the whole scrollback in vim
      wezterm.on('trigger-vim-with-scrollback', function(window, pane)
        -- Retrieve the text from the pane
        local text = pane:get_lines_as_text(pane:get_dimensions().scrollback_rows)

        -- Create a temporary file to pass to vim
        local name = os.tmpname()
        local f = io.open(name, 'w+')
        f:write(text)
        f:flush()
        f:close()

        -- Open a new window running vim and tell it to open the file
        window:perform_action(
          action.SpawnCommandInNewWindow {
            args = { 'vim', name },
          },
          pane
        )

        -- Wait "enough" time for vim to read the file before we remove it.
        -- The window creation and process spawn are asynchronous wrt. running
        -- this script and are not awaitable, so we just pick a number.
        --
        -- Note: We don't strictly need to remove this file, but it is nice
        -- to avoid cluttering up the temporary directory.
        wezterm.sleep_ms(1000)
        os.remove(name)
      end)

      return config
    '';
  };
}
