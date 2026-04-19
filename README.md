# ctrlnix-rpi4-rt

PREEMPT_RT kernel and EtherCAT IGH master for Raspberry Pi 4 on NixOS.

## Binary Cache

Pre-built binaries are available via Cachix - no need to compile yourself:

```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://cognibotics.cachix.org"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cognibotics.cachix.org-1:qcwFFasLKhSxQEKC5tgb/0+HIFlie3kc+PpPQSxlBv4="
  ];
};
```

## Usage

Add this flake as an input to your NixOS configuration:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    rpi4-rt.url = "github:YOUR_ORG/nixos-rpi4-rt";
  };

  outputs = { self, nixpkgs, rpi4-rt }: {
    nixosConfigurations.mypi = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./configuration.nix
        {
          nixpkgs.overlays = [ rpi4-rt.overlays.default ];
          boot.kernelPackages    = pkgs.linuxPackages-rt-rpi4;
          boot.extraModulePackages = [ pkgs.ethercat-kmod-rpi4 ];
          environment.systemPackages = [ pkgs.ethercat-userspace-rpi4 ];
        }
      ];
    };
  };
}
```

## What's included

| Package | Description |
|---------|-------------|
| `kernel` | Linux RPi4 kernel with `PREEMPT_RT`, `RCU_BOOST` |
| `ethercat-kmod` | EtherCAT IGH master 1.6.9 kernel module |
| `ethercat-userspace` | EtherCAT IGH userspace tools (`ethercat` CLI) |

## Kernel configuration

- `PREEMPT_RT=yes` - Full real-time preemption
- `PREEMPT=no` - Disabled (replaced by PREEMPT_RT)
- `PREEMPT_VOLUNTARY=no` - Disabled (replaced by PREEMPT_RT)
- `RCU_BOOST=yes` - RCU priority boosting for RT tasks

Linux 6.12+ has PREEMPT_RT merged into mainline - no external patch needed.

## EtherCAT

EtherCAT IGH master 1.6.9 built against the RT kernel.
Set your NIC MAC address in your configuration:

```nix
boot.extraModprobeConfig = ''
  options ec_master main_devices=XX:XX:XX:XX:XX:XX
'';
boot.kernelModules = [ "ec_master" "ec_generic" ];
```
