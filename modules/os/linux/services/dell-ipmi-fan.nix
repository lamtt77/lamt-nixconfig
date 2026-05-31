{
  config,
  lib,
  pkgs,
  ...}:with lib; let
  cfg = config.modules.os.linux.services.dell-ipmi-fan;
in {
  options.modules.os.linux.services.dell-ipmi-fan = {
    enable = mkEnableOption "Dell IPMI Fan Control service";

    idracIpFile = mkOption {
      type = types.path;
      description = "Path to file containing iDRAC IP address";
    };

    idracUser = mkOption {
      type = types.str;
      default = "root";
      description = "Username for iDRAC";
    };

    passwordFile = mkOption {
      type = types.path;
      description = "Path to file containing iDRAC password";
    };

    sensorName = mkOption {
      type = types.str;
      default = "Exhaust";
      description = "Name of the temperature sensor to monitor";
    };

    threshold = mkOption {
      type = types.int;
      default = 42;
      description = "Temperature threshold in Celsius to trigger dynamic control";
    };

    staticSpeedHex = mkOption {
      type = types.str;
      default = "0x10"; # ~16%
      description = "Static fan speed in Hex (e.g., 0x10)";
    };

    interval = mkOption {
      type = types.str;
      default = "*:0/15"; # Every 15 minutes
      description = "Systemd calendar interval for the check";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.dell-ipmi-fan-control = {
      description = "Dell IPMI Fan Control Service";
      path = with pkgs; [ipmitool gnugrep coreutils gawk];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };

      script = ''
        # Read IP from file (trimming whitespace)
        IDRACIP=$(cat "${cfg.idracIpFile}" | tr -d '\n')
        IDRACUSER="${cfg.idracUser}"
        # Read password from file (trimming whitespace)
        IDRACPASSWORD=$(cat "${cfg.passwordFile}" | tr -d '\n')
        SENSORNAME="${cfg.sensorName}"
        TEMPTHRESHOLD="${toString cfg.threshold}"
        STATICSPEEDBASE16="${cfg.staticSpeedHex}"

        # Get temperature
        RAW_DATA=$(ipmitool -I lanplus -H "$IDRACIP" -U "$IDRACUSER" -P "$IDRACPASSWORD" sdr type temperature)
        IPMI_RC=$?

        if [ $IPMI_RC -ne 0 ]; then
          echo "Error: Failed to contact iDRAC at $IDRACIP. Ret code: $IPMI_RC"
          exit 1
        fi

        # Extract temperature.
        # Example output line: "Inlet Temp | 04h | ok  |  7.1 | 24 degrees C"
        CURRENT_TEMP=$(echo "$RAW_DATA" | grep "$SENSORNAME" | awk -F'|' '{print $5}' | awk '{print $1}')

        echo "Current Temperature for $SENSORNAME: $CURRENT_TEMP C (Threshold: $TEMPTHRESHOLD C)"

        if [ -z "$CURRENT_TEMP" ] || [ "$CURRENT_TEMP" = "No" ]; then
           echo "Could not read valid temperature. Aborting."
           exit 1
        fi

        if [ "$CURRENT_TEMP" -gt "$TEMPTHRESHOLD" ]; then
          echo "Temperature > Threshold. Enabling dynamic fan control (Dell default)."
          ipmitool -I lanplus -H "$IDRACIP" -U "$IDRACUSER" -P "$IDRACPASSWORD" raw 0x30 0x30 0x01 0x01
        else
          echo "Temperature <= Threshold. Disabling dynamic fan control and setting static speed to $STATICSPEEDBASE16."
          ipmitool -I lanplus -H "$IDRACIP" -U "$IDRACUSER" -P "$IDRACPASSWORD" raw 0x30 0x30 0x01 0x00
          ipmitool -I lanplus -H "$IDRACIP" -U "$IDRACUSER" -P "$IDRACPASSWORD" raw 0x30 0x30 0x02 0xff $STATICSPEEDBASE16
        fi
      '';
    };

    systemd.timers.dell-ipmi-fan-control = {
      description = "Timer for Dell IPMI Fan Control";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };

    environment.systemPackages = [ pkgs.ipmitool ];
  };
}
