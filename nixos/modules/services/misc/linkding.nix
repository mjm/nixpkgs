{ config
, pkgs
, lib
, ...
}:

let
  inherit
    (lib)
    boolToString
    isBool
    mapAttrs
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    optional
    types
    ;

  cfg = config.services.linkding;
  pkg = cfg.package;

  env = {
    LD_DATA_DIR = cfg.dataDir;
  } // (mapAttrs (_: s: if isBool s then boolToString s else toString s) cfg.settings);

  uwsgi = cfg.uwsgi.package.override { plugins = [ "python3" ]; };
  uwsgiCfg = pkgs.writeText "linkding-uwsgi.ini" ''
    [uwsgi]
    need-plugin = python3
    module = siteroot.wsgi:application
    env = DJANGO_SETTINGS_MODULE=siteroot.settings.prod
    static-map = /static=${pkg}/lib/linkding/static
    static-map = /static=${cfg.dataDir}/favicons
    processes = 2
    threads = 2
    vacuum = True
    buffer-size = 8192
    die-on-term = true

    if-env = LD_CONTEXT_PATH
    static-map = /%(_)static=static
    static-map = /%(_)static=data/favicons
    endif =

    if-env = LD_REQUEST_TIMEOUT
    http-timeout = %(_)
    socket-timeout = %(_)
    harakiri = %(_)
    endif =

    if-env = LD_LOG_X_FORWARDED_FOR
    log-x-forwarded-for = %(_)
    endif =
  '';
in
{
  meta.maintainers = with lib.maintainers; [ mjm ];

  options.services.linkding = {
    enable = mkEnableOption "linkding";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/linkding";
      description = "Directory to use to store linkding data, such as favicons and the SQLite database.";
    };

    address = mkOption {
      type = types.str;
      default = "localhost";
      description = "Web interface listen address.";
    };

    port = mkOption {
      type = types.port;
      default = 9090;
      description = "Web interface port.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the firewall for the web interface port.";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType =
          with types;
          attrsOf (oneOf [
            bool
            float
            int
            str
            path
            package
          ]);
      };
      default = { };
      description = ''
        Extra linkding config options.

        These will be set as environment variables when running linkding.
        See [the documentation](https://github.com/sissbruecker/linkding/blob/master/docs/Options.md)
        for valid options.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/linkding.env";
      description = ''
        Additional environment file as defined in {manpage}`systemd.exec(5)`.

        Can be used to pass sensitive config options (like database credentials when
        connecting to an external PostgreSQL database) without making them available
        to the world-readable Nix store.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "linkding";
      description = "User under which linkding runs.";
    };

    package = mkPackageOption pkgs "linkding" { };

    uwsgi.package = mkPackageOption pkgs "uwsgi" { };
  };

  config = mkIf cfg.enable {
    users = mkIf (cfg.user == "linkding") {
      users.linkding = {
        isSystemUser = true;
        group = "linkding";
        home = cfg.dataDir;
      };

      groups.linkding = { };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.linkding = {
      description = "Linkding bookmarks manager";
      wantedBy = [ "multi-user.target" ];
      wants = [ "linkding-tasks.service" ];
      after = [ "network.target" ];
      preStart = ''
        ${pkg}/bin/linkding migrate
        ${pkg}/bin/linkding enable_wal
        (cd ${cfg.dataDir} && ${pkg}/bin/linkding generate_secret_key)
        ${pkg}/bin/linkding create_initial_superuser
      '';
      script = ''
        exec ${uwsgi}/bin/uwsgi --http ${cfg.address}:${toString cfg.port} ${uwsgiCfg}
      '';
      serviceConfig = {
        User = cfg.user;
        Restart = "on-failure";
        StateDirectory = mkIf (cfg.dataDir == "/var/lib/linkding") "linkding";
        WorkingDirectory = "${pkg}/lib/linkding";
        EnvironmentFile = optional (cfg.environmentFile != null) cfg.environmentFile;
      };
      environment = env // {
        PYTHONPATH = "${pkg.python.pkgs.makePythonPath pkg.propagatedBuildInputs}:${pkg}/lib/linkding";
      };
    };

    systemd.services.linkding-tasks = {
      description = "Linkding background task worker";
      after = [ "linkding.service" ];
      preStart = ''
        mkdir -p ${cfg.dataDir}
      '';
      script = ''
        ${pkg}/bin/linkding clean_tasks
        exec ${pkg}/bin/linkding process_tasks
      '';
      serviceConfig = {
        User = cfg.user;
        Restart = "on-failure";
        StateDirectory = mkIf (cfg.dataDir == "/var/lib/linkding") "linkding";
        EnvironmentFile = optional (cfg.environmentFile != null) cfg.environmentFile;
      };
      environment = env;
    };
  };
}
