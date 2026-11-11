{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  makeWrapper,
  autoPatchelfHook,
  wrapGAppsHook3,
  # runtime / dlopen'd libraries
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libcap_ng,
  libGL,
  libdrm,
  libgbm,
  libnotify,
  libseccomp,
  libpulseaudio,
  libsecret,
  libuuid,
  libxkbcommon,
  mesa,
  nss,
  nspr,
  pango,
  pipewire,
  qemu,
  OVMF,
  systemd,
  virtiofsd,
  vulkan-loader,
  xdg-utils,
  # X libraries
  libX11,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libXrandr,
  libXrender,
  libXScrnSaver,
  libXtst,
  libxcb,
}:

let
  pname = "claude-desktop";
  version = "5.1231.2";

  # Anthropic's apt pool: https://downloads.claude.ai/claude-desktop/apt/stable
  # Hashes come from dists/stable/main/binary-<arch>/Packages.
  srcs = {
    x86_64-linux = fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
      hash = "sha256:eb4d16c9aff0a696366d88728f74fa55136be7cfde3c1fe35af4062b45955b6f";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_arm64.deb";
      hash = "sha256:d7a0144e6946975e6c5f33a48db08cbe08bccda04bdb19cf2254aa690bce25c1";
    };
  };
in
stdenv.mkDerivation {
  inherit pname version;

  src =
    srcs.${stdenv.hostPlatform.system}
      or (throw "claude-desktop: unsupported system ${stdenv.hostPlatform.system}");

  nativeBuildInputs = [
    dpkg
    makeWrapper
    autoPatchelfHook
    wrapGAppsHook3
  ];

  # Libraries autoPatchelfHook links against, plus ones Chromium dlopen's at
  # runtime (added to the wrapper's LD_LIBRARY_PATH below via runtimeDependencies).
  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libcap_ng
    libGL
    libdrm
    libgbm
    libnotify
    libpulseaudio
    libseccomp
    libsecret
    libuuid
    libxkbcommon
    mesa
    nss
    nspr
    pango
    pipewire
    systemd
    vulkan-loader
    libX11
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libXrandr
    libXrender
    libXScrnSaver
    libXtst
    libxcb
  ];

  # Chromium dlopen's these; they must be on LD_LIBRARY_PATH at runtime.
  runtimeDependencies = [
    (lib.getLib systemd)
    libGL
    libgbm
    mesa
    vulkan-loader
  ];

  # The .deb is a data archive; dpkg-deb -x unpacks it, no configure/build needed.
  dontConfigure = true;
  dontBuild = true;

  # --no-same-permissions so tar doesn't try to restore chrome-sandbox's setuid
  # bit (rwsr-xr-x), which fails in the unprivileged build sandbox.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-owner --no-same-permissions -f -
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r usr/lib "$out/lib"
    cp -r usr/share "$out/share"

    # Cowork requires QEMU UEFI firmware. Keep the firmware in the runtime
    # closure alongside the executables exposed through the launcher wrapper.
    mkdir -p "$out/share/OVMF"
    ln -s "${OVMF.fd}/FV/"* "$out/share/OVMF/"

    # chrome-sandbox in the Nix store cannot be setuid-root, so Chromium falls
    # back to its unprivileged user-namespace sandbox (default-enabled on NixOS).
    # Remove the unusable helper so it isn't picked and mis-reported.
    rm -f "$out/lib/claude-desktop/chrome-sandbox"

    # Launcher: the bundled Electron binary must run with resources/ alongside it.
    makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libGL libgbm vulkan-loader ]}" \
      --suffix PATH : "${lib.makeBinPath [ qemu virtiofsd xdg-utils ]}"

    # Point the .desktop entry at our wrapper.
    substituteInPlace "$out/share/applications/com.anthropic.Claude.desktop" \
      --replace-warn "Exec=claude-desktop" "Exec=$out/bin/claude-desktop"

    runHook postInstall
  '';

  meta = {
    description = "Claude Desktop app for Linux (Chat, Cowork, and Claude Code)";
    homepage = "https://claude.com/download";
    downloadPage = "https://code.claude.com/docs/en/desktop-linux";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "claude-desktop";
  };
}
