{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "satellite-earth-download";
  runtimeInputs = with pkgs; [curl imagemagick];
  source = ''
    use std/log

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
          log error $"Unknown source: ($source). Use: goes-east, goes-west, himawari"
          exit 1
        }
      }

      let output_path = if $output != null {
        $output
      } else {
        let cache = ($env | get -o XDG_CACHE_HOME | default $"($env.HOME)/.cache")
        $"($cache)/satellite-earth/latest.png"
      }

      log info $"Source: ($source) (($sat_id)), Product: ($product), Zoom: ($zoom), Output: ($output_path)"

      mkdir ($output_path | path dirname)
      let tile_dir = (mktemp -d)
      log debug $"Tile directory: ($tile_dir)"

      # Get latest timestamp
      log info "Fetching latest timestamp..."
      let latest = (curl -sf $"https://slider.cira.colostate.edu/data/json/($sat_id)/full_disk/($product)/latest_times.json" | from json)
      let timestamp = ($latest.timestamps_int.0 | into string)
      let year = ($timestamp | str substring 0..<4)
      let month = ($timestamp | str substring 4..<6)
      let day = ($timestamp | str substring 6..<8)
      log info $"Latest timestamp: ($timestamp) (($year)-($month)-($day))"

      let zoom_pad = ($zoom | fill -a right -c '0' -w 2)
      let grid_size = (2 ** $zoom)
      let base_url = $"https://slider.cira.colostate.edu/data/imagery/($year)/($month)/($day)/($sat_id)---full_disk/($product)/($timestamp)/($zoom_pad)"
      log debug $"Base URL: ($base_url)"

      # Download tiles
      let indices = (seq 0 ($grid_size - 1) | each {|x| $x | into int})
      log info $"Downloading ($grid_size * $grid_size) tiles..."
      for row in $indices {
        for col in $indices {
          let rp = ($row | fill -a right -c '0' -w 3)
          let cp = ($col | fill -a right -c '0' -w 3)
          curl -sf -o $"($tile_dir)/tile_($rp)_($cp).png" $"($base_url)/($rp)_($cp).png"
        }
      }
      log info "Tiles downloaded"

      # Stitch tiles: columns horizontally per row, then rows vertically
      log info "Stitching tiles..."
      for row in $indices {
        let rp = ($row | fill -a right -c '0' -w 3)
        let tiles = ($indices | each {|col| $"($tile_dir)/tile_($rp)_(($col | fill -a right -c '0' -w 3)).png" })
        magick ...$tiles +append $"($tile_dir)/row($row).png"
      }
      let rows = ($indices | each {|row| $"($tile_dir)/row($row).png" })
      magick ...$rows -append $"($tile_dir)/stitched.png"
      log info "Stitching complete"

      # Optionally add border, then save
      if $border > 0 {
        log info $"Adding ($border)px black border"
        magick $"($tile_dir)/stitched.png" -bordercolor black -border $border $output_path
      } else {
        mv $"($tile_dir)/stitched.png" $output_path
      }

      log info $"Saved to: ($output_path)"
      print $output_path
      rm -rf $tile_dir
    }
  '';
}
