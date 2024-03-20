let
  giodamelio-cadmium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKmSxFyT9n91A9dOpSCfl9kJj80KWFA6UvCtguT4S5b giodamelio@cadmium";
  giodamelio-cesium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAHlH3cxSO186g1bcZ3I3xSX3Fi2E094XnzvTFnW5/G1 giodamelio@cesium";
  users = [giodamelio-cadmium giodamelio-cesium];

  zirconium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3O4mziNw2k53SE3WTX2jbMx38tqngSaoB3TsXM9UlH";
  cadmium = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFyDOEgsO9wykdbqhUOBWpSIXJ7Kd9D0Pl7W0dnxDn/m";
  carbon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIX5P0ZXB1SUbiDrm42t19GEsz80dw+yI0GoO0tYlJsn";
  systems = [zirconium cadmium carbon];
in {
  "cloudflare-token.age".publicKeys = users ++ [zirconium];
  "grafana-defguard-oauth-client-id.age".publicKeys = users ++ [zirconium];
  "grafana-defguard-oauth-client-secret.age".publicKeys = users ++ [zirconium];
}
