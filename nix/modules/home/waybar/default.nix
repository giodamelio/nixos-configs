{
  config,
  lib,
  pkgs,
  flake,
  ...
}: let
  cfg = config.gio.waybar;
  flakePackages = flake.packages.${pkgs.stdenv.hostPlatform.system};

  allModules = cfg.modules.left ++ cfg.modules.center ++ cfg.modules.right;
  has = name: builtins.elem name allModules;

  # Expand meta-module names to actual waybar module names
  networkModuleNames =
    if cfg.networkInterfaces == []
    then ["network"]
    else
      map (
        iface:
          if iface.suffix != null
          then "network#${iface.suffix}"
          else "network"
      )
      cfg.networkInterfaces;

  expandModule = name:
    if name == "network"
    then networkModuleNames
    else if name == "network-graphs"
    then ["custom/network-down-icon" "custom-graph/network-down" "custom/network-up-icon" "custom-graph/network-up"]
    else [name];

  expandModules = builtins.concatMap expandModule;

  # CPU format with 32 icon slots (auto-sizes to actual core count)
  cpuFormat = let
    icons = builtins.genList (i: "{icon${toString i}}") 32;
  in
    builtins.concatStringsSep "" icons + " {usage}% ";

  cpuFormatIcons = [
    "<span color='#69ff94'>▁</span>"
    "<span color='#2aa9ff'>▂</span>"
    "<span color='#f8f8f2'>▃</span>"
    "<span color='#f8f8f2'>▄</span>"
    "<span color='#ffffa5'>▅</span>"
    "<span color='#ffffa5'>▆</span>"
    "<span color='#ff9977'>▇</span>"
    "<span color='#dd532e'>█</span>"
  ];

  # Shared module configs
  clockConfig = {
    format = "{:%I:%M %p} ";
    format-alt = "{:%A, %B %d, %Y (%I:%M %p)}";
    tooltip-format = "<tt><small>{calendar}</small></tt>";
    calendar = {
      mode = "month";
      mode-mon-col = 3;
      weeks-pos = "right";
      on-scroll = 1;
      on-click-right = "mode";
      format = {
        months = "<span color='#ffead3'><b>{}</b></span>";
        days = "<span color='#ecc6d9'><b>{}</b></span>";
        weeks = "<span color='#99ffdd'><b>W{}</b></span>";
        weekdays = "<span color='#ffcc66'><b>{}</b></span>";
        today = "<span color='#ff6699'><b><u>{}</u></b></span>";
      };
    };
    actions = {
      on-click-right = "mode";
      on-scroll-up = "shift_up";
      on-scroll-down = "shift_down";
    };
  };

  memoryConfig = {
    format = "{percentage}% ({used}GiB) ";
  };

  notificationConfig = let
    swayncClient = "${pkgs.swaynotificationcenter}/bin/swaync-client";
  in {
    tooltip = false;
    format = " {icon} ";
    format-icons = {
      notification = "<span foreground='red'><sup></sup></span>";
      none = "";
      dnd-notification = "<span foreground='red'><sup></sup></span>";
      dnd-none = "";
      inhibited-notification = "<span foreground='red'><sup></sup></span>";
      inhibited-none = "";
      dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
      dnd-inhibited-none = "";
    };
    return-type = "json";
    exec-if = "which ${swayncClient}";
    exec = "${swayncClient} -swb";
    on-click = "${swayncClient} -t -sw";
    on-click-right = "${swayncClient} -d -sw";
    escape = true;
  };

  defaultNetworkConfig = {
    format-ethernet = "{ifname} {ipaddr} 󰛳";
    format-linked = "{ifname} 󰅛";
    format-alt = "{ifname}: {ipaddr}/{cidr}";
    tooltip-format = ''
      {ifname} {ipaddr}/{cidr}

      Down: {bandwidthDownBytes}
      Up:   {bandwidthUpBytes}
    '';
  };

  # Build network settings from interfaces
  networkSettings =
    if cfg.networkInterfaces == []
    then {
      network =
        defaultNetworkConfig
        // {
          format-disconnected = "Disconnected 󰅛";
        }
        // lib.optionalAttrs cfg.isLaptop {
          format-wifi = "{essid} ({signalStrength}%) ";
        };
    }
    else
      builtins.listToAttrs (
        map (
          iface: let
            moduleName =
              if iface.suffix != null
              then "network#${iface.suffix}"
              else "network";
          in {
            name = moduleName;
            value =
              defaultNetworkConfig
              // {
                interface = iface.name;
                format-disconnected = "{ifname} 󰅛";
              }
              // lib.optionalAttrs cfg.isLaptop {
                format-wifi = "{essid} ({signalStrength}%) ";
              };
          }
        )
        cfg.networkInterfaces
      );

  # Build all module settings
  moduleSettings =
    {}
    // lib.optionalAttrs (has "clock") {clock = clockConfig;}
    // lib.optionalAttrs (has "cpu") {
      cpu = {
        format = cpuFormat;
        interval = 1;
        format-icons = cpuFormatIcons;
      };
    }
    // lib.optionalAttrs (has "memory") {memory = memoryConfig;}
    // lib.optionalAttrs (has "battery") {
      battery = {
        states = {
          warning = 30;
          critical = 15;
        };
        format = "{capacity}% {icon}";
        format-charging = "{capacity}% 󰂄";
        format-plugged = "{capacity}% ";
        format-alt = "{time} {icon}";
        format-icons = ["" "" "" "" ""];
      };
    }
    // lib.optionalAttrs (has "backlight") {
      backlight = {
        format = "{percent}% {icon}";
        format-icons = ["" "" "" "" "" "" "" "" ""];
      };
    }
    // lib.optionalAttrs (has "pulseaudio") {
      pulseaudio =
        {
          format = "{volume}% {icon}";
          format-icons = {
            headphone = "";
            default = ["" ""];
          };
        }
        // (
          if cfg.audioOutputSwitcher
          then {
            on-click = "${flakePackages.audio-output-switcher}/bin/audio-output-switcher";
            on-click-right = "${pkgs.pw-volume}/bin/pw-volume mute toggle";
          }
          else {
            format-muted = "{volume}% 󰝟";
            on-click = "${pkgs.pw-volume}/bin/pw-volume mute toggle";
          }
        );
    }
    // lib.optionalAttrs (has "custom/notification") {"custom/notification" = notificationConfig;}
    // lib.optionalAttrs (has "custom/claude-usage") {
      "custom/claude-usage" = {
        exec = "${flakePackages.waybar-claude-usage}/bin/waybar-claude-usage";
        return-type = "json";
        interval = 600;
        tooltip = true;
      };
    }
    // lib.optionalAttrs (has "custom/power") {
      "custom/power" = {
        on-click = "${flakePackages.reboot-into-entry}/bin/reboot-into-entry";
        format = " ⏻  ";
      };
    }
    // lib.optionalAttrs (has "network-graphs") {
      "custom/network-down-icon" = {
        format = "↓";
        tooltip = false;
      };
      "custom-graph/network-down" = {
        exec = "${flakePackages.waybar-network-monitor}/bin/waybar-network-monitor down";
        return-type = "json";
        tooltip = true;
      };
      "custom/network-up-icon" = {
        format = "↑";
        tooltip = false;
      };
      "custom-graph/network-up" = {
        exec = "${flakePackages.waybar-network-monitor}/bin/waybar-network-monitor up";
        return-type = "json";
        tooltip = true;
      };
    }
    // lib.optionalAttrs (has "network") networkSettings;

  # CSS color definitions
  colorDefs = ''
    /* Base */
    @define-color bg-color rgba(43, 48, 59, 0.5);
    @define-color border-color rgba(100, 114, 125, 0.5);
    @define-color text #ffffff;
    @define-color text-dark #000000;
    @define-color hover rgba(0, 0, 0, 0.2);

    /* Accent */
    @define-color accent #64727D;

    /* Status */
    @define-color urgent #eb4d4b;
    @define-color critical #f53c3c;
    @define-color success #26A65B;
    @define-color warning #f0932b;

    /* Module backgrounds */
    @define-color cpu #2ecc71;
    @define-color memory #9b59b6;
    @define-color network #2980b9;
    @define-color pulseaudio #f1c40f;
    @define-color backlight #90b1b1;
    @define-color muted #90b1b1;
    @define-color muted-text #2a5c45;
  '';

  # Base CSS (always included)
  baseCSS = ''
    * {
        font-family: "Symbols Nerd Font", FontAwesome, Roboto, Helvetica, Arial, sans-serif;
        font-size: ${toString cfg.fontSize}px;
    }

    window#waybar {
        background-color: @bg-color;
        border-bottom: 3px solid @border-color;
        color: @text;
        transition-property: background-color;
        transition-duration: .5s;
    }

    window#waybar.hidden {
        opacity: 0.2;
    }

    button {
        box-shadow: inset 0 -3px transparent;
        border: none;
        border-radius: 0;
    }

    button:hover {
        background: inherit;
        box-shadow: inset 0 -3px @text;
    }

    #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: @text;
    }

    #workspaces button:hover {
        background: @hover;
    }

    #workspaces button.urgent {
        background-color: @urgent;
    }

    #window,
    #workspaces {
        margin: 0 4px;
    }

    .modules-left > widget:first-child > #workspaces {
        margin-left: 0;
    }

    .modules-right > widget:last-child > #workspaces {
        margin-right: 0;
    }
  '';

  # WM-specific CSS
  wmCSS =
    if cfg.windowManager == "sway"
    then ''
      #workspaces button.focused {
          background-color: @accent;
          box-shadow: inset 0 -3px @text;
      }
    ''
    else ''
      #workspaces button.active {
          background-color: @accent;
          box-shadow: inset 0 -3px @text;
      }
    '';

  # Per-module CSS blocks
  getModuleCSS = name:
    if name == "clock"
    then ''
      #clock {
          padding: 0 10px;
          color: @text;
          background-color: @accent;
      }
    ''
    else if name == "cpu"
    then ''
      #cpu {
          padding: 0 10px;
          color: @text;
          background-color: @cpu;
          color: @text-dark;
      }
    ''
    else if name == "memory"
    then ''
      #memory {
          padding: 0 10px;
          color: @text;
          background-color: @memory;
      }
    ''
    else if name == "battery"
    then ''
      #battery {
          padding: 0 10px;
          color: @text;
          background-color: @text;
          color: @text-dark;
      }

      #battery.charging, #battery.plugged {
          color: @text;
          background-color: @success;
      }

      @keyframes blink {
          to {
              background-color: @text;
              color: @text-dark;
          }
      }

      #battery.critical:not(.charging) {
          background-color: @critical;
          color: @text;
          animation-name: blink;
          animation-duration: 0.5s;
          animation-timing-function: steps(12);
          animation-iteration-count: infinite;
          animation-direction: alternate;
      }
    ''
    else if name == "backlight"
    then ''
      #backlight {
          padding: 0 10px;
          color: @text;
          background-color: @backlight;
      }
    ''
    else if name == "network"
    then ''
      #network {
          padding: 0 10px;
          color: @text;
          background-color: @network;
      }

      #network.disconnected {
          background-color: @critical;
      }
    ''
    else if name == "pulseaudio"
    then ''
      #pulseaudio {
          padding: 0 10px;
          color: @text;
          background-color: @pulseaudio;
          color: @text-dark;
      }

      #pulseaudio.muted {
          background-color: @muted;
          color: @muted-text;
      }
    ''
    else if name == "tray"
    then ''
      #tray {
          padding: 0 10px;
          color: @text;
          background-color: @network;
      }

      #tray > .passive {
          -gtk-icon-effect: dim;
      }

      #tray > .needs-attention {
          -gtk-icon-effect: highlight;
          background-color: @urgent;
      }
    ''
    else if name == "sway/mode"
    then ''
      #mode {
          padding: 0 10px;
          color: @text;
          background-color: @accent;
          box-shadow: inset 0 -3px @text;
      }
    ''
    else if name == "network-graphs"
    then ''
      @define-color network-down #0080c0;
      @define-color network-up #fa7070;

      #custom-network-down-icon {
          background-color: transparent;
          color: @network-down;
          padding: 0 2px;
      }

      #custom-graph-network-down {
          background-color: transparent;
          padding: 0 5px 0 0;
      }

      #custom-network-up-icon {
          background-color: transparent;
          color: @network-up;
          padding: 0 2px;
      }

      #custom-graph-network-up {
          background-color: transparent;
          padding: 0 5px 0 0;
      }
    ''
    else if name == "custom/claude-usage"
    then ''
      #custom-claude-usage {
          padding: 0 10px;
          color: @text;
          background-color: @cpu;
          color: @text-dark;
      }

      #custom-claude-usage.warning {
          background-color: @warning;
          color: @text-dark;
      }

      #custom-claude-usage.critical {
          background-color: @critical;
          color: @text;
      }

      #custom-claude-usage.error {
          background-color: @muted;
          color: @muted-text;
      }
    ''
    else if name == "custom/notification"
    then ""
    else if name == "custom/power"
    then ""
    else "";

  modulesCSS = builtins.concatStringsSep "\n" (map getModuleCSS allModules);

  # Build main bar config
  mainBar =
    {
      layer = "top";
      position = "top";
      modules-left = expandModules cfg.modules.left;
      modules-center = expandModules cfg.modules.center;
      modules-right = expandModules cfg.modules.right;
    }
    // lib.optionalAttrs (cfg.monitors != null) {
      output = [cfg.monitors.main];
    }
    // moduleSettings;

  # Build secondary bar (minimal: workspaces + clock)
  secondaryBar = {
    layer = "top";
    position = "top";
    output = cfg.monitors.secondary;
    modules-left =
      if cfg.windowManager == "sway"
      then ["sway/workspaces"]
      else ["niri/workspaces"];
    modules-right = ["clock"];
    clock = clockConfig;
  };
in {
  options.gio.waybar = {
    enable = lib.mkEnableOption "Waybar status bar";

    windowManager = lib.mkOption {
      type = lib.types.enum ["sway" "niri"];
      description = "Which window manager to configure waybar for";
    };

    isLaptop = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this is a laptop (enables wifi format on network)";
    };

    fontSize = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = "Font size in pixels for waybar";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.waybar;
      description = "The waybar package to use";
    };

    audioOutputSwitcher = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use audio-output-switcher for pulseaudio click instead of mute toggle";
    };

    modules = {
      left = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Modules for the left side of the bar";
      };

      center = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Modules for the center of the bar";
      };

      right = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Modules for the right side of the bar";
      };
    };

    monitors = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          main = lib.mkOption {
            type = lib.types.str;
            description = "Primary monitor output name";
          };
          secondary = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Secondary monitor output names (get a minimal bar with workspaces + clock)";
          };
        };
      });
      default = null;
      description = "Multi-monitor configuration. null means single monitor.";
    };

    networkInterfaces = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Interface name or glob pattern";
          };
          suffix = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Waybar module suffix (e.g. 'wifi' produces network#wifi)";
          };
        };
      });
      default = [];
      description = "Network interfaces to display. Empty uses a single default network module.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      [pkgs.swaynotificationcenter]
      ++ lib.optional (has "custom/power") flakePackages.reboot-into-entry;

    # Override the systemd service so waybar only starts for Sway,
    # not for every graphical session
    systemd.user.services.waybar = {
      Unit = {
        After = lib.mkForce ["graphical-session.target"];
        PartOf = lib.mkForce ["sway-session.target" "tray.target"];
      };
      Install.WantedBy = lib.mkForce ["sway-session.target"];
    };

    programs.waybar = {
      enable = true;
      inherit (cfg) package;
      systemd.enable = true;

      settings =
        {main = mainBar;}
        // lib.optionalAttrs (cfg.monitors != null && cfg.monitors.secondary != []) {
          secondary = secondaryBar;
        };

      style = builtins.concatStringsSep "\n" [
        colorDefs
        baseCSS
        wmCSS
        modulesCSS
      ];
    };

    xdg.desktopEntries = lib.mkIf (has "custom/power") {
      reboot-into-entry = {
        name = "Reboot Into Boot Entry";
        exec = "reboot-into-entry";
        icon = "system-reboot";
        categories = ["System"];
      };
    };
  };
}
