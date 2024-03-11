# This is a unholy thing that extracts the files we want
# directly from a docker image layer fetched from ghcr.io
# Here Be Dragons
_: {pkgs, ...}: let
  downloadScript = version:
    pkgs.writeShellApplication {
      name = "download-layer";

      runtimeInputs = with pkgs; [curl jq cacert];

      text = ''
        # Make curl work with SSL
        export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

        # Get token so we can download layer
        token_url="https://ghcr.io/token?service=ghcr.io&scope=repository%3Adefguard%2Fdefguard%3Apull"
        token=$(curl "$token_url" | jq -r .token)

        # Download layer
        curl --fail --location --output layer.tar.gz "https://ghcr.io/v2/defguard/defguard/blobs/sha256:${version}" -H "authorization: Bearer $token"
      '';
    };
  extractScript = pkgs.writeShellApplication {
    name = "extract-layer";

    runtimeInputs = with pkgs; [gzip];

    text = ''
      tar xzfv layer.tar.gz

      # Allow access to $out even though it was not defined here
      # shellcheck disable=SC2154
      mv app/web/dist/ "$out"
    '';
  };
in
  pkgs.stdenv.mkDerivation rec {
    pname = "defguard-ui";
    version = "f5e89529eba2786c8eab0b9e24ac1a5935299fab38286d34f8090f613b63e160"; # Blob digest
    src = ./.;

    buildPhase = "${downloadScript version}/bin/download-layer";
    installPhase = "${extractScript}/bin/extract-layer";

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-45Czgy5AK2On16sYxpjybbQXJIX/Imp2s3gqyfPCIBM=";
  }
