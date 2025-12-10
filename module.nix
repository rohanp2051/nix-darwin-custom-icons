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
            stripMacl = mkOption {
              type = types.bool;
              default = false;
              description = "Temporarily strip com.apple.macl to set icon, then restore it";
            };
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
                  local strip_macl="$3"

                  if [ ! -e "$dest_path" ]; then
                    echo "  ⚠ Skipping: $dest_path (not found)"
                    return 0
                  fi

                  # Save and strip macl if requested
                  local macl_value=""
                  if [ "$strip_macl" = "true" ]; then
                    if xattr -px com.apple.macl "$dest_path" >/dev/null 2>&1; then
                      macl_value=$(xattr -px com.apple.macl "$dest_path" 2>/dev/null)
                      sudo xattr -dr com.apple.macl "$dest_path" 2>/dev/null
                    fi
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

                  # Restore macl if we saved it
                  if [ -n "$macl_value" ]; then
                    sudo xattr -wx com.apple.macl "$macl_value" "$dest_path" 2>/dev/null
                  fi

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
                    set_icon "${iconCfg.icon}" "${iconCfg.path}" "${
                      if iconCfg.stripMacl then "true" else "false"
                    }" || true
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
                  echo "⚠ The following apps require an overlay or stripMacl = true:"
                  for app in "''${failed_apps[@]}"; do
                    echo "  - $app"
                  done
                  echo ""
                  echo "These apps have com.apple.macl protection. Either add 'stripMacl = true'"
                  echo "to temporarily bypass it, or use a nixpkgs overlay to set the icon at build time."
                fi
                echo "custom icons applied"
      '';
    })
  ];
}
