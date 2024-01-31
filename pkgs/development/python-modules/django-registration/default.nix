{ lib
, buildPythonPackage
, fetchPypi
, setuptools-scm
, django
, confusable-homoglyphs
}:

buildPythonPackage rec {
  pname = "django-registration";
  version = "3.4";
  format = "pyproject";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-GgzO9+9x5np4pVGr2K03iXfcFKA28fzYvkIqaL1SVKk=";
  };

  nativeBuildInputs = [ setuptools-scm ];

  propagatedBuildInputs = [
    confusable-homoglyphs
    django
  ];

  meta = with lib; {
    description = "An extensible user-registration app for Django";
    homepage = "https://github.com/ubernostrum/django-registration";
    license = licenses.bsd3;
    maintainers = with maintainers; [ mjm ];
  };
}
