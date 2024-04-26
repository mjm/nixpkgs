{ config, lib, pkgs, utils, ... }:

with lib;
let

  dataDir = "/var/lib/consul";
  cfg = config.services.consul;

  configOptions = {
    data_dir = dataDir;
    ui_config = {
      enabled = cfg.webUi;
    };
  } // cfg.extraConfig;

  jsonFormat = pkgs.formats.json { };
  enabledServices = attrValues (filterAttrs (_: svc: svc.enable) cfg.services);
  servicesCfg = jsonFormat.generate "consul-services.json" {
    services = map (filterAttrs (k: _: k != "enable")) enabledServices;
  };

  configFiles = [ "/etc/consul.json" "/etc/consul-addrs.json" ]
    ++ (optional (enabledServices != [ ]) "/etc/consul-services.json")
    ++ cfg.extraConfigFiles;

  devices = attrValues (filterAttrs (_: i: i != null) cfg.interface);
  systemdDevices = forEach devices
    (i: "sys-subsystem-net-devices-${utils.escapeSystemdPath i}.device");
in
{
  options = {

    services.consul = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enables the consul daemon.
        '';
      };

      package = mkPackageOption pkgs "consul" { };

      webUi = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enables the web interface on the consul http port.
        '';
      };

      leaveOnStop = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If enabled, causes a leave action to be sent when closing consul.
          This allows a clean termination of the node, but permanently removes
          it from the cluster. You probably don't want this option unless you
          are running a node which going offline in a permanent / semi-permanent
          fashion.
        '';
      };

      interface = {

        advertise = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            The name of the interface to pull the advertise_addr from.
          '';
        };

        bind = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            The name of the interface to pull the bind_addr from.
          '';
        };
      };

      forceAddrFamily = mkOption {
        type = types.enum [ "any" "ipv4" "ipv6" ];
        default = "any";
        description = ''
          Whether to bind ipv4/ipv6 or both kind of addresses.
        '';
      };

      forceIpv4 = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Deprecated: Use consul.forceAddrFamily instead.
          Whether we should force the interfaces to only pull ipv4 addresses.
        '';
      };

      dropPrivileges = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the consul agent should be run as a non-root consul user.
        '';
      };

      extraConfig = mkOption {
        default = { };
        type = types.attrsOf types.anything;
        description = ''
          Extra configuration options which are serialized to json and added
          to the config.json file.
        '';
      };

      extraConfigFiles = mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = ''
          Additional configuration files to pass to consul
          NOTE: These will not trigger the service to be restarted when altered.
        '';
      };

      alerts = {
        enable = mkEnableOption "consul-alerts";

        package = mkPackageOption pkgs "consul-alerts" { };

        listenAddr = mkOption {
          description = "Api listening address.";
          default = "localhost:9000";
          type = types.str;
        };

        consulAddr = mkOption {
          description = "Consul api listening address";
          default = "localhost:8500";
          type = types.str;
        };

        watchChecks = mkOption {
          description = "Whether to enable check watcher.";
          default = true;
          type = types.bool;
        };

        watchEvents = mkOption {
          description = "Whether to enable event watcher.";
          default = true;
          type = types.bool;
        };
      };

      services = mkOption {
        description = "Services to automatically register with this consul agent.";
        default = { };
        type = types.attrsOf (types.submodule ({ name, ... }: {
          freeformType = jsonFormat.type;

          options = {
            enable = mkOption {
              description = "Whether to register this service. Can be set to `false` to stop registering a service without removing it from your config.";
              default = true;
              type = types.bool;
            };

            id = mkOption {
              description = "ID for this instance of the service.";
              default = "${name}:${config.networking.hostName}";
              defaultText = literalExpression ''"''${name}:''${config.networking.hostName}"'';
              type = types.str;
            };

            name = mkOption {
              description = "The name of the service to register.";
              default = name;
              type = types.str;
            };
          };
        }));
      };

    };

  };

  config = mkIf cfg.enable (
    mkMerge [{

      users.users.consul = {
        description = "Consul agent daemon user";
        isSystemUser = true;
        group = "consul";
        # The shell is needed for health checks
        shell = "/run/current-system/sw/bin/bash";
      };
      users.groups.consul = {};

      environment = {
        etc."consul.json".text = builtins.toJSON configOptions;
        # We need consul.d to exist for consul to start
        etc."consul.d/dummy.json".text = "{ }";
        systemPackages = [ cfg.package ];
      };

      warnings = lib.flatten [
        (lib.optional (cfg.forceIpv4 != null) ''
          The option consul.forceIpv4 is deprecated, please use
          consul.forceAddrFamily instead.
        '')
      ];

      systemd.services.consul = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ] ++ systemdDevices;
        bindsTo = systemdDevices;
        restartTriggers = [ config.environment.etc."consul.json".source ]
          ++ mapAttrsToList (_: d: d.source)
            (filterAttrs (n: _: hasPrefix "consul.d/" n) config.environment.etc);

        serviceConfig = {
          ExecStart = "@${lib.getExe cfg.package} consul agent -config-dir /etc/consul.d"
            + concatMapStrings (n: " -config-file ${n}") configFiles;
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          PermissionsStartOnly = true;
          User = if cfg.dropPrivileges then "consul" else null;
          Restart = "on-failure";
          TimeoutStartSec = "infinity";
        } // (optionalAttrs (cfg.leaveOnStop) {
          ExecStop = "${lib.getExe cfg.package} leave";
        });

        path = with pkgs; [ iproute2 gawk cfg.package ];
        preStart = let
          family = if cfg.forceAddrFamily == "ipv6" then
            "-6"
          else if cfg.forceAddrFamily == "ipv4" then
            "-4"
          else
            "";
        in ''
          mkdir -m 0700 -p ${dataDir}
          chown -R consul ${dataDir}

          # Determine interface addresses
          getAddrOnce () {
            ip ${family} addr show dev "$1" scope global \
              | awk -F '[ /\t]*' '/inet/ {print $3}' | head -n 1
          }
          getAddr () {
            ADDR="$(getAddrOnce $1)"
            LEFT=60 # Die after 1 minute
            while [ -z "$ADDR" ]; do
              sleep 1
              LEFT=$(expr $LEFT - 1)
              if [ "$LEFT" -eq "0" ]; then
                echo "Address lookup timed out"
                exit 1
              fi
              ADDR="$(getAddrOnce $1)"
            done
            echo "$ADDR"
          }
          echo "{" > /etc/consul-addrs.json
          delim=" "
        ''
        + concatStrings (flip mapAttrsToList cfg.interface (name: i:
          optionalString (i != null) ''
            echo "$delim \"${name}_addr\": \"$(getAddr "${i}")\"" >> /etc/consul-addrs.json
            delim=","
          ''))
        + ''
          echo "}" >> /etc/consul-addrs.json
        '';
      };
    }

    # deprecated
    (mkIf (cfg.forceIpv4 != null && cfg.forceIpv4) {
      services.consul.forceAddrFamily = "ipv4";
    })

    (mkIf (enabledServices != [ ]) {
      environment.etc."consul-services.json".source = servicesCfg;
      systemd.services.consul.reloadTriggers = [ servicesCfg ];
    })

    (mkIf (cfg.alerts.enable) {
      systemd.services.consul-alerts = {
        wantedBy = [ "multi-user.target" ];
        after = [ "consul.service" ];

        path = [ cfg.package ];

        serviceConfig = {
          ExecStart = ''
            ${lib.getExe cfg.alerts.package} start \
              --alert-addr=${cfg.alerts.listenAddr} \
              --consul-addr=${cfg.alerts.consulAddr} \
              ${optionalString cfg.alerts.watchChecks "--watch-checks"} \
              ${optionalString cfg.alerts.watchEvents "--watch-events"}
          '';
          User = if cfg.dropPrivileges then "consul" else null;
          Restart = "on-failure";
        };
      };
    })

  ]);
}
