{
  description = "PREEMPT_RT kernels and EtherCAT IGH master for NixOS (aarch64 + x86_64)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }: let
    lib = nixpkgs.lib;

    # ─── Shared RT kernel config ──────────────────────────────────────
    # Applied to all three kernels. PREEMPT_VOLUNTARY is intentionally
    # absent: it is a valid option in 6.12 but was removed in 6.18, so
    # leaving it out keeps the config compatible with both versions.
    rtKernelConfig = with lib.kernel; {
      PREEMPT_RT = yes;
      PREEMPT    = lib.mkForce no;
      RCU_BOOST  = yes;
    };

    # ─── x86 6.18 extra overrides ─────────────────────────────────────
    # DRM_I915_GVT and DRM_I915_GVT_KVMGT were removed in 6.18 but are
    # still present in the nixpkgs base config, causing build errors.
    rtKernelConfigX86_618 = rtKernelConfig // (with lib.kernel; {
      DRM_I915_GVT       = lib.mkForce (option no);
      DRM_I915_GVT_KVMGT = lib.mkForce (option no);
    });

    # ─── EtherCAT IGH 1.6.9 source (shared by all builds) ────────────
    ethercatSrc = {
      owner = "etherlab.org";
      repo  = "ethercat";
      rev   = "b709e58147e65b5e3251b45f48c01ef33cc7366f";
      hash  = "sha256-Msx0i1SAwlSMD3+vjGRNe36Yx9qdUYokVekGytZptqk=";
    };

    # ─── Helper: build EtherCAT kmod against a kernel package set ─────
    mkEthercatKmod = linuxPackages: pkgs:
      linuxPackages.callPackage
        ({ stdenv, fetchFromGitLab, kernel, automake, autoconf, libtool, pkgconf }:
        stdenv.mkDerivation {
          pname   = "ethercat-kmod";
          version = "1.6.9";
          src = fetchFromGitLab ethercatSrc;
          nativeBuildInputs = [ automake autoconf libtool pkgconf ]
            ++ kernel.moduleBuildDependencies;
          preConfigure = "bash ./bootstrap";
          configureFlags = [
            "--enable-generic"
            "--with-linux-dir=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
          ];
          buildPhase = ''
            make
            make -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" \
              M=$(pwd) modules
          '';
          installPhase = ''
            mkdir -p $out
            make -C "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" \
              M=$(pwd) INSTALL_MOD_PATH=$out modules_install
          '';
        }) { fetchFromGitLab = pkgs.fetchFromGitLab; };

    # ─── Helper: build EtherCAT userspace tools ───────────────────────
    mkEthercatUserspace = linuxPackages: pkgs:
      pkgs.stdenv.mkDerivation {
        pname   = "ethercat-userspace";
        version = "1.6.9";
        src = pkgs.fetchFromGitLab ethercatSrc;
        nativeBuildInputs = with pkgs; [ automake autoconf libtool pkgconf ];
        preConfigure = "bash ./bootstrap";
        configureFlags = [
          "--enable-generic"
          "--with-linux-dir=${linuxPackages.kernel.dev}/lib/modules/${linuxPackages.kernel.modDirVersion}/build"
        ];
        installPhase = "make install prefix=$out";
      };

    # ─── Helper: build a complete set of three packages for one kernel ─
    mkKernelPackages = linuxPackages: pkgs: rec {
      kernel             = linuxPackages.kernel;
      ethercat-kmod      = mkEthercatKmod linuxPackages pkgs;
      ethercat-userspace = mkEthercatUserspace linuxPackages pkgs;
      default            = kernel;
    };

    # ─── aarch64: RPi4 kernel 6.12 ────────────────────────────────────
    pkgs-aarch64 = nixpkgs.legacyPackages."aarch64-linux";

    linuxPackages-rt-rpi4-612 = pkgs-aarch64.linuxPackages_rpi4.extend (_: super: {
      kernel = super.kernel.override {
        structuredExtraConfig = rtKernelConfig;
      };
    });

    # ─── x86_64: vanilla kernel 6.12 ──────────────────────────────────
    pkgs-x86 = nixpkgs.legacyPackages."x86_64-linux";

    linuxPackages-rt-x86-612 = pkgs-x86.linuxPackages_6_12.extend (_: super: {
      kernel = super.kernel.override {
        structuredExtraConfig = rtKernelConfig;
      };
    });

    # ─── x86_64: vanilla kernel 6.18 ──────────────────────────────────
    linuxPackages-rt-x86-618 = pkgs-x86.linuxPackages_6_18.extend (_: super: {
      kernel = super.kernel.override {
        structuredExtraConfig = rtKernelConfigX86_618;
      };
    });

  in {
    # ─── Packages ─────────────────────────────────────────────────────
    packages."aarch64-linux" = {
      # RPi4 kernel 6.12 with PREEMPT_RT
      kernel-rpi4-612             = linuxPackages-rt-rpi4-612.kernel;
      ethercat-kmod-rpi4-612      = mkEthercatKmod linuxPackages-rt-rpi4-612 pkgs-aarch64;
      ethercat-userspace-rpi4-612 = mkEthercatUserspace linuxPackages-rt-rpi4-612 pkgs-aarch64;
      default                     = linuxPackages-rt-rpi4-612.kernel;
    };

    packages."x86_64-linux" = {
      # x86 kernel 6.12 with PREEMPT_RT
      kernel-x86-612             = linuxPackages-rt-x86-612.kernel;
      ethercat-kmod-x86-612      = mkEthercatKmod linuxPackages-rt-x86-612 pkgs-x86;
      ethercat-userspace-x86-612 = mkEthercatUserspace linuxPackages-rt-x86-612 pkgs-x86;

      # x86 kernel 6.18 with PREEMPT_RT
      kernel-x86-618             = linuxPackages-rt-x86-618.kernel;
      ethercat-kmod-x86-618      = mkEthercatKmod linuxPackages-rt-x86-618 pkgs-x86;
      ethercat-userspace-x86-618 = mkEthercatUserspace linuxPackages-rt-x86-618 pkgs-x86;

      default = linuxPackages-rt-x86-618.kernel;
    };

    # ─── Overlay ──────────────────────────────────────────────────────
    # Usage in your NixOS flake:
    #
    #   inputs.rt.url = "github:YOUR_ORG/ctrlnix-rt";
    #   nixpkgs.overlays = [ inputs.rt.overlays.default ];
    #
    #   # aarch64 (RPi4, 6.12):
    #   boot.kernelPackages      = pkgs.linuxPackages-rt-rpi4-612;
    #   boot.extraModulePackages = [ pkgs.ethercat-kmod-rpi4-612 ];
    #
    #   # x86_64 (6.12):
    #   boot.kernelPackages      = pkgs.linuxPackages-rt-x86-612;
    #   boot.extraModulePackages = [ pkgs.ethercat-kmod-x86-612 ];
    #
    #   # x86_64 (6.18):
    #   boot.kernelPackages      = pkgs.linuxPackages-rt-x86-618;
    #   boot.extraModulePackages = [ pkgs.ethercat-kmod-x86-618 ];
    #
    overlays.default = final: prev: {
      linuxPackages-rt-rpi4-612   = linuxPackages-rt-rpi4-612;
      ethercat-kmod-rpi4-612      = mkEthercatKmod linuxPackages-rt-rpi4-612 prev;
      ethercat-userspace-rpi4-612 = mkEthercatUserspace linuxPackages-rt-rpi4-612 prev;

      linuxPackages-rt-x86-612    = linuxPackages-rt-x86-612;
      ethercat-kmod-x86-612       = mkEthercatKmod linuxPackages-rt-x86-612 prev;
      ethercat-userspace-x86-612  = mkEthercatUserspace linuxPackages-rt-x86-612 prev;

      linuxPackages-rt-x86-618    = linuxPackages-rt-x86-618;
      ethercat-kmod-x86-618       = mkEthercatKmod linuxPackages-rt-x86-618 prev;
      ethercat-userspace-x86-618  = mkEthercatUserspace linuxPackages-rt-x86-618 prev;
    };
  };
}