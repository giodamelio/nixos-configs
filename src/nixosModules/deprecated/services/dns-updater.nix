_: {
  pkgs,
  config,
  ...
}: let
  terraformConfig = pkgs.writeTextFile {
    name = "dns-updater.tf";
    text = ''
      # Setup our providers
      terraform {
        required_providers {
          tailscale = {
            source  = "tailscale/tailscale"
              version = "0.13.7"
          }
          cloudflare = {
            source = "cloudflare/cloudflare"
            version = "4.12.0"
          }
        }
      }
      provider "tailscale" {
        scopes  = ["read:devices"]
      }
      provider "cloudflare" {}

      # Some inputs
      variable "cloudflare_zone_id" {
        type = string
      }

      # Get all the devices from Tailscale
      data "tailscale_devices" "all" {}

      # Calculate the records from the list of Tailscale devices
      locals {
        a_records = {
          for d in data.tailscale_devices.all.devices : regex("^([^.]*)", d.name)[0] =>
            [
              for a in d.addresses : a
                if length(regexall("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", a)) > 0
            ][0]
        }
        aaaa_records = {
          for d in data.tailscale_devices.all.devices : regex("^([^.]*)", d.name)[0] =>
            [
              for a in d.addresses : a
                if length(regexall("^([a-f0-9:]+:+)+[a-f0-9]+$", a)) > 0
            ][0]
        }
      }

      # Add A record for each ipv4 address
      resource "cloudflare_record" "a_record" {
        for_each = local.a_records

        zone_id = var.cloudflare_zone_id
        type = "A"
        ttl = 300 # Five minutes
        comment = format("Created by dns-updater Terraform script. Updated at %s", timestamp())
        allow_overwrite = true

        name = each.key
        value = each.value
      }

      # Add AAAA record for each ipv4 address
      resource "cloudflare_record" "aaaa_record" {
        for_each = local.aaaa_records

        zone_id = var.cloudflare_zone_id
        type = "AAAA"
        ttl = 300 # Five minutes
        comment = format("Created by dns-updater Terraform script. Updated at %s", timestamp())
        allow_overwrite = true

        name = each.key
        value = each.value
      }
    '';
  };
  terraformScript = pkgs.writeShellApplication {
    name = "dns-updater-terraform";
    runtimeInputs = with pkgs; [terraform vault];
    text = ''
      # Symlink config in from Nix Store
      ln -s ${terraformConfig} .

      # Run Terraform
      terraform init
      terraform apply -auto-approve
    '';
  };
in {
  environment = {
    systemPackages = with pkgs; [
      terraform
    ];
  };

  age.secrets.service_dns_updater.file = ../../../secrets/service_dns_updater.age;

  systemd.services.dns-updater = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${terraformScript}/bin/dns-updater-terraform";
      EnvironmentFile = config.age.secrets.service_dns_updater.path;

      # Create our own tmp directory, then use it as the CWD for terraform
      PrivateTmp = "yes";
      WorkingDirectory = "%T";
    };
  };
}
