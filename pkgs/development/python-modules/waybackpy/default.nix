{ lib
, buildPythonPackage
, fetchPypi
, click
, requests
, urllib3
, pytest
}:

buildPythonPackage rec {
  pname = "waybackpy";
  version = "3.0.6";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-SXo3F1arp2ROt62g69TtsVy4xTvBNMyXO/AjoSyv+D8=";
  };

  propagatedBuildInputs = [
    click
    requests
    urllib3
  ];

  nativeCheckInputs = [ pytest ];

  meta = with lib; {
    changelog = "https://github.com/akamhy/waybackpy/releases/tag/${version}";
    description = "Python package that interfaces with the Internet Archive's Wayback Machine APIs";
    homepage = "https://akamhy.github.io/waybackpy/";
    license = licenses.mit;
    maintainers = with maintainers; [ mjm ];
  };
}
