{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.klipper;
  package = pkgs.klipper;
  format = pkgs.formats.ini { mkKeyValue = generators.mkKeyValueDefault {} ":"; };
in
{
  ##### interface
  options = {
    services.klipper = {
      enable = mkEnableOption "Klipper, the 3D printer firmware";

      octoprintIntegration = mkOption {
        type = types.bool;
        default = false;
        description = "Allows Octoprint to control Klipper.";
      };

      user = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          User account under which Klipper runs.

          If null is specified (default), a temporary user will be created by systemd.
        '';
      };

      group = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Group account under which Klipper runs.

          If null is specified (default), a temporary user will be created by systemd.
        '';
      };

      settings = mkOption {
        type = format.type;
        default = { };
        description = ''
          Configuration for Klipper. See the <link xlink:href="https://www.klipper3d.org/Overview.html#configuration-and-tuning-guides">documentation</link>
          for supported values.
        '';
      };
    };
  };

  ##### implementation
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.octoprintIntegration -> config.services.octoprint.enable;
        message = "Option klipper.octoprintIntegration requires Octoprint to be enabled on this system. Please enable services.octoprint to use it.";
      }
      {
        assertion = cfg.user != null -> cfg.group != null;
        message = "Option klipper.group is not set when a user is specified.";
      }
    ];

    environment.etc."klipper.cfg".source = format.generate "klipper.cfg" cfg.settings;

    services.klipper = mkIf cfg.octoprintIntegration {
      user = config.services.octoprint.user;
      group = config.services.octoprint.group;
    };

    systemd.services.klipper = {
      description = "Klipper 3D Printer Firmware";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${package}/lib/klipper/klippy.py --input-tty=/run/klipper/tty /etc/klipper.cfg";
        RuntimeDirectory = "klipper";
        SupplementaryGroups = [ "dialout" ];
        WorkingDirectory = "${package}/lib";
      } // (if cfg.user != null then {
        Group = cfg.group;
        User = cfg.user;
      } else {
        DynamicUser = true;
        User = "klipper";
      });
    };
  };
}
