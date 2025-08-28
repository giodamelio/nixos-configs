{
  vim = {
    # Enable treesitter
    treesitter = {
      enable = true;
      grammars = []; # Empty means all available grammars
    };

    # Rainbow parens and whatnot
    visuals.rainbow-delimiters.enable = true;
  };
}
