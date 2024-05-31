{
  lib,
  mkKdeDerivation,
  fetchFromGitLab,
  substituteAll,
  xorg,
  pkg-config,
  spirv-tools,
  qtsvg,
  qtwayland,
  libcanberra,
  libqalculate,
  pipewire,
  qttools,
  qqc2-breeze-style,
  gpsd,
}:
mkKdeDerivation {
  pname = "plasma-workspace";
  version = "6.0.90-unstable-2024-05-31";

  src = fetchFromGitLab {
    domain = "invent.kde.org";
    owner = "plasma";
    repo = "plasma-workspace";
    rev = "dd6181feb1974753665b3a207c4b23e9fedd16c2";
    hash = "sha256-dmiZr6529/BhtztjZ667D5dYFJ/XelsFKYNMZDRDINw=";
  };

  patches = [
    (substituteAll {
      src = ./tool-paths.patch;
      xmessage = "${lib.getBin xorg.xmessage}/bin/xmessage";
      xsetroot = "${lib.getBin xorg.xsetroot}/bin/xsetroot";
      qdbus = "${lib.getBin qttools}/bin/qdbus";
    })
  ];

  postInstall = ''
    # Prevent patching this shell file, it only is used by sourcing it from /bin/sh.
    chmod -x $out/libexec/plasma-sourceenv.sh
  '';

  extraNativeBuildInputs = [pkg-config spirv-tools];
  extraBuildInputs = [
    qtsvg
    qtwayland

    qqc2-breeze-style

    libcanberra
    libqalculate
    pipewire

    xorg.libSM
    xorg.libXcursor
    xorg.libXtst
    xorg.libXft

    gpsd
  ];

  passthru.providedSessions = ["plasma" "plasmax11"];
}
