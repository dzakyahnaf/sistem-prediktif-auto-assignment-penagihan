import 'package:flutter_test/flutter_test.dart';
import 'package:assignment_studio/api.dart';
void main() {
  test('same origin bundle preserves protocol host port and query', () {
    expect(Api.endpoint('', '/api/cases?q=a%20b', origin: Uri.parse('https://demo.test:8443/#/cases')).toString(), 'https://demo.test:8443/api/cases?q=a%20b');
    expect(Api.endpoint('http://10.0.2.2:8000', '/api/me').toString(), 'http://10.0.2.2:8000/api/me');
  });
  test('empty native configuration fails before a request', () {
    expect(() => Api.endpoint('', '/api/me', origin: Uri.parse('file:///app')), throwsA(isA<ApiException>()));
  });
}
