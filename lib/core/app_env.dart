class AppEnv {
  const AppEnv._();

  static const String tokenEmail = String.fromEnvironment('ADANA_EMAIL',
      defaultValue: 'a1FJQ8vLIA@gmail.com');
  static const String tokenPassword =
      String.fromEnvironment('ADANA_PASSWORD', defaultValue: 'secret');
  static const String kentkartToken = String.fromEnvironment(
    'KENTKART_TOKEN',
    defaultValue:
        'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJrZW50a2FydC5jb20iLCJzdWIiOiJBQzUiLCJhdWQiOiJhQzF1biIsImV4cCI6MTg5MzQ0NTIwMCwibmJmIjoxNzQxMjcwNDAwLCJpYXQiOjE3NDEyNzA0MDAsImp0aSI6IjE5ZWMzOWEzLWE4ODItNDdhNC05MTNlLWZjNTBmOTBkZjkwOCIsInN5c3RlbV9pZCI6IjAwMyIsInNjb3BlcyI6W119.D5lpigVF8ib-6KPuZ-bV8rhEbskoaF7kSSbNc_INK5OztF9PKIMnp2aBNmjmqCp8paHN84Lu-nbQoqjNiR03_TIeX7BkAiE8lAJUlCPW2c1CGwe_VSDbRFwYLqIDoR-TthhkqLmpvIK3HandFv3zpZRF1byB01WyeDqUGnW6iH1G0TXjQb_wl3SaoYq0WuDQD7X_jIaJpWt0asNh1-gsvj7N7Gex-pe33bcc9DBhs85MpM7xn2MPPzsXCePdK4C2BRPL_FFzz_JuRL-J_iIStBXv0mFR08TYJ2rBHDWbiD73ARytGRH0SVf3c0IiNTyzAQh1gyzH7XFYnsv8q2Bfuw',
  );

  static bool get hasApiCredentials =>
      tokenEmail.isNotEmpty && tokenPassword.isNotEmpty;

  static bool get hasKentkartToken => kentkartToken.isNotEmpty;
}
