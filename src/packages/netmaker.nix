_: {pkgs}: {
  netmaker-ui = pkgs.buildNpmPackage rec {
    name = "netmaker-ui";
    version = "0.19.0";
    src = pkgs.fetchFromGitHub {
      owner = "gravitl";
      repo = "netmaker-ui";
      rev = "v${version}";
      hash = "sha256-VEnl3q72SZ8ut3jMs+7KyrhXx9Atxu8985UQeo0wMlk=";
    };
    npmDepsHash = "sha256-j1jZUHyRvGNmqF+dU7DoI9ghGbHXWJ8mRxTNWhSAK40=";
    NODE_OPTIONS = "--openssl-legacy-provider";

    installPhase = ''
      mkdir -p $out
      mv build/* $out/
    '';
  };
}
