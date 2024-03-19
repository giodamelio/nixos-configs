terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    toml = {
      source  = "Tobotimus/toml"
      version = "0.1.0"
    }
  }
}

provider "cloudflare" {}

data "cloudflare_zone" "gio-ninja" {
  name = "gio.ninja"
}
