import 'package:flutter/material.dart';
import 'api.dart';
import 'widgets.dart';
import 'case_detail.dart';
import 'operation_dialogs.dart';

class OperationsPage extends StatefulWidget {
  final Api api;
  const OperationsPage({super.key,required this.api});
  @override
  State<OperationsPage> createState()=>OperationsPageState();
}
class OperationsPageState extends State<OperationsPage> {
  final scroll=ScrollController();
  Map<String,dynamic>? data,pending;String? error;
  int tab=0,offset=0,generation=0;bool loading=true,busy=false,unread=false;
  bool get locked=>loading||busy||pending!=null;
  @override
  void initState(){super.initState();load();}
  @override
  void dispose(){scroll.dispose();super.dispose();}
  Future<void> load() async {
    if(busy)return;final g=++generation;setState((){loading=true;error=null;data=null;});
    try{
      final path=tab==0?'/api/notifications?offset=$offset&limit=25&unread=$unread':tab==1?'/api/integrations?offset=$offset&limit=25':'/api/accounts';
      final result=await widget.api.request('GET',path);
      if(mounted&&g==generation)setState(()=>data=Map<String,dynamic>.from(result as Map));
    }catch(e){if(mounted&&g==generation){setState(()=>error='$e');await showMessage(context,'$e');}}
    finally{if(mounted&&g==generation)setState(()=>loading=false);}
  }
  Future<void> mutate(String path,{String method='POST',Map<String,dynamic>? body,bool review=true}) async {
    if(busy||loading)return;
    if(pending==null){
      if(review){
        final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text(path.endsWith('scan')?'Pindai SLA?':'Proses job siap?'),
          content:Text(path.endsWith('scan')?'Buat satu pengingat per siklus yang melewati SLA. Tidak mengubah status/outcome kasus.':'Maksimal20job yang jadwalnya siap. Adapter tiruan lokal; tidak ada pesan atau panggilan eksternal.'),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Jalankan'))]));
        if(ok!=true||!mounted)return;
      }
      pending={'path':path,'method':method,'body':method=='PATCH'?null:{...?body,'request_key':'ops-${DateTime.now().microsecondsSinceEpoch}'}};
    }
    setState((){busy=true;error=null;});bool success=false;
    try{
      final result=await widget.api.request(pending!['method'] as String,pending!['path'] as String,pending!['body']);
      if(!mounted)return;setState(()=>pending=null);success=true;
      if(result is Map&&result['processed']!=null)await showMessage(context,'${result['processed']} job diproses secara simulasi.');
      if(mounted&&result is Map&&result['created']!=null)await showMessage(context,'${result['created']} pengingat baru.');
    }catch(e){if(mounted){setState((){error='$e';if(e is ApiException&&!e.mayHaveSucceeded&&e.status!=null&&e.status!<500)pending=null;});await showMessage(context,'$e');}}
    finally{if(mounted)setState(()=>busy=false);}
    if(success&&mounted)await load();
  }
  Future<void> dialog({Map<String,dynamic>? account,Map<String,dynamic>? job}) async {
    await showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>OperationDialog(api:widget.api,account:account,job:job));
    if(mounted)await load();
  }
  Future<void> open(String id) async {
    await Navigator.push<void>(context,MaterialPageRoute(builder:(_)=>CaseDetail(api:widget.api,caseId:id)));if(mounted)await load();
  }
  Widget item(Map r){
    if(tab==0)return Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${r['title']}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),Text('${r['body']}'),
      Text('${r['case_id']??''} · ${dateLabel(r['created_at'] as String?)}'),
      Text(r['read_at']==null?'Belum dibaca':'Sudah dibaca'),
      Wrap(spacing:10,children:[if(r['read_at']==null)TextButton(onPressed:locked?null:()=>mutate('/api/notifications/${r['id']}/read',method:'PATCH',review:false),child:const Text('Tandai dibaca')),
        if(r['can_open']==true)TextButton(onPressed:locked?null:()=>open(r['case_id'] as String),child:const Text('Buka kasus'))]),
      if(r['case_id']!=null&&r['can_open']!=true)const Text('Kasus tidak lagi dalam scope akun ini.'),
    ]));
    if(tab==2)return Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${r['username']}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),Text('${r['name']} · ${r['agent_id']}'),
      Text('Login ${r['active']==1?'aktif':'nonaktif'} · revisi${r['version']} · ${r['active_cases']} kasus aktif'),
      TextButton(onPressed:locked?null:()=>dialog(account:Map<String,dynamic>.from(r)),child:const Text('Kontrol akun')),
    ]));
    return Surface(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SelectableText('${r['id']}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w600)),
      Text('${r['case_id']} · siklus${r['cycle']} · ${r['channel']}'),
      Text('Status ${r['state']} · percobaan ${r['attempts']}/${r['attempt_limit']} · revisi${r['version']}'),
      Text('Siap: ${dateLabel(r['available_at'] as String?)}'),
      if(r['receipt_id']!=null)SelectableText('Receipt lokal ${r['receipt_id']}'),
      ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('Histori percobaan'),children:[
        for(final h in r['attempt_history'] as List) ListTile(contentPadding:EdgeInsets.zero,title:Text('${h['attempt']} · ${h['state']}'),subtitle:Text('${h['detail']}\n${dateLabel(h['created_at'] as String?)}')),
      ]),
      Wrap(spacing:10,children:[TextButton(onPressed:locked?null:()=>open(r['case_id'] as String),child:const Text('Buka kasus')),
        if(widget.api.supervisor&&['retry','dead'].contains(r['state']))TextButton(onPressed:locked?null:()=>dialog(job:Map<String,dynamic>.from(r)),child:const Text('Jadwalkan ulang'))]),
    ]));
  }
  @override
  Widget build(BuildContext context)=>DefaultTabController(length:widget.api.supervisor?3:2,child:Scaffold(
    appBar:AppBar(title:const Text('Operasi & notifikasi'),actions:[IconButton(tooltip:'Muat operasi terbaru',onPressed:busy||loading?null:load,icon:const Icon(Icons.refresh))],
      bottom:PreferredSize(preferredSize:const Size.fromHeight(48),child:AbsorbPointer(absorbing:locked,child:TabBar(onTap:(i){if(scroll.hasClients)scroll.jumpTo(0);setState((){tab=i;offset=0;});load();},tabs:[const Tab(text:'Inbox'),const Tab(text:'Integrasi'),if(widget.api.supervisor)const Tab(text:'Akun petugas')])))),
    body:ListView(controller:scroll,padding:const EdgeInsets.all(20),children:[
      Text(tab==0?'Notifikasi akun ini':tab==1?'Telephony & omnichannel tiruan':'Administrasi login petugas',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w600)),
      const Text('Data dan transaksi sintetis. Tidak ada komunikasi keluar ke nasabah atau layanan eksternal.'),const SizedBox(height:14),
      if(loading||busy)const LinearProgressIndicator(),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.deepOrange)),
      if(pending!=null)...[const Text('Hasil belum pasti; operasi lain dikunci sampai retry/periksa status.'),FilledButton(onPressed:busy||loading?null:()=>mutate(pending!['path'] as String),child:const Text('Periksa / ulangi batch'))],
      if(tab==0)CheckboxListTile(contentPadding:EdgeInsets.zero,value:unread,title:const Text('Hanya belum dibaca'),onChanged:locked?null:(v){setState((){unread=v!;offset=0;});load();}),
      if(widget.api.supervisor&&tab<2)Wrap(spacing:12,children:[
        OutlinedButton(onPressed:locked?null:()=>mutate('/api/notifications/scan'),child:const Text('Pindai SLA')),
        if(tab==1)FilledButton(onPressed:locked?null:()=>mutate('/api/integrations/process',body:{'limit':20}),child:const Text('Proses job siap')),
      ]),
      if(data!=null)...[
        if(tab==0)Text('${data!['unread']} notifikasi belum dibaca'),
        if((data!['items'] as List).isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Belum ada hasil pada halaman ini.')),
        for(final r in data!['items'] as List)Padding(padding:const EdgeInsets.only(top:14),child:item(r as Map)),
        if(tab<2)...[const SizedBox(height:16),Text('${data!['total']} hasil · 25 per halaman'),Wrap(spacing:12,children:[
          TextButton(onPressed:locked||offset==0?null:(){setState(()=>offset-=25);load();},child:const Text('Sebelumnya')),
          TextButton(onPressed:locked||offset+25>=(data!['total'] as int)?null:(){setState(()=>offset+=25);load();},child:const Text('Berikutnya')),
        ])],
      ],
    ])));
}
