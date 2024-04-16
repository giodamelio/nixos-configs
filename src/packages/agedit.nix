_: {pkgs, ...}:
pkgs.buildGoModule rec {
  pname = "agedit";
  version = "0.2.1";

  src = pkgs.fetchgit {
    url = "https://git.burning.moe/celediel/agedit";
    rev = "v${version}";
    hash = "sha256-MC3ZSKJlGBKDZQaugkXCXaJnbiDv+u+jvXok5DiZrNI=";
  };

  vendorHash = "sha256-V2YbTYN9780TuhqXuIxBrZdnri6XZhJLYYbHEin4+tU=";

  ldflags = ["-s" "-w"];

  meta = with pkgs.lib; {
    description = "Easily edit age encrypted files";
    homepage = "https://git.burning.moe/celediel/agedit";
    license = licenses.agpl3Only;
    maintainers = with maintainers; [];
    mainProgram = "agedit";
  };
}
