{
  debug,
  inputs,
  ...
}: {pkgs}: let
  # Create a copy of our nixpkgs with the Nu builder
  pkgsWithNu = import inputs.nixpkgs {
    inherit (pkgs) system;
    overlays = [inputs.nuenv.overlays.nuenv];
  };
in {
  zz = pkgsWithNu.nuenv.mkCommand {
    name = "zz";
    runtimeInputs = with pkgsWithNu; [zellij skim];
    description = "Interactivaly choose which Zellij session to join, or create one if none exist";
    text = ''
      let sessions = (zellij list-sessions | lines)
      let session_count = ($sessions | length)
      if $session_count == 0 {
        exec zellij attach --create default
      } else if $session_count == 1 {
        exec zellij attach $sessions.0
      } else {
        let picked_session = ($sessions | to text | sk)
        exec zellij attach $picked_session
      }
    '';
    subCommands = {
      ls = {
        description = "Lists the Zellij sessions";
        text = "zellij ls";
      };
    };
  };
  zdeploy = pkgsWithNu.nuenv.mkCommand {
    name = "zdeploy";
    runtimeInputs = with pkgsWithNu; [zellij];
    args = ["host:string"];
    description = "Run deploy command in another Zellij session (that I keep open on another monitor)";
    text = ''
      # Write ASCII ETX (end of text), basically ^C
      zellij --session runner action write 3
      zellij --session runner action write-chars "deploy "
      zellij --session runner action write-chars $host
      # Write ASCII Newline
      zellij --session runner action write 10
    '';
  };
  deploy = pkgsWithNu.nuenv.mkCommand {
    name = "deploy";
    description = "Interactivaly choose a host and deploy to it";
    runtimeInputs = with pkgsWithNu; [skim];
    args = ["host?:string"];
    flags = {
      verbose = {
        description = "Disable Colmena spinners and print the whole build log";
        type = "bool";
        short = "v";
      };
    };
    text = ''
      # If no node is passed, interactivaly pick one
      let node = (if ($host == null) {
        let nodes = (
          nix eval .#nixosConfigurations --apply builtins.attrNames --json
        )
        ($nodes | from json | to text | sk)
      } else {
        $host
      })

      printf "Running 'colmena apply --on %s'\n\n" $node
      if ($verbose != null) {
        colmena apply --verbose --on $node
      } else {
        colmena apply --on $node
      }
    '';

    subCommands = {
      all = {
        description = "Deploy all hosts";
        text = ''
          colmena apply
        '';
      };
    };
  };
  wallpaper-epic-downloader = pkgsWithNu.nuenv.mkCommand {
    name = "wallpaper-epic-downloader";
    runtimeInputs = with pkgsWithNu; [curl imagemagick swww];
    description = "Download the latest photo from the DSCOVR: EPIC instrument and annotate the datetime on the bottom";
    text = ''
      # Get the url of the latest image and it's metadata
      let latest_image_info = (http get https://epic.gsfc.nasa.gov/api/natural | last)
      let latest_image_date = ($latest_image_info.date | date to-record)
      let latest_image_url = (printf "https://epic.gsfc.nasa.gov/archive/natural/%d/%02d/%02d/png/%s.png" $latest_image_date.year $latest_image_date.month $latest_image_date.day $latest_image_info.image)

      # Create a date string that we can annotate onto the image
      let date_exact = ($latest_image_info.date | into datetime | format date "%A %B %d %I:%M %p")
      let date_relative = ($latest_image_info.date | date humanize)
      let date_string = (printf "%s | %s" $date_exact $date_relative)

      # Download the latest image
      curl -o /tmp/epic_latest.png $latest_image_url

      # Annotate the image
      magick /tmp/epic_latest.png -gravity South -pointsize 40 -fill white -annotate +0+40 $date_string /tmp/epic_latest_annotated.png

      # Set it as the desktop background
      swww img /tmp/epic_latest_annotated.png --transition-type none --resize no
    '';
  };
}
