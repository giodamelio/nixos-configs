let
  # Generated with Rage. Currently stored in ~/nixos-configs/tmp/rage.txt
  testing = "age1qptntq0epxhxz892qwh65cnpk3vhpy69hlpzllzzh98e86y3yejqney7w0";
  users = [testing];

  beryllium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC1yjCGzopneOVL0+bVHAoFmnypw/qQh/exCXYPwr06b";
  systems = [beryllium];
in {
  "service_lldap.age".publicKeys = users ++ systems;
  "service_dns_updater.age".publicKeys = users ++ systems;
  "service_authelia_jwt_secret.age".publicKeys = users ++ systems;
  "service_authelia_storage_encryption_key.age".publicKeys = users ++ systems;
  "service_authelia_ldap_password.age".publicKeys = users ++ systems;
  "service_authentik_secret_key.age".publicKeys = users ++ systems;
  "service_authentik_postgres_password.age".publicKeys = users ++ systems;
  "cert_cloudflare_gio_ninja.age".publicKeys = users ++ systems;
}
