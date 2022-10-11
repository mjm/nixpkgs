{ lib, stdenv, fetchurl, buildPackages, perl, coreutils
, withCryptodev ? false, cryptodev
, enableSSL2 ? false
, enableSSL3 ? false
, static ? stdenv.hostPlatform.isStatic
# Used to avoid cross compiling perl, for example, in darwin bootstrap tools.
# This will cause c_rehash to refer to perl via the environment, but otherwise
# will produce a perfectly functional openssl binary and library.
, withPerl ? stdenv.hostPlatform == stdenv.buildPlatform
, removeReferencesTo
}:

# Note: this package is used for bootstrapping fetchurl, and thus
# cannot use fetchpatch! All mutable patches (generated by GitHub or
# cgit) that are needed here should be included directly in Nixpkgs as
# files.

let
  common = { version, sha256, patches ? [], withDocs ? false, extraMeta ? {} }:
   stdenv.mkDerivation rec {
    pname = "openssl";
    inherit version;

    src = fetchurl {
      url = "https://www.openssl.org/source/${pname}-${version}.tar.gz";
      inherit sha256;
    };

    inherit patches;

    postPatch = ''
      patchShebangs Configure
    '' + lib.optionalString (lib.versionOlder version "1.1.1") ''
      patchShebangs test/*
      for a in test/t* ; do
        substituteInPlace "$a" \
          --replace /bin/rm rm
      done
    ''
    # config is a configure script which is not installed.
    + lib.optionalString (lib.versionAtLeast version "1.1.1") ''
      substituteInPlace config --replace '/usr/bin/env' '${buildPackages.coreutils}/bin/env'
    '' + lib.optionalString (lib.versionAtLeast version "1.1.1" && stdenv.hostPlatform.isMusl) ''
      substituteInPlace crypto/async/arch/async_posix.h \
        --replace '!defined(__ANDROID__) && !defined(__OpenBSD__)' \
                  '!defined(__ANDROID__) && !defined(__OpenBSD__) && 0'
    ''
    # Move ENGINESDIR into OPENSSLDIR for static builds, in order to move
    # it to the separate etc output.
    + lib.optionalString static ''
      substituteInPlace Configurations/unix-Makefile.tmpl \
        --replace 'ENGINESDIR=$(libdir)/engines-{- $sover_dirname -}' \
                  'ENGINESDIR=$(OPENSSLDIR)/engines-{- $sover_dirname -}'
    '';

    outputs = [ "bin" "dev" "out" "man" ]
      ++ lib.optional withDocs "doc"
      # Separate output for the runtime dependencies of the static build.
      # Specifically, move OPENSSLDIR into this output, as its path will be
      # compiled into 'libcrypto.a'. This makes it a runtime dependency of
      # any package that statically links openssl, so we want to keep that
      # output minimal.
      ++ lib.optional static "etc";
    setOutputFlags = false;
    separateDebugInfo =
      !stdenv.hostPlatform.isDarwin &&
      !(stdenv.hostPlatform.useLLVM or false) &&
      stdenv.cc.isGNU;

    nativeBuildInputs = [ perl ]
      ++ lib.optionals static [ removeReferencesTo ];
    buildInputs = lib.optional withCryptodev cryptodev
      # perl is included to allow the interpreter path fixup hook to set the
      # correct interpreter in c_rehash.
      ++ lib.optional withPerl perl;

    # TODO(@Ericson2314): Improve with mass rebuild
    configurePlatforms = [];
    configureScript = {
        armv5tel-linux = "./Configure linux-armv4 -march=armv5te";
        armv6l-linux = "./Configure linux-armv4 -march=armv6";
        armv7l-linux = "./Configure linux-armv4 -march=armv7-a";
        x86_64-darwin  = "./Configure darwin64-x86_64-cc";
        aarch64-darwin = "./Configure darwin64-arm64-cc";
        x86_64-linux = "./Configure linux-x86_64";
        x86_64-solaris = "./Configure solaris64-x86_64-gcc";
        riscv64-linux = "./Configure linux64-riscv64";
        mips64el-linux =
          if stdenv.hostPlatform.isMips64n64
          then "./Configure linux64-mips64"
          else if stdenv.hostPlatform.isMips64n32
          then "./Configure linux-mips64"
          else throw "unsupported ABI for ${stdenv.hostPlatform.system}";
      }.${stdenv.hostPlatform.system} or (
        if stdenv.hostPlatform == stdenv.buildPlatform
          then "./config"
        else if stdenv.hostPlatform.isBSD && stdenv.hostPlatform.isx86_64
          then "./Configure BSD-x86_64"
        else if stdenv.hostPlatform.isBSD && stdenv.hostPlatform.isx86_32
          then "./Configure BSD-x86" + lib.optionalString (stdenv.hostPlatform.parsed.kernel.execFormat.name == "elf") "-elf"
        else if stdenv.hostPlatform.isBSD
          then "./Configure BSD-generic${toString stdenv.hostPlatform.parsed.cpu.bits}"
        else if stdenv.hostPlatform.isMinGW
          then "./Configure mingw${lib.optionalString
                                     (stdenv.hostPlatform.parsed.cpu.bits != 32)
                                     (toString stdenv.hostPlatform.parsed.cpu.bits)}"
        else if stdenv.hostPlatform.isLinux
          then "./Configure linux-generic${toString stdenv.hostPlatform.parsed.cpu.bits}"
        else if stdenv.hostPlatform.isiOS
          then "./Configure ios${toString stdenv.hostPlatform.parsed.cpu.bits}-cross"
        else
          throw "Not sure what configuration to use for ${stdenv.hostPlatform.config}"
      );

    # OpenSSL doesn't like the `--enable-static` / `--disable-shared` flags.
    dontAddStaticConfigureFlags = true;
    configureFlags = [
      "shared" # "shared" builds both shared and static libraries
      "--libdir=lib"
      (if !static then
         "--openssldir=etc/ssl"
       else
         # Move OPENSSLDIR to the 'etc' output for static builds. Prepend '/.'
         # to the path to make it appear absolute before variable expansion,
         # else the 'prefix' would be prepended to it.
         "--openssldir=/.$(etc)/etc/ssl"
      )
    ] ++ lib.optionals withCryptodev [
      "-DHAVE_CRYPTODEV"
      "-DUSE_CRYPTODEV_DIGESTS"
    ] ++ lib.optional enableSSL2 "enable-ssl2"
      ++ lib.optional enableSSL3 "enable-ssl3"
      ++ lib.optional (lib.versionAtLeast version "3.0.0") "enable-ktls"
      ++ lib.optional (lib.versionAtLeast version "1.1.1" && stdenv.hostPlatform.isAarch64) "no-afalgeng"
      # OpenSSL needs a specific `no-shared` configure flag.
      # See https://wiki.openssl.org/index.php/Compilation_and_Installation#Configure_Options
      # for a comprehensive list of configuration options.
      ++ lib.optional (lib.versionAtLeast version "1.1.1" && static) "no-shared"
      ++ lib.optional (lib.versionAtLeast version "3.0.0" && static) "no-module"
      # This introduces a reference to the CTLOG_FILE which is undesired when
      # trying to build binaries statically.
      ++ lib.optional static "no-ct"
      ;

    makeFlags = [
      "MANDIR=$(man)/share/man"
      # This avoids conflicts between man pages of openssl subcommands (for
      # example 'ts' and 'err') man pages and their equivalent top-level
      # command in other packages (respectively man-pages and moreutils).
      # This is done in ubuntu and archlinux, and possiibly many other distros.
      "MANSUFFIX=ssl"
    ];

    enableParallelBuilding = true;

    postInstall =
    (if static then ''
      # OPENSSLDIR has a reference to self
      remove-references-to -t $out $out/lib/*.a
    '' else ''
      # If we're building dynamic libraries, then don't install static
      # libraries.
      if [ -n "$(echo $out/lib/*.so $out/lib/*.dylib $out/lib/*.dll)" ]; then
          rm "$out/lib/"*.a
      fi

      # 'etc' is a separate output on static builds only.
      etc=$out
    '') + lib.optionalString (!stdenv.hostPlatform.isWindows)
      # Fix bin/c_rehash's perl interpreter line
      #
      # - openssl 1_0_2: embeds a reference to buildPackages.perl
      # - openssl 1_1:   emits "#!/usr/bin/env perl"
      #
      # In the case of openssl_1_0_2, reset the invalid reference and let the
      # interpreter hook take care of it.
      #
      # In both cases, if withPerl = false, the intepreter line is expected be
      # "#!/usr/bin/env perl"
    ''
      substituteInPlace $out/bin/c_rehash --replace ${buildPackages.perl}/bin/perl "/usr/bin/env perl"
    '' + ''
      mkdir -p $bin
      mv $out/bin $bin/bin

      mkdir $dev
      mv $out/include $dev/

      # remove dependency on Perl at runtime
      rm -r $etc/etc/ssl/misc

      rmdir $etc/etc/ssl/{certs,private}
    '';

    postFixup = lib.optionalString (!stdenv.hostPlatform.isWindows) ''
      # Check to make sure the main output and the static runtime dependencies
      # don't depend on perl
      if grep -r '${buildPackages.perl}' $out $etc; then
        echo "Found an erroneous dependency on perl ^^^" >&2
        exit 1
      fi
    '';

    meta = with lib; {
      homepage = "https://www.openssl.org/";
      description = "A cryptographic library that implements the SSL and TLS protocols";
      license = licenses.openssl;
      platforms = platforms.all;
    } // extraMeta;
  };

in {


  openssl_1_1 = common rec {
    version = "1.1.1r";
    sha256 = "sha256-44k1KuPVrk04WXv4pU8dy2+zyLUPT+WKlLsb9/hdgqA=";
    patches = [
      ./1.1/nix-ssl-cert-file.patch

      (if stdenv.hostPlatform.isDarwin
       then ./use-etc-ssl-certs-darwin.patch
       else ./use-etc-ssl-certs.patch)
    ] ++ lib.optionals (stdenv.isDarwin && (builtins.substring 5 5 version) < "m") [
      ./1.1/macos-yosemite-compat.patch
    ];
    withDocs = true;
  };

  openssl_3 = common {
    version = "3.0.5";
    sha256 = "sha256-qn2Nm+9xrWUlxVuhHl9Dl4ic5Jwsk0nc6m0+TwsCSno=";
    patches = [
      ./3.0/nix-ssl-cert-file.patch

      # openssl will only compile in KTLS if the current kernel supports it.
      # This patch disables build-time detection.
      ./3.0/openssl-disable-kernel-detection.patch

      (if stdenv.hostPlatform.isDarwin
       then ./use-etc-ssl-certs-darwin.patch
       else ./use-etc-ssl-certs.patch)
    ];

    withDocs = true;

    extraMeta = with lib; {
      license = licenses.asl20;
    };
  };
}
