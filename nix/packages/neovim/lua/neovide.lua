-- Neovide Configuration
-- Only apply these settings when running in Neovide
if vim.g.neovide then
  -- Disable some decorations
  vim.g.neovide_cursor_animation_length = 0 -- Disable cursor animation (default: 0.13)
  vim.g.neovide_cursor_vfx_mode = '' -- Disable particle effects

  -- Scrolling
  vim.g.neovide_scroll_animation_length = 0.3 -- Scroll animation duration (default: 0.3)
  vim.g.neovide_scroll_animation_far_lines = 1 -- Lines considered "far" for scroll animation (default: 1)

  -- Floating Blur
  vim.g.neovide_floating_blur_amount_x = 2.0 -- Horizontal blur for floating windows (default: 2.0)
  vim.g.neovide_floating_blur_amount_y = 2.0 -- Vertical blur for floating windows (default: 2.0)
  vim.g.neovide_floating_shadow = true -- Shadow for floating windows (default: true)
  vim.g.neovide_floating_z_height = 10 -- Z-height for floating windows (default: 10)
  vim.g.neovide_light_angle_degrees = 45 -- Light angle for shadows (default: 45)
  vim.g.neovide_light_radius = 5 -- Light radius for shadows (default: 5)

  -- Performance
  vim.g.neovide_refresh_rate = 120 -- Refresh rate in Hz (default: 60)
  vim.g.neovide_confirm_quit = true -- Confirm before quitting (default: true)

  -- Input
  vim.g.neovide_profiler = false -- Enable profiler overlay (default: false)
  vim.g.neovide_input_macos_option_key_is_meta = 'only_left' -- Treat Alt as Meta on macOS (default: true)
  vim.g.neovide_input_ime = true -- Enable Input Method Editor support (default: true)

  -- Hide mouse when typing
  vim.g.neovide_hide_mouse_when_typing = true -- Hide mouse cursor when typing (default: true)

  -- Theme variant (for OS integration)
  vim.g.neovide_theme = 'auto' -- Options: 'auto', 'light', 'dark' (default: 'auto')

  -- Window decorations
  vim.g.neovide_unlink_border_highlights = false -- Keep border highlights linked (default: false)

  -- Remember window size and position
  vim.g.neovide_remember_window_size = true -- Remember window size between sessions (default: true)

  -- Keybindings specific to Neovide
  -- Toggle fullscreen
  vim.keymap.set('n', '<F11>', function()
    vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
  end, { desc = 'Toggle Neovide fullscreen' })

  -- Zoom in/out (Cmd/Ctrl + Plus/Minus)
  vim.keymap.set('n', '<D-=>', function()
    local current_scale = vim.g.neovide_scale_factor or 1.0
    vim.g.neovide_scale_factor = current_scale + 0.1
  end, { desc = 'Zoom in' })

  vim.keymap.set('n', '<D-->', function()
    local current_scale = vim.g.neovide_scale_factor or 1.0
    vim.g.neovide_scale_factor = math.max(0.1, current_scale - 0.1)
  end, { desc = 'Zoom out' })

  vim.keymap.set('n', '<D-0>', function()
    vim.g.neovide_scale_factor = 1.0
  end, { desc = 'Reset zoom' })

  -- For Linux/Windows, use Ctrl instead of Cmd
  vim.keymap.set('n', '<C-=>', function()
    local current_scale = vim.g.neovide_scale_factor or 1.0
    vim.g.neovide_scale_factor = current_scale + 0.1
  end, { desc = 'Zoom in' })

  vim.keymap.set('n', '<C-->', function()
    local current_scale = vim.g.neovide_scale_factor or 1.0
    vim.g.neovide_scale_factor = math.max(0.1, current_scale - 0.1)
  end, { desc = 'Zoom out' })

  vim.keymap.set('n', '<C-0>', function()
    vim.g.neovide_scale_factor = 1.0
  end, { desc = 'Reset zoom' })
end
