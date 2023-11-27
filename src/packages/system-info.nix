{
  inputs,
  homelab,
  debug,
}: {pkgs}: rec {
  # List system info from various tools
  list-system-info = pkgs.writeShellApplication {
    name = "list-system-info";

    runtimeInputs = with pkgs; [inxi dmidecode lm_sensors];

    text = ''
      if [[ "$EUID" != 0 ]]; then
        echo "Script must be run as root"
        exit 1
      fi

      sudo inxi -v 8 --width 1
    '';
  };

  # Upload system info to a pastebin, encrypting it first
  upload-system-info = pkgs.writeShellApplication {
    name = "upload-system-info";

    runtimeInputs = with pkgs; [list-system-info rage];

    text = ''
      SYSTEM_INFO_FILE=/tmp/system-info-url

      if [[ -f "$SYSTEM_INFO_FILE" ]]; then
        URL=$(< "$SYSTEM_INFO_FILE")
        printf "System Info Uploaded: %s\n" "$URL"
        echo ""
        echo "To view, run this command:"
        echo "    curl --silent $URL | rage --decrypt -i ~/.age/bootstrap.key | less"
        exit 0
      fi

      if [[ "$EUID" != 0 ]]; then
        echo "Script must be run as root"
        exit 1
      fi

      printf "Uploading system info..."
      list-system-info | rage ${recipients} | curl --silent -F 'f:1=<-' ix.io > "$SYSTEM_INFO_FILE"
      echo " Done"

      # Rerun itself
      exec "$0"
    '';
  };

  # List of encryption recipients formatted for age
  recipients = pkgs.lib.strings.concatMapStringsSep " " (item: "-r ${item}") homelab.bootstrap_keys;
}
