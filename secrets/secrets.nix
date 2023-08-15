let
  # Generated with Rage. Currently stored in ~/nixos-configs/tmp/rage.txt
  testing = "age1qptntq0epxhxz892qwh65cnpk3vhpy69hlpzllzzh98e86y3yejqney7w0";
  users = [testing];

  beryllium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC1yjCGzopneOVL0+bVHAoFmnypw/qQh/exCXYPwr06b";
  systems = [beryllium];
in {
  "test_secret.age".publicKeys = users ++ systems;
}
