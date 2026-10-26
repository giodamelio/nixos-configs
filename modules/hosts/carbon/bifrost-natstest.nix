# Throwaway webhook target for testing bifrost's NATS publishing end to end.
# Delete when done.
# REMIND-ME-TO: Delete this natstest target and run `nats stream rm BIFROST_TEST` on carbon once a real JetStream webhook uses bifrost date_passed=2027-01-24
_: {
  den.aspects.carbon.nixos = {pkgs, ...}: {
    gio.nats.streams.BIFROST_TEST = {
      subjects = ["bifrost.test.>"];
      maxAge = "1d";
    };

    gio.bifrost.services.natstest = {
      # A deliberately public test token; it guards nothing but this stream.
      config = ''
        bifrost_guard bearer {
          token_file ${pkgs.writeText "bifrost-natstest-token" "fc17af946e9198a6eaefbf197e7e8efc"}
        }
      '';
      nats = {
        subject = "bifrost.test.webhook";
        stream = "BIFROST_TEST";
      };
    };
  };
}
