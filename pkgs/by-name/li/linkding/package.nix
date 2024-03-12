{ lib
, python3
, python3Packages
, fetchFromGitHub
, buildNpmPackage
}:

let
  pname = "linkding";
  version = "1.24.0";

  src = fetchFromGitHub {
    owner = "sissbruecker";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-oqIGgP0JBPKGKPTnW+mflBfQ2BzRlRqpdVN1OKXE7bA=";
  };

  frontend = buildNpmPackage {
    pname = "linkding-frontend";
    inherit version src;

    npmDepsHash = "sha256-Ku8bCS0PHtbfzrlSnaAWMr315NYKcXe/Goiz/ZouRLk=";

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/linkding-ui
      mv bookmarks/static/bundle.js{,.map} $out/lib/linkding-ui/
      cp -r node_modules/spectre.css/src $out/lib/linkding-ui/spectre.css
      runHook postInstall
    '';
  };

  python = python3;
  django = python3Packages.django_4;
in

python3Packages.buildPythonApplication rec {
  inherit pname version src;

  format = "other";

  propagatedBuildInputs = with python3Packages; [
    asgiref
    beautifulsoup4
    bleach
    bleach-allowlist
    certifi
    charset-normalizer
    click
    confusable-homoglyphs
    django
    django-generate-secret-key
    django-registration
    django-sass-processor
    django-widget-tweaks
    django4-background-tasks
    djangorestframework
    idna
    markdown
    psycopg2
    python-dateutil
    pytz
    requests
    soupsieve
    sqlparse
    supervisor
    typing-extensions
    urllib3
    waybackpy
    webencodings
  ];

  preBuild = ''
    rm siteroot/settings/dev.py
    sed -i 's|../../node_modules/spectre.css/src|${frontend}/lib/linkding-ui/spectre.css|g' bookmarks/styles/spectre.scss
    sed -i -e '19i DATA_DIR = os.getenv("LD_DATA_DIR", "/var/lib/linkding")' -e "s/BASE_DIR, 'data',/DATA_DIR,/" siteroot/settings/base.py
    sed -i -e 's/BASE_DIR, "secretkey.txt"/DATA_DIR, "secretkey.txt"/' siteroot/settings/prod.py
  '';

  postBuild = ''
    ${python.pythonOnBuildForHost.interpreter} -OO -m compileall .
    ${python.pythonOnBuildForHost.interpreter} manage.py compilescss
    ${python.pythonOnBuildForHost.interpreter} manage.py collectstatic --clear --no-input '--ignore=*.scss'
    ${python.pythonOnBuildForHost.interpreter} manage.py compilescss --delete-files
  '';

  installPhase =
    let
      pythonPath = python3Packages.makePythonPath propagatedBuildInputs;
    in
    ''
      mkdir -p $out/lib/linkding
      cp -r {bookmarks,siteroot,static,LICENSE.txt,manage.py,version.txt} $out/lib/linkding
      cp ${frontend}/lib/linkding-ui/bundle.js{,.map} $out/lib/linkding/static/
      chmod +x $out/lib/linkding/manage.py
      makeWrapper $out/lib/linkding/manage.py $out/bin/linkding \
        --prefix PYTHONPATH : ${pythonPath}
    '';

  passthru = {
    inherit python frontend;
  };

  meta = with lib; {
    changelog = "https://github.com/sissbruecker/linkding/blob/master/CHANGELOG.md";
    description = "A bookmark manager that you can host yourself";
    homepage = "https://github.com/sissbruecker/linkding";
    license = licenses.mit;
    maintainers = with maintainers; [ mjm ];
  };
}
