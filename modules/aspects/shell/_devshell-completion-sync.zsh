# Fold zsh completions exposed by nix devshells into the running shell. mkShell
# puts each package's /share on XDG_DATA_DIRS (that's why bash/nushell get
# devshell completions for free); zsh keys off fpath + a one-time compinit, so
# it needs help. When XDG_DATA_DIRS changes (direnv, `nix develop -c zsh`) we
# fast-add the new zsh/site-functions per-file (autoload + compdef) instead of a
# full compinit rebuild (~300ms on a ~1k-fn fpath -> ~0.2ms here). No compdump
# caching needed since we never re-run compinit.
typeset -gA _zcs_seen
typeset -g _zcs_last_xdg _zcs_init

_zcs_fold() {
  local dir sf f fn tag rest
  for dir in ${(s.:.)XDG_DATA_DIRS}; do
    for sf in "$dir"/zsh/site-functions "$dir"/zsh/vendor-completions; do
      [[ -d "$sf" && -z "$_zcs_seen[$sf]" ]] || continue
      _zcs_seen[$sf]=1
      (( ${fpath[(Ie)$sf]} )) && continue        # already on fpath => startup compinit handled it
      fpath=("$sf" $fpath)
      for f in "$sf"/_*(N); do
        fn=$f:t
        read -r tag rest <"$f" 2>/dev/null || continue
        [[ "$tag" == "#compdef" && -n "$rest" ]] || continue
        (( $+functions[$fn] )) && unfunction $fn
        autoload -Uz $fn
        compdef $fn ${=rest} 2>/dev/null
      done
    done
  done
}

_zcs_sync() {                                       # fold on first prompt, then on XDG change
  [[ -n "$_zcs_init" && "$XDG_DATA_DIRS" == "$_zcs_last_xdg" ]] && return
  _zcs_init=1 _zcs_last_xdg="$XDG_DATA_DIRS"
  _zcs_fold
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zcs_sync
add-zsh-hook chpwd _zcs_sync
