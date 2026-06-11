# ollama — local LLM server with ROCm acceleration. Converted from
# nix/modules/nixos/ollama.nix.
_: {
  den.aspects.ollama.nixos = {pkgs, ...}: {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
    };
  };
}
