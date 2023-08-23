let
  # Generated with Rage. Currently stored in ~/nixos-configs/tmp/rage.txt
  user_testing = "age1qptntq0epxhxz892qwh65cnpk3vhpy69hlpzllzzh98e86y3yejqney7w0";
  users = [user_testing];

  system_beryllium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC1yjCGzopneOVL0+bVHAoFmnypw/qQh/exCXYPwr06b";
  system_testing = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDehyZliNaoBmck3+Or4tCEHMhgeOrWF6tIkYSlQmauj";
  systems = [system_beryllium system_testing];
in {
  "cert_cloudflare_gio_ninja.age".publicKeys = users ++ systems;

  "wireguard/beryllium/rescue.key.age".publicKeys = [system_beryllium] ++ users;
  "wireguard/testing/rescue.key.age".publicKeys = [system_testing] ++ users;
  "wireguard/gio-pixel-7/rescue.key.age".publicKeys = users;

  "service_lldap.age".publicKeys = users ++ systems;
  "service_dns_updater.age".publicKeys = users ++ systems;
  "service_authelia_jwt_secret.age".publicKeys = users ++ systems;
  "service_authelia_storage_encryption_key.age".publicKeys = users ++ systems;
  "service_authelia_ldap_password.age".publicKeys = users ++ systems;
  "service_authentik_secret_key.age".publicKeys = users ++ systems;
  "service_authentik_postgres_password.age".publicKeys = users ++ systems;
  "service_firezone_postgres_password.age".publicKeys = users ++ systems;
  "service_firezone_envfile.age".publicKeys = users ++ systems;
  "service_netmaker_mosquitto_password_file.age".publicKeys = users ++ systems;
  "service_netmaker_postgres_password.age".publicKeys = users ++ systems;
  "service_netmaker_envfile.age".publicKeys = users ++ systems;
  "service_headscale_postgres_password.age".publicKeys = users ++ systems;
  "service_boundary_postgres_password.age".publicKeys = users ++ systems;
  "service_boundary_kms_config.age".publicKeys = users ++ systems;
  "service_boundary_admin_password.age".publicKeys = users ++ systems;
}
