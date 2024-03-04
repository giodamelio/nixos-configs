let
  giodamelio-cadmium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKmSxFyT9n91A9dOpSCfl9kJj80KWFA6UvCtguT4S5b giodamelio@cadmium";
  users = [giodamelio-cadmium];

  zirconium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIECR2kS4hXBLqvqK21Ko+4CborL0Uo64/ZvtrISCsKPS";
  systems = [zirconium];
in {
  # Nebula CA Cert
  "nebula-ca.crt.age".publicKeys = users ++ systems;

  # Nebula Cert/Key for zirconium
  "nebula-zirconium.crt.age".publicKeys = users ++ [zirconium];
  "nebula-zirconium.key.age".publicKeys = users ++ [zirconium];
}
