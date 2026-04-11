{
  config,
  perSystem,
  ...
}: {
  home.packages =
    if config.gio.role == "server"
    then [perSystem.zmx.default]
    else [];
}
