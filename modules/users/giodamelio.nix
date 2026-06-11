# giodamelio — the shared user baseline, applied on every den host that
# declares `users.giodamelio` (currently cesium and cadmium; den resolves the
# aspect by user name). Host-specific user bits — extra groups, host-only HM
# aspects, monitor layouts — live on each host's user entity via
# `den.hosts.<sys>.<host>.users.giodamelio.aspect.includes` (which then must
# also include this baseline aspect explicitly), NOT here: anything added here
# lands on every host with this user.
#
# nix-activate/shpool/zmx come from den.default, so they are not listed here.
{den, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../homelab.toml);
in {
  den.aspects.giodamelio = {
    includes = [
      # User account at OS + Home level. primary-user is deliberately NOT here:
      # it adds the networkmanager group, which only cesium wants (cadmium is a
      # wired desktop with its own group set).
      den.batteries.define-user
      (den.batteries.user-shell "zsh")

      # Home-Manager features. modern-coreutils-replacements comes from
      # den.default, so it is not listed here.
      den.aspects.lil-scripts
      den.aspects.git
      den.aspects.neovim
      den.aspects.zellij
      den.aspects.starship
      den.aspects.zsh
      den.aspects.nushell
      den.aspects.nix-index
      den.aspects.atuind
      den.aspects.claude-code
      den.aspects.jj
      den.aspects.wezterm

      # Folded dual-class: HM half on the user, NixOS half forwarded to the
      # host ("users shape their host").
      den.aspects.niri
    ];

    # Account details beyond what define-user/user-shell provide. Uses den's
    # `user` class (forwarded to users.users.giodamelio by the os-user
    # battery), so the aspect never names users.users.<name> directly.
    user = {
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };

    homeManager = {
      # TODO: HM stateVersion is still 24.11 (carried over from Blueprint).
      # Update later, deliberately, once the den-migrated hosts have soaked.
      home.stateVersion = "24.11";

      programs.home-manager.enable = true;

      # Configure Claude Code
      programs.gio-claude-code = {
        enable = true;
        installPackage = true;
      };

      # Configure nix-activate for NixOS
      gio.nix-activate-config.activation = {system = "nixos";};
    };
  };
}
