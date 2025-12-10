{ lib, config, ... }:
let
  cfg = config.environment.customIcons;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
in
{
  options.environment.customIcons = {
    enable = mkEnableOption "environment.customIcons";
    clearCacheOnActivation = mkEnableOption "environment.customIcons.clearCacheOnActivation";
    icons = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            path = mkOption { type = types.str; };
            icon = mkOption { type = types.path; };
          };
        }
      );
      default = [ ];
      description = "List of custom icon configurations";
    };
  };
  config = mkMerge [
    (mkIf cfg.enable {
      system.activationScripts.extraActivation.text = ''
                echo "applying custom icons..."
                failed_apps=()
                set_icon() {
                  local icon_path="$1"
                  local dest_path="$2"
                  if [ ! -e "$dest_path" ]; then
                    echo "  ⚠ Skipping: $dest_path (not found)"
                    return 0
                  fi
                  local result
                  result=$(osascript <<EOF 2>&1
                    use framework "Cocoa"
                    set iconPath to "$icon_path"
                    set destPath to "$dest_path"
                    set imageData to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
                    if imageData is missing value then
                      error "Failed to load icon image"
                    end if
                    set success to (current application's NSWorkspace's sharedWorkspace()'s setIcon:imageData forFile:destPath options:2)
                    if success then
                      return "ok"
                    else
                      error "NSWorkspace setIcon returned false"
                    end if
        EOF
                  )
                  local exit_code=$?
                  if [ $exit_code -ne 0 ]; then
                    echo "  ✗ Failed: $dest_path"
                    echo "    Error: $result"
                    failed_apps+=("$dest_path")
                    return 0
                  fi
                  echo "  ✓ Set icon: $dest_path"
                  return 0
                }
                ${builtins.concatStringsSep "\n" (
                  builtins.map (iconCfg: ''
                    set_icon "${iconCfg.icon}" "${iconCfg.path}" || true
                  '') cfg.icons
                )}
                ${lib.optionalString cfg.clearCacheOnActivation ''
                  echo "clearing icon cache..."
                  sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
                  sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -o -name com.apple.iconservices -o -name com.apple.iconservicesagent \) -exec rm -rf {} \; 2>/dev/null || true
                  killall Dock 2>/dev/null || true
                  echo "  ✓ Icon cache cleared"
                ''}
                if [ ''${#failed_apps[@]} -gt 0 ]; then
                  echo ""
                  echo "⚠ The following apps require an overlay to change their icons:"
                  for app in "''${failed_apps[@]}"; do
                    echo "  - $app"
                  done
                  echo ""
                  echo "These apps have com.apple.macl protection. Use a nixpkgs overlay to"
                  echo "replace the icon at build time instead of runtime."
                fi
                echo "custom icons applied"
      '';
    })
  ];
}
