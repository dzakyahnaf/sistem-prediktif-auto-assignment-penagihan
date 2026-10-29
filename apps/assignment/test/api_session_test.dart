import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:assignment_studio/api.dart';

http.Response sessionResponse([String token = 'session-one']) => http.Response(jsonEncode({
  'access_token': token, 'user': {'id': token, 'username': 'supervisor', 'role': 'supervisor', 'agent_id': null},
}), 200);

void main() {
  test('authenticated 401 clears credentials once and notifies root', () async {
    final api = Api(client: MockClient((request) async => request.url.path.endsWith('login') ? sessionResponse() : http.Response('<html>Expired</html>', 401)));
    addTearDown(api.dispose);
    await api.login('supervisor', 'demo');
    var notifications = 0;
    api.addListener(() => notifications++);
    await expectLater(api.request('GET', '/api/me'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(api.token, isNull);
    expect(api.user, isNull);
    expect(api.sessionMessage, contains('berakhir'));
    expect(notifications, 1);
    api.clearSession();
    expect(notifications, 1);
  });

  test('invalid login stays on login and preserves error instead of expiry', () async {
    final api = Api(client: MockClient((_) async => http.Response('{"detail":"Username atau password tidak cocok."}', 401)));
    addTearDown(api.dispose);
    await expectLater(api.login('wrong', 'wrong'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('tidak cocok'))));
    expect(api.token, isNull);
    expect(api.sessionRevision, 0);
    expect(api.sessionMessage, isNull);
  });

  test('403 is not a session expiry', () async {
    final api = Api(client: MockClient((request) async => request.url.path.endsWith('login') ? sessionResponse() : http.Response('{"detail":"Supervisor saja"}', 403)));
    addTearDown(api.dispose);
    await api.login('supervisor', 'demo');
    await expectLater(api.request('GET', '/api/agents'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
    expect(api.token, 'session-one');
  });

  for (final oldStatus in [200, 401]) {
    test('late $oldStatus from old session cannot affect a new user', () async {
      final oldResponse = Completer<http.Response>();
      final started = Completer<void>();
      var logins = 0;
      final api = Api(client: MockClient((request) async {
        if (request.url.path.endsWith('login')) return sessionResponse('session-${++logins}');
        started.complete();
        return oldResponse.future;
      }));
      addTearDown(api.dispose);
      await api.login('first', 'demo');
      final pending = api.request('GET', '/api/cases');
      final check = expectLater(pending, throwsA(isA<ApiException>().having((e) => e.status, 'stale', 409)));
      await started.future;
      api.clearSession();
      await api.login('second', 'demo');
      oldResponse.complete(http.Response(oldStatus == 200 ? '{"items":["old private data"]}' : '{"detail":"Expired"}', oldStatus));
      await check;
      expect(api.token, 'session-2');
      expect(api.user!['id'], 'session-2');
    });
  }

  test('malformed login never installs a half valid session', () async {
    final api = Api(client: MockClient((_) async => http.Response('{"access_token":"bad"}', 200)));
    addTearDown(api.dispose);
    await expectLater(api.login('demo','demo'), throwsA(isA<ApiException>()));
    expect(api.token, isNull);
  });

  test('transport timeout does not expire session or retry a write', () async {
    var calls = 0;
    final response = Completer<http.Response>();
    final api = Api(timeout: const Duration(milliseconds: 10), client: MockClient((request) async {
      if (request.url.path.endsWith('login')) return sessionResponse();
      calls++;
      return response.future;
    }));
    addTearDown(api.dispose);
    await api.login('supervisor','demo');
    await expectLater(api.request('POST','/api/cases/TAG-1/activities', {'code':'payment'}),
      throwsA(isA<ApiException>().having((e) => e.mayHaveSucceeded, 'ambiguous mutation', true)));
    expect(api.token, 'session-one');
    expect(calls, 1);
    response.complete(http.Response('{}',200));
  });

  test('non JSON 500 write remains ambiguous and session is retained', () async {
    final api = Api(client: MockClient((request) async => request.url.path.endsWith('login') ? sessionResponse() : http.Response('Bad Gateway', 500)));
    addTearDown(api.dispose);
    await api.login('supervisor','demo');
    await expectLater(api.request('POST','/api/cases/TAG-1/activities', {}),
      throwsA(isA<ApiException>().having((e) => e.mayHaveSucceeded, 'ambiguous mutation', true)));
    expect(api.token, isNotNull);
  });

  test('validation errors identify fields without leaking server internals', () async {
    final api = Api(client: MockClient((request) async => request.url.path.endsWith('login') ? sessionResponse() : http.Response(jsonEncode({'detail':[
      {'loc':['body','amount'],'msg':'Input should be greater than 0','input':-1},
    ]}),422)));
    addTearDown(api.dispose);
    await api.login('supervisor','demo');
    await expectLater(api.request('POST','/api/cases', {}), throwsA(isA<ApiException>()
      .having((e) => e.message, 'field name', contains('nominal'))
      .having((e) => e.mayHaveSucceeded, 'validation rejected', false)));
  });

  test('public login never sends the previous bearer credential', () async {
    final headers = <Map<String, String>>[];
    final api = Api(client: MockClient((request) async { headers.add(request.headers); return sessionResponse(); }));
    addTearDown(api.dispose);
    await api.login('one','demo');
    await api.login('two','demo');
    expect(headers.every((h) => !h.containsKey('authorization')), isTrue);
  });
}
