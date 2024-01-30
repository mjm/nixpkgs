{ lib
, buildPythonPackage
, fetchPypi
, click
}:

buildPythonPackage rec {
  pname = "confusable-homoglyphs";
  version = "3.2.0";

  src = fetchPypi {
    pname = "confusable_homoglyphs";
    inherit version;
    hash = "sha256-O0oNn6UQZpSYggyRoL/AwydWjOzskGSM84GdSm/Gp1E=";
  };

  nativeCheckInputs = [ click ];

  pythonImportsCheck = [
    "confusable_homoglyphs.categories"
    "confusable_homoglyphs.confusables"
  ];

  meta = with lib; {
    description = "Detect confusable usage of unicode homoglyphs, prevent homograph attacks.";
    homepage = "https://sr.ht/~valhalla/confusable_homoglyphs/";
    license = licenses.mit;
    maintainers = with maintainers; [ mjm ];
  };
}
