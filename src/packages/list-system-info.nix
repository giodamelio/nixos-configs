{
  inputs,
  homelab,
  debug,
}: {pkgs}:
pkgs.writeShellApplication {
  name = "list-system-info";

  runtimeInputs = with pkgs; [inxi dmidecode lm_sensors];

  text = ''
    sudo inxi -v 8
  '';
}
