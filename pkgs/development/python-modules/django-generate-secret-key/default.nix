{ lib
, buildPythonPackage
, fetchPypi
, django
}:

buildPythonPackage rec {
  pname = "django-generate-secret-key";
  version = "1.0.2";

  src = fetchPypi {
    pname = "django_generate_secret_key";
    inherit version;
    hash = "sha256-4v6bV87YLpocrYRRKZxNrPCXFY5ghD7zWm0TaD858Zc=";
  };

  propagatedBuildInputs = [ django ];

  # The tests import `django.utils.six` which was removed in Django 3, but
  # the module itself works fine even in Django 4.
  doCheck = false;

  meta = with lib; {
    description = "Python module to generate a new Django secret key";
    homepage = "https://github.com/MickaelBergem/django-generate-secret-key";
    license = licenses.mit;
    maintainers = with maintainers; [ mjm ];
  };
}
