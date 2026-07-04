# devshell-completion-sync — auto-load zsh completions that nix devshells expose
# via XDG_DATA_DIRS. Included by the zsh aspect; inert on its own.
_: {
  den.aspects.devshell-completion-sync.homeManager = {lib, ...}: {
    programs.zsh.initContent =
      lib.mkAfter (builtins.readFile ./_devshell-completion-sync.zsh);
  };
}
