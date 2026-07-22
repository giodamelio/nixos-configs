# firefox-pwa — Firefox site-specific browsers via PWAsForFirefox (firefoxpwa),
# fully declarative. Everyday Firefox gets the connector + extension; each app in
# `apps` is its own isolated firefoxpwa profile (own icon, own about:config
# prefs). config.json is Home-Manager-owned, so apps live here, not behind a
# runtime `firefoxpwa site install`. Adding one is a new `apps` block.
#
# Not wired to any host — kept as a working reference. We use the zapzap desktop
# client for WhatsApp instead. To use, include `den.aspects.firefox-pwa` in a
# host user's aspect list.
_: {
  den.aspects.firefox-pwa.homeManager = {
    pkgs,
    lib,
    ...
  }: let
    # One profile per app so prefs stay per-app. profileUlid/siteUlid are pinned
    # (26 chars of 0-9 A-Z minus I L O U) so the profile path is known and we can
    # seed its user.js. The nixpkgs firefoxpwa bakes its runtime in, and a
    # config.json-declared site creates + patches its profile on first launch, so
    # no CLI install is needed.
    apps = {
      whatsapp = {
        profileUlid = "0WHATSAPPWEB00000000000001";
        siteUlid = "0WHATSAPPWEB00000000000002";
        name = "WhatsApp Web";
        url = "https://web.whatsapp.com/";
        manifestUrl = "https://web.whatsapp.com/manifest.json";
        icon = pkgs.fetchurl {
          url = "https://web.whatsapp.com/whatsapp_pwa_icon_512.png";
          sha256 = "03mp6g7ai8gb2845q7s56n5kh8spjzbwk65fdj1v506rdij86kja";
        };
        # QR-linked, no external SSO, so hand every out-of-scope link to the
        # everyday Firefox. linksTarget=2 forces _blank into a throwaway window so
        # the handoff never navigates the app window away. launchType=2 reuses the
        # running window instead of spawning duplicates.
        prefs = {
          "firefoxpwa.openOutOfScopeInDefaultBrowser" = true;
          "firefoxpwa.linksTarget" = 2;
          "firefoxpwa.launchType" = 2;
        };
      };
    };

    prefsToUserJs = prefs:
      lib.concatStrings
      (lib.mapAttrsToList (k: v: ''user_pref("${k}", ${builtins.toJSON v});${"\n"}'') prefs);
  in {
    programs.firefox = {
      enable = true;
      # The firefoxpwa connector talks over native messaging, which is broken on
      # the -bin builds — it needs the wrapped source build.
      package = pkgs.firefox;
      nativeMessagingHosts = [pkgs.firefoxpwa];

      policies.ExtensionSettings."firefoxpwa@filips.si" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/pwas-for-firefox/latest.xpi";
      };
    };

    # Register everyday Firefox as the default handler so out-of-scope links from
    # an app hand off here, not into the app's own isolated Firefox.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/about" = "firefox.desktop";
        "x-scheme-handler/unknown" = "firefox.desktop";
      };
    };

    programs.firefoxpwa = {
      enable = true;
      profiles = lib.mapAttrs' (_: app:
        lib.nameValuePair app.profileUlid {
          inherit (app) name;
          sites.${app.siteUlid} = {
            inherit (app) name url manifestUrl;
            desktopEntry.icon = app.icon;
          };
        })
      apps;
      # Render natively on Wayland (niri/HiDPI hosts) instead of blurry XWayland.
      settings.config.runtime_enable_wayland = true;
    };

    # Per-app about:config prefs. firefoxpwa never writes a profile user.js, so
    # this file is ours; Firefox applies it on every app start.
    xdg.dataFile = lib.mapAttrs' (_: app:
      lib.nameValuePair "firefoxpwa/profiles/${app.profileUlid}/user.js" {
        text = prefsToUserJs app.prefs;
      })
    apps;
  };
}
