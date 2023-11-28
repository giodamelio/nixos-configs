{
  root,
  debug,
  inputs,
  ...
}: {
  system,
  self,
}: {
  bootstrap-iso = self.nixosConfigurations.bootstrap.config.formats.install-iso;
  bootstrap-iso-hyperv = self.nixosConfigurations.bootstrap.config.formats.install-iso-hyperv;
}
