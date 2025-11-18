{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    natscli
    nats-top
  ];

  services.nats = {
    enable = true;
    jetstream = true;
  };
}
