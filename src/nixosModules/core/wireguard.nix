{homelab, ...}: {
  pkgs,
  config,
  ...
}: let
  inherit (pkgs) lib;
  hostname = config.networking.hostName;

  # Get a network from a machine
  getNetwork = host: networkName:
    lib.attrsets.attrByPath [host "wireguard" networkName] null homelab.machines;

  # Get a list of the names of the networks this host belongs to
  networks = builtins.attrNames homelab.machines."${hostname}".wireguard;
in {
  # Make the Wireguard tools available
  environment.systemPackages = with pkgs; [
    wireguard-tools
    qrencode
  ];

  # Load the keys for each network
  age.secrets = builtins.listToAttrs (builtins.map (networkName: {
      name = "wireguard_${hostname}_${networkName}_key";
      value = {file = ../../../. + "secrets/wireguard/${hostname}/${networkName}.key.age";};
    })
    networks);

  # Open up firewall ports for each network
  networking.firewall = {
    enable = true;
    allowedUDPPorts = builtins.map (networkName: (getNetwork hostname networkName).port) networks;
  };

  # Setup a wireguard config for each netwo
  networking.wg-quick.interfaces = let
    # A list of the names of the machines in our lab
    machines = builtins.attrNames homelab.machines;

    # Convert a network to a peer
    networkToPeer = network:
      {
        allowedIPs = network.address;
        inherit (network) publicKey;
      }
      # Add in the endpoint if it exists
      // lib.attrsets.optionalAttrs
      (builtins.hasAttr "endpoint" network)
      {endpoint = "${network.endpoint}:${toString network.port}";}
      # Add in persistantKeepalive if it exists
      // lib.attrsets.optionalAttrs
      (builtins.hasAttr "persistentKeepalive" network)
      {inherit (network) persistentKeepalive;};

    # Convert a network to a interface
    networkToInterface = networkName: network: peers: let
      keyName = "wireguard_${hostname}_${networkName}_key";
    in
      assert lib.asserts.assertMsg
      (builtins.hasAttr keyName config.age.secrets)
      "A private key must exist for machine:${hostname} network:${networkName}"; {
        listenPort = network.port;
        inherit (network) address;
        privateKeyFile = config.age.secrets."${keyName}".path;
        inherit peers;
      };

    # Get a list of peers for a network
    getPeers = networkName:
      lib.lists.foldr (
        machineName: peers: let
          network = getNetwork machineName networkName;
        in
          # If a machine is not part of the network ignore it
          if builtins.isNull network
          then peers
          # If the machine is this machine ignore it
          else if machineName == hostname
          then peers
          # Otherwise add it to the peers
          else peers ++ [(networkToPeer network)]
      )
      []
      machines;

    # Convert a network name to a interfaceConfig
    networkNameToConfig = networkName: let
      network = getNetwork hostname networkName;
    in {
      name = network.interface;
      value = networkToInterface networkName network (getPeers networkName);
    };
  in
    builtins.listToAttrs (builtins.map networkNameToConfig networks);
}
