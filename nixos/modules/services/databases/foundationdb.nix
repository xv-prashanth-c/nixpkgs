{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.foundationdb;

  # used for initial cluster configuration
  initialIpAddr = if (cfg.publicAddress != "auto") then cfg.publicAddress else "127.0.0.1";

  fdbServers = n:
    concatStringsSep "\n" (map (x: "[fdbserver.${toString (x+cfg.listenPortStart)}]") (range 0 (n - 1)));

  backupAgents = n:
    concatStringsSep "\n" (map (x: "[backup_agent.${toString x}]") (range 1 n));

  configFile = pkgs.writeText "foundationdb.conf" ''
    [general]
    cluster_file  = /etc/foundationdb/fdb.cluster

    [fdbmonitor]
    restart_delay = ${toString cfg.restartDelay}
    user          = ${cfg.user}
    group         = ${cfg.group}

    [fdbserver]
    command        = ${pkgs.foundationdb}/bin/fdbserver
    public_address = ${cfg.publicAddress}:$ID
    listen_address = ${cfg.listenAddress}
    datadir        = ${cfg.dataDir}/$ID
    logdir         = ${cfg.logDir}
    logsize        = ${cfg.logSize}
    maxlogssize    = ${cfg.maxLogSize}
    ${optionalString (cfg.class != null) "class = ${cfg.class}"}
    memory         = ${cfg.memory}
    storage_memory = ${cfg.storageMemory}

    ${optionalString (cfg.locality.machineId    != null) "locality_machineid=${cfg.locality.machineId}"}
    ${optionalString (cfg.locality.zoneId       != null) "locality_zoneid=${cfg.locality.zoneId}"}
    ${optionalString (cfg.locality.datacenterId != null) "locality_dcid=${cfg.locality.datacenterId}"}
    ${optionalString (cfg.locality.dataHall     != null) "locality_data_hall=${cfg.locality.dataHall}"}

    ${fdbServers cfg.serverProcesses}

    [backup_agent]
    command = ${pkgs.foundationdb}/libexec/backup_agent
    ${backupAgents cfg.backupProcesses}
  '';
in
{
  options.services.foundationdb = {

    enable = mkEnableOption "FoundationDB Server";

    publicAddress = mkOption {
      type        = types.str;
      default     = "auto";
      description = "Publicly visible IP address of the process. Port is determined by process ID";
    };

    listenAddress = mkOption {
      type        = types.str;
      default     = "public";
      description = "Publicly visible IP address of the process. Port is determined by process ID";
    };

    listenPortStart = mkOption {
      type          = types.int;
      default       = 4500;
      description   = ''
        Starting port number for database listening sockets. Every FDB process binds to a
        subsequent port, to this number reflects the start of the overall range. e.g. having
        8 server processes will use all ports between 4500 and 4507.
      '';
    };

    openFirewall = mkOption {
      type        = types.bool;
      default     = false;
      description = ''
        Open the firewall ports corresponding to FoundationDB processes and coordinators
        using <option>config.networking.firewall.*</option>.
      '';
    };

    dataDir = mkOption {
      type        = types.path;
      default     = "/var/lib/foundationdb";
      description = "Data directory. All cluster data will be put under here.";
    };

    logDir = mkOption {
      type        = types.path;
      default     = "/var/log/foundationdb";
      description = "Log directory.";
    };

    user = mkOption {
      type        = types.str;
      default     = "foundationdb";
      description = "User account under which FoundationDB runs.";
    };

    group = mkOption {
      type        = types.str;
      default     = "foundationdb";
      description = "Group account under which FoundationDB runs.";
    };

    class = mkOption {
      type        = types.nullOr (types.enum [ "storage" "transaction" "stateless" ]);
      default     = null;
      description = "Process class";
    };

    restartDelay = mkOption {
      type = types.int;
      default = 10;
      description = "Number of seconds to wait before restarting servers.";
    };

    logSize = mkOption {
      type        = types.string;
      default     = "10MiB";
      description = ''
        Roll over to a new log file after the current log file
        reaches the specified size.
      '';
    };

    maxLogSize = mkOption {
      type        = types.string;
      default     = "100MiB";
      description = ''
        Delete the oldest log file when the total size of all log
        files exceeds the specified size. If set to 0, old log files
        will not be deleted.
      '';
    };

    serverProcesses = mkOption {
      type = types.int;
      default = 1;
      description = "Number of fdbserver processes to run.";
    };

    backupProcesses = mkOption {
      type = types.int;
      default = 1;
      description = "Number of backup_agent processes to run for snapshots.";
    };

    memory = mkOption {
      type        = types.string;
      default     = "8GiB";
      description = ''
        Maximum memory used by the process. The default value is
        <literal>8GiB</literal>. When specified without a unit,
        <literal>MiB</literal> is assumed. This parameter does not
        change the memory allocation of the program. Rather, it sets
        a hard limit beyond which the process will kill itself and
        be restarted. The default value of <literal>8GiB</literal>
        is double the intended memory usage in the default
        configuration (providing an emergency buffer to deal with
        memory leaks or similar problems). It is not recommended to
        decrease the value of this parameter below its default
        value. It may be increased if you wish to allocate a very
        large amount of storage engine memory or cache. In
        particular, when the <literal>storageMemory</literal>
        parameter is increased, the <literal>memory</literal>
        parameter should be increased by an equal amount.
      '';
    };

    storageMemory = mkOption {
      type        = types.string;
      default     = "1GiB";
      description = ''
        Maximum memory used for data storage. The default value is
        <literal>1GiB</literal>. When specified without a unit,
        <literal>MB</literal> is assumed. Clusters using the memory
        storage engine will be restricted to using this amount of
        memory per process for purposes of data storage. Memory
        overhead associated with storing the data is counted against
        this total. If you increase the
        <literal>storageMemory</literal>, you should also increase
        the <literal>memory</literal> parameter by the same amount.
      '';
    };

    locality = mkOption {
      default = {
        machineId    = null;
        zoneId       = null;
        datacenterId = null;
        dataHall     = null;
      };

      description = ''
        FoundationDB locality settings.
      '';

      type = types.submodule ({
        options = {
          machineId = mkOption {
            default = null;
            type = types.nullOr types.str;
            description = ''
              Machine identifier key. All processes on a machine should share a
              unique id. By default, processes on a machine determine a unique id to share.
              This does not generally need to be set.
            '';
          };

          zoneId = mkOption {
            default = null;
            type = types.nullOr types.str;
            description = ''
              Zone identifier key. Processes that share a zone id are
              considered non-unique for the purposes of data replication.
              If unset, defaults to machine id.
            '';
          };

          datacenterId = mkOption {
            default = null;
            type = types.nullOr types.str;
            description = ''
              Data center identifier key. All processes physically located in a
              data center should share the id. If you are depending on data
              center based replication this must be set on all processes.
            '';
          };

          dataHall = mkOption {
            default = null;
            type = types.nullOr types.str;
            description = ''
              Data hall identifier key. All processes physically located in a
              data hall should share the id. If you are depending on data
              hall based replication this must be set on all processes.
            '';
          };
        };
      });
    };

    extraReadWritePaths = mkOption {
      default = [ ];
      type = types.listOf types.path;
      description = ''
        An extra set of filesystem paths that FoundationDB can read to
        and write from. By default, FoundationDB runs under a heavily
        namespaced systemd environment without write access to most of
        the filesystem outside of its data and log directories. By
        adding paths to this list, the set of writeable paths will be
        expanded. This is useful for allowing e.g. backups to local files,
        which must be performed on behalf of the foundationdb service.
      '';
    };

    pidfile = mkOption {
      type        = types.path;
      default     = "/run/foundationdb.pid";
      description = "Path to pidfile for fdbmonitor.";
    };
  };

  config = mkIf cfg.enable {
    meta.doc         = ./foundationdb.xml;
    meta.maintainers = with lib.maintainers; [ thoughtpolice ];

    environment.systemPackages = [ pkgs.foundationdb ];

    users.extraUsers = optionalAttrs (cfg.user == "foundationdb") (singleton
      { name        = "foundationdb";
        description = "FoundationDB User";
        uid         = config.ids.uids.foundationdb;
        group       = cfg.group;
      });

    users.extraGroups = optionalAttrs (cfg.group == "foundationdb") (singleton
      { name = "foundationdb";
        gid  = config.ids.gids.foundationdb;
      });

    networking.firewall.allowedTCPPortRanges = mkIf cfg.openFirewall
      [ { from = cfg.listenPortStart;
          to = (cfg.listenPortStart + cfg.serverProcesses) - 1;
        }
      ];

    systemd.services.foundationdb = {
      description             = "FoundationDB Service";

      after                   = [ "network.target" ];
      wantedBy                = [ "multi-user.target" ];
      unitConfig =
        { RequiresMountsFor = "${cfg.dataDir} ${cfg.logDir}";
        };

      serviceConfig =
        let rwpaths = [ cfg.dataDir cfg.logDir cfg.pidfile "/etc/foundationdb" ]
                   ++ cfg.extraReadWritePaths;
        in
        { Type       = "simple";
          Restart    = "always";
          RestartSec = 5;
          User       = cfg.user;
          Group      = cfg.group;
          PIDFile    = "${cfg.pidfile}";

          PermissionsStartOnly = true;  # setup needs root perms
          TimeoutSec           = 120;   # give reasonable time to shut down

          # Security options
          NoNewPrivileges       = true;
          ProtectHome           = true;
          ProtectSystem         = "strict";
          ProtectKernelTunables = true;
          ProtectControlGroups  = true;
          PrivateTmp            = true;
          PrivateDevices        = true;
          ReadWritePaths        = lib.concatStringsSep " " (map (x: "-" + x) rwpaths);
        };

      path = [ pkgs.foundationdb pkgs.coreutils ];

      preStart = ''
        rm -f ${cfg.pidfile}   && \
          touch ${cfg.pidfile} && \
          chown -R ${cfg.user}:${cfg.group} ${cfg.pidfile}

        for x in "${cfg.logDir}" "${cfg.dataDir}" /etc/foundationdb; do
          [ ! -d "$x" ] && mkdir -m 0700 -vp "$x" && chown -R ${cfg.user}:${cfg.group} "$x";
        done

        if [ ! -f /etc/foundationdb/fdb.cluster ]; then
            cf=/etc/foundationdb/fdb.cluster
            desc=$(tr -dc A-Za-z0-9 </dev/urandom 2>/dev/null | head -c8)
            rand=$(tr -dc A-Za-z0-9 </dev/urandom 2>/dev/null | head -c8)
            echo ''${desc}:''${rand}@${initialIpAddr}:${builtins.toString cfg.listenPortStart} > $cf
            chmod 0660 $cf && chown -R ${cfg.user}:${cfg.group} $cf
            touch "${cfg.dataDir}/.first_startup"
        fi
      '';

      script = ''
        exec fdbmonitor --lockfile ${cfg.pidfile} --conffile ${configFile};
      '';

      postStart = ''
        if [ -e "${cfg.dataDir}/.first_startup" ]; then
          fdbcli --exec "configure new single ssd"
          rm -f "${cfg.dataDir}/.first_startup";
        fi
      '';
    };
  };
}
