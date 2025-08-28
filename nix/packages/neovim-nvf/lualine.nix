{lib, ...}: {
  vim.statusline.lualine = {
    enable = true;

    # TODO: contribute a tabline setup to nvf
    setupOpts = {
      tabline = {
        lualine_a = [(lib.generators.mkLuaInline ''{ "tabs", mode = 2 }'')];
        lualine_x = [
          (lib.generators.mkLuaInline ''
            '"[next tab] gt, [prev tab] gT, [close tab] :tabclose"'
          '')
        ];
      };
    };
  };
}
