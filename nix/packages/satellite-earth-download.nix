{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "satellite-earth-download";
  runtimeInputs = with pkgs; [curl imagemagick];
  source = ''
    # Download the latest full-disk Earth image from a geostationary satellite
    # All imagery sourced from RAMMB/CIRA SLIDER (clean, no annotations)
    def main [
      source: string = "goes-east"           # goes-east, goes-west, himawari
      output?: string                        # output file path
      --zoom (-z): int = 2                   # zoom level (0=678px, 1=1356px, 2=2712px, 3=5424px)
      --product (-p): string = "natural_color"  # product type (natural_color, geocolor)
      --border (-b): int = 200                # border size in pixels (0 to disable)
    ] {
      let sat_id = match $source {
        "goes-east" => "goes-19",
        "goes-west" => "goes-18",
        "himawari" => "himawari",
        _ => {
          print -e $"Unknown source: ($source). Use: goes-east, goes-west, himawari"
          exit 1
        }
      }

      let output_path = if $output != null {
        $output
      } else {
        let cache = ($env | get -o XDG_CACHE_HOME | default $"($env.HOME)/.cache")
        $"($cache)/satellite-earth/latest.png"
      }

      mkdir ($output_path | path dirname)
      let tile_dir = (mktemp -d)

      # Get latest timestamp
      let latest = (curl -sf $"https://slider.cira.colostate.edu/data/json/($sat_id)/full_disk/($product)/latest_times.json" | from json)
      let timestamp = ($latest.timestamps_int.0 | into string)
      let year = ($timestamp | str substring 0..<4)
      let month = ($timestamp | str substring 4..<6)
      let day = ($timestamp | str substring 6..<8)

      let zoom_pad = ($zoom | fill -a right -c '0' -w 2)
      let grid_size = (2 ** $zoom)
      let base_url = $"https://slider.cira.colostate.edu/data/imagery/($year)/($month)/($day)/($sat_id)---full_disk/($product)/($timestamp)/($zoom_pad)"

      # Download tiles
      let indices = (seq 0 ($grid_size - 1) | each {|x| $x | into int})
      for row in $indices {
        for col in $indices {
          let rp = ($row | fill -a right -c '0' -w 3)
          let cp = ($col | fill -a right -c '0' -w 3)
          curl -sf -o $"($tile_dir)/tile_($rp)_($cp).png" $"($base_url)/($rp)_($cp).png"
        }
      }

      # Stitch tiles: columns horizontally per row, then rows vertically
      for row in $indices {
        let rp = ($row | fill -a right -c '0' -w 3)
        let tiles = ($indices | each {|col| $"($tile_dir)/tile_($rp)_(($col | fill -a right -c '0' -w 3)).png" })
        magick ...$tiles +append $"($tile_dir)/row($row).png"
      }
      let rows = ($indices | each {|row| $"($tile_dir)/row($row).png" })
      magick ...$rows -append $"($tile_dir)/stitched.png"

      # Optionally add border, then save
      if $border > 0 {
        magick $"($tile_dir)/stitched.png" -bordercolor black -border $border $output_path
      } else {
        mv $"($tile_dir)/stitched.png" $output_path
      }

      print $output_path
      rm -rf $tile_dir
    }
  '';
}
