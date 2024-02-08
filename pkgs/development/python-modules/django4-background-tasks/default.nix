{
  lib,
  buildPythonPackage,
  fetchPypi,
  django,
  six,
  python,
  mock,
}:
buildPythonPackage rec {
  pname = "django4-background-tasks";
  version = "1.2.9";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-on3eyKDIUOXu3u9HZ9rNBnZXrrSEx+g1k9r1nBZDPOI=";
  };

  propagatedBuildInputs = [
    django
    six
  ];

  nativeCheckInputs = [ mock ];

  checkPhase = ''
    ${python.interpreter} -m django test --settings=background_task.tests.test_settings
  '';

  meta = with lib; {
    description = "A database-backed work queue for Django";
    homepage = "https://github.com/meneses-pt/django-background-tasks";
    license = licenses.bsd3;
    maintainers = with maintainers; [ mjm ];
  };
}
