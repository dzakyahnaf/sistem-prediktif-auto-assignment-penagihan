import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:assignment_studio/main.dart';
import 'package:assignment_studio/api.dart';
import 'package:assignment_studio/case_form.dart';
import 'package:assignment_studio/case_detail.dart';
import 'package:assignment_studio/decisions_page.dart';

Finder field(String label) => find.byWidgetPredicate((w)=>w is TextField && (w.decoration?.labelText ?? w.decoration?.hintText)==label);
Future<void> ready(WidgetTester t, Finder target) async {
  for(int i=0;i<150;i++) {
    await t.pump(const Duration(milliseconds:200));
    if(target.evaluate().isNotEmpty) { await t.pumpAndSettle(); return; }
  }
  throw StateError('Native UI did not reach $target');
}
Future<void> tap(WidgetTester t,Finder target) async {
  await ready(t,target);await t.ensureVisible(target);await t.pumpAndSettle();await t.tap(target);await t.pumpAndSettle();
}
Future<void> fill(WidgetTester t,String label,String value) async {
  final f=field(label);await ready(t,f);await t.ensureVisible(f);await t.pumpAndSettle();await t.enterText(f,value);await t.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();await t.pumpAndSettle();
}
Future<void> login(WidgetTester t,Api api,String username) async {
  await fill(t,'Username',username);await fill(t,'Password','DemoAssignment!2026');
  expect(t.widget<TextField>(field('Username')).controller!.text,username);
  await tap(t,find.text('Masuk ke ruang kerja'));
  for(int i=0;i<100 && api.user?['username']!=username;i++) { await t.pump(const Duration(milliseconds:200)); }
  expect(api.user?['username'],username);
  await ready(t,find.text('Buka penagihan'));
}
Future<void> dropdown(WidgetTester t,String label,String choice) async {
  final target=find.ancestor(of:find.text(label),matching:find.byType(DropdownButtonFormField<String>));
  await tap(t,target);await ready(t,find.text(choice));await tap(t,find.text(choice).last);
}
Future<String> create(WidgetTester t,Api api,String kind,String alias) async {
  await tap(t,find.text(kind=='collection'?'Buka penagihan':'Buka pengajuan'));
  await tap(t,find.text(kind=='collection'?'Kasus baru':'Pengajuan baru'));await fill(t,'Nama / alias demo',alias);
  await dropdown(t,'Wilayah','Semarang');await dropdown(t,'Kesulitan kasus','Low');
  await fill(t,kind=='collection'?'Nilai tagihan penuh (Rp)':'Nominal pengajuan (Rp)','1000000');
  if(kind=='origination') await fill(t,'Penghasilan bulanan (Rp)','5000000');
  await tap(t,find.text('Simpan'));
  for(int i=0;i<100 && find.byType(CaseForm).evaluate().isNotEmpty;i++) { await t.pump(const Duration(milliseconds:200)); }
  expect(find.byType(CaseForm),findsNothing);
  final result=await api.request('GET','/api/cases?${Uri(queryParameters:{'q':alias}).query}');
  expect((result['items'] as List).length,1);final cid=result['items'][0]['id'] as String;
  await fill(t,'Cari ID, nama demo, atau kode wilayah…',cid);await ready(t,find.text(alias));await tap(t,find.text(alias));
  await ready(t,find.text('Tugaskan kasus'));await tap(t,find.text('Tugaskan kasus'));await ready(t,find.text('Catat aktivitas'));
  return cid;
}
Future<void> activity(WidgetTester t,String code,{String? amount}) async {
  await tap(t,find.text('Catat aktivitas'));await dropdown(t,'Hasil aktivitas',code);
  if(amount!=null) await fill(t,'Nominal (Rp)',amount);
  await fill(t,'Catatan','UAT Android sintetis; transaksi simulasi');await tap(t,find.text('Simpan aktivitas'));
  for(int i=0;i<100 && find.byType(ActivityDialog).evaluate().isNotEmpty;i++) { await t.pump(const Duration(milliseconds:200)); }
  expect(find.byType(ActivityDialog),findsNothing);await t.pumpAndSettle();
}
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android supervisor and agent complete both workflows with persistence and scope',(t) async {
    // Keep deterministic automated typing separate from the real IME check.
    t.testTextInput.register();addTearDown(t.testTextInput.unregister);
    const acknowledged=bool.fromEnvironment('UAT_ISOLATED',defaultValue:false);
    expect(acknowledged,isTrue,reason:'Run only with an isolated UAT backend, never the original demo.');
    final api=Api();await t.pumpWidget(AssignmentApp(api:api));await t.pumpAndSettle();
    await login(t,api,'supervisor');final tag='UAT Android ${DateTime.now().microsecondsSinceEpoch}';
    final collection=await create(t,api,'collection','$tag Penagihan');
    await tap(t,find.text('Penugasan ulang'));await fill(t,'Alasan penugasan ulang','UAT Android siklus kedua sebelum pembayaran');await tap(t,find.text('Lanjutkan'));
    for(int i=0;i<50;i++) { await t.pump(const Duration(milliseconds:200)); }
    await t.pageBack();await t.pumpAndSettle();
    await tap(t,find.byTooltip('Keluar'));await ready(t,field('Username'));await login(t,api,'smg-col-a');
    expect(find.text('Keputusan & segmen'),findsNothing);expect(find.text('Model & evaluasi'),findsNothing);
    await tap(t,find.text('Operasi & notifikasi'));await ready(t,find.text('Tandai dibaca'));
    expect(find.text('Akun petugas'),findsNothing);expect(find.text('Proses job siap'),findsNothing);
    await tap(t,find.text('Tandai dibaca').first);await ready(t,find.text('Sudah dibaca'));
    await tap(t,find.text('Buka kasus').first);await ready(t,find.text('Catat aktivitas'));
    await activity(t,'Pembayaran',amount:'400000');
    final partial=await api.request('GET','/api/cases/$collection');expect(partial['case']['paid'],400000);expect(partial['case']['status'],'in_progress');
    await activity(t,'Pembayaran',amount:'600000');final full=await api.request('GET','/api/cases/$collection');
    expect(full['case']['paid'],1000000);expect(full['case']['status'],'paid');expect(full['case']['cycle'],2);expect(full['assignments'].last['outcome'],'success');
    await t.pageBack();await t.pumpAndSettle();await t.pageBack();await t.pumpAndSettle();await tap(t,find.byTooltip('Keluar'));await login(t,api,'supervisor');
    final origination=await create(t,api,'origination','$tag Pengajuan');
    await activity(t,'Dokumen lengkap');await activity(t,'Lolos verifikasi');await activity(t,'Pencairan simulasi',amount:'1000000');
    final disbursed=await api.request('GET','/api/cases/$origination');expect(disbursed['case']['status'],'disbursed');expect(disbursed['case']['paid'],1000000);
    await t.pageBack();await t.pumpAndSettle();
    // Reopen the overview using the navigation destination, then create a rejected lead.
    final nav=find.byType(NavigationBar);await tap(t,find.descendant(of:nav,matching:find.text('Ringkasan')));
    final rejected=await create(t,api,'origination','$tag Ditolak');await activity(t,'Penolakan');
    expect((await api.request('GET','/api/cases/$rejected'))['case']['status'],'rejected');
    await t.pageBack();await t.pumpAndSettle();await tap(t,find.descendant(of:find.byType(NavigationBar),matching:find.text('Ringkasan')));
    await tap(t,find.text('Keputusan & segmen'));await ready(t,find.byType(DecisionsPage));await t.pageBack();await t.pumpAndSettle();
    expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());api.dispose();
  },timeout:const Timeout(Duration(minutes:8)));
}
