# Generic eco/performance power-toggle script, driven entirely by
# dotsLocal.machine.display (see modules/local/schema.nix). A host
# with no display config (dotsLocal.machine.display == null) simply
# doesn't get this script installed - no host-specific Nix file needed.
{ config, lib, pkgs, dotsLocal, ... }:

let
  cfg = dotsLocal.machine.display;
in {
  config = lib.mkIf (cfg != null) {
    home.file.".local/bin/power-toggle.sh" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Use absolute paths from the Nix store to be safe
        BOOST_FILE="/sys/devices/system/cpu/cpufreq/boost"

        if [ $(cat $BOOST_FILE) -eq 1 ]; then
          echo 0 | sudo ${pkgs.bash}/bin/tee $BOOST_FILE
          ${pkgs.wlr-randr}/bin/wlr-randr --output ${cfg.output} --mode ${cfg.ecoMode.resolution}@${cfg.ecoMode.refreshRate}
          ${pkgs.brightnessctl}/bin/brightnessctl set ${cfg.ecoMode.brightness}
          ${pkgs.libnotify}/bin/notify-send "Power" "Eco Mode"
        else
          echo 1 | sudo ${pkgs.bash}/bin/tee $BOOST_FILE
          ${pkgs.wlr-randr}/bin/wlr-randr --output ${cfg.output} --mode ${cfg.perfMode.resolution}@${cfg.perfMode.refreshRate}
          ${pkgs.libnotify}/bin/notify-send "Power" "Performance Mode"
        fi
      '';
    };

    dots.tools = [
      {
        name = "power-toggle.sh";
        synopsis = "Toggle CPU boost + display resolution/refresh/brightness between eco and performance modes.";
        feature = "features.power-toggle";
        dotsLocalSettings = [ "machine.display" ];
      }
    ];
  };
}
