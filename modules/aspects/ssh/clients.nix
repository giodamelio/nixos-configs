# Fleet SSH registries; enrollment + revocation runbooks in docs/ssh.md.
_: {
  fleet.ssh = {
    externalClients = {
      pixel8-termius = {
        publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCsv5nvQed0ahn542ujutvCI7rUv+wNXUQTXAF8MfePxSMBNvHKYj5BtnXNdPeVoI54akfWz9n5f+V6Tv1Qqy5U=";
        accessTo.cadmium.giodamelio = true;
        accessTo.cesium.giodamelio = true;
      };
    };

    revocations = {
      users = []; # KRL spec lines, e.g. "id: termius-phone"
      hosts = [];
    };
  };
}
