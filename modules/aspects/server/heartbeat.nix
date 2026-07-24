# server-heartbeat — the shared handle every always-on server pulls in to run the
# heartbeat collector (Telegraf -> its own Healthchecks check). It's explicitly
# included per server (like zfs-backup), NOT role-attached: heartbeat needs the
# healthcheck_url credential, and test fleets default to role="server", so
# auto-attaching would trip the fleet.credentials assertion across the suite.
{den, ...}: {
  den.aspects.server-heartbeat.includes = [den.aspects.heartbeat];
}
