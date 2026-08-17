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
  systemd,
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
  version = "1.30096.1";

  # Anthropic's apt pool: https://downloads.claude.ai/claude-desktop/apt/stable
  # Hashes come from dists/stable/main/binary-<arch>/Packages.
  srcs = {
    x86_64-linux = fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_amd64.deb";
      hash = "sha256:09e41a20a5b47ea0e5bc226d4fffa77af43ad450c7cbf5e66e56d6e4fd4ad2e9";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_arm64.deb";
      hash = "sha256:16949f5c06387806bd01eb1b2b402af8ed515d37e4ffc6f2d6aae5808af873c8";
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

    # chrome-sandbox in the Nix store cannot be setuid-root, so Chromium falls
    # back to its unprivileged user-namespace sandbox (default-enabled on NixOS).
    # Remove the unusable helper so it isn't picked and mis-reported.
    rm -f "$out/lib/claude-desktop/chrome-sandbox"

    # Launcher: the bundled Electron binary must run with resources/ alongside it.
    makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libGL libgbm vulkan-loader ]}" \
      --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}"

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
