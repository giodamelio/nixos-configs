# Nasty package that fetches Caddy from the internet...
# Just being used until this is resolved upstream
# See: https://github.com/NixOS/nixpkgs/pull/259275
_: {pkgs, ...}:
pkgs.stdenv.mkDerivation rec {
  name = "caddy-dns-cloudflare";
  src = builtins.fetchurl {
    url = "https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com%2Fcaddy-dns%2Fcloudflare";
    name = "caddy-dns-cloudflare";
    sha256 = "sha256:0250jmb8wy9414xwjm5mjhmjpn5gj5ri6ajh3q53wlvnydgrl9dc";
  };
  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/caddy
    chmod 755 $out/bin/caddy
  '';
}
