# Throwaway MCP server for testing bifrost's OAuth end to end. Delete when done.
# REMIND-ME-TO: Delete this time MCP server, .mcp.json and its grants once a real MCP server is behind bifrost date_passed=2027-01-24
_: {
  den.aspects.carbon.nixos = {
    pkgs,
    lib,
    ...
  }: let
    port = 52794;
  in {
    systemd.services.bifrost-time-mcp = {
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.mcp-proxy} --host 127.0.0.1 --port ${toString port} --stateless -- ${lib.getExe pkgs.mcp-server-time} --local-timezone America/Los_Angeles";
        DynamicUser = true;
        Restart = "on-failure";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    gio.bifrost.services.time = {
      oauth.groups = [];
      config = ''
        reverse_proxy 127.0.0.1:${toString port}
      '';
    };
  };
}
