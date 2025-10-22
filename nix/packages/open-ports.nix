{pkgs, ...}:
pkgs.writeShellApplication {
  name = "open-ports";
  runtimeInputs = with pkgs; [lsof ripgrep];
  text = ''
    output=$(sudo lsof -i -P -n)

    # Print the column labels
    echo "$output" | head -n 1

    # Print just the open listening ports
    echo "$output" | rg "LISTEN"
  '';
}
