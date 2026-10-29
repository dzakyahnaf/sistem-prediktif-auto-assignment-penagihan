import 'package:flutter/material.dart';
import 'api.dart';

class OperationDialog extends StatefulWidget {
  final Api api;
  final Map<String, dynamic>? record, job, account;
  const OperationDialog({super.key,required this.api,this.record,this.job,this.account}) : assert((record!=null?1:0)+(job!=null?1:0)+(account!=null?1:0)==1);
  @override
  State<OperationDialog> createState()=>_OperationDialogState();
}
class _OperationDialogState extends State<OperationDialog> {
  final form=GlobalKey<FormState>();
  final reason=TextEditingController(),password=TextEditingController();
  String channel='telephony',scenario='success';bool active=true,busy=false,stale=false;
  Map<String,dynamic>? pending;String? error;
  bool get account=>widget.account!=null;
  bool get retry=>widget.job!=null;
  bool get locked=>busy||pending!=null||stale;
  @override
  void initState(){super.initState();active=widget.account?['active']==1;}
  @override
  void dispose(){reason.dispose();password.dispose();super.dispose();}
  Future<void> submit() async {
    if(busy||stale)return;
    if(pending==null){
      if(!(form.currentState?.validate()??false))return;
      final target=widget.account?['username']??widget.job?['id']??widget.record?['id'];
      final review=account?'Login ${active?'aktif':'nonaktif'} · reset password ${password.text.isEmpty?'tidak':'ya'}. Sesi dicabut jika login dinonaktifkan atau password direset. Assignment baru memerlukan akun aktif; tugas lama tetap tercatat.'
        : retry?'Jadwalkan ulang job yang sama, skenario $scenario. Histori percobaan tidak dihapus.'
        :'Buat job $channel untuk siklus${widget.record!['cycle']}, skenario $scenario. Tidak ada panggilan/pesan keluar dan tidak mencatat hasil kontak otomatis.';
      final approved=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Tinjau operasi'),
        content:SizedBox(width:500,child:SingleChildScrollView(child:Text('$target\n$review${account||retry?'\nAlasan: ${reason.text.trim()}':''}'))),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Konfirmasi operasi'))]));
      if(approved!=true||!mounted)return;
      pending={'request_key':'operation-${DateTime.now().microsecondsSinceEpoch}',
        'expected_version':widget.account?['version']??widget.job?['version']??widget.record!['version'],
        if(account)...{'active':active,'new_password':password.text.isEmpty?null:password.text,'reason':reason.text.trim()},
        if(retry)...{'scenario':scenario,'reason':reason.text.trim()},
        if(!account&&!retry)...{'channel':channel,'scenario':scenario},
      };
    }
    setState((){busy=true;error=null;});
    try{
      final path=account?'/api/accounts/${widget.account!['id']}':retry?'/api/integrations/${widget.job!['id']}/retry':'/api/cases/${widget.record!['id']}/integrations';
      await widget.api.request(account?'PATCH':'POST',path,pending);
      if(mounted)Navigator.pop(context,true);
    }catch(e){if(mounted)setState((){error='$e';if(e is ApiException&&!e.mayHaveSucceeded&&e.status!=null&&e.status!<500){pending=null;stale=e.status==409;}});}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>AlertDialog(insetPadding:const EdgeInsets.all(16),
    title:Text(account?'Kontrol akun petugas':retry?'Pulihkan job simulasi':'Tindak lanjut simulasi'),
    content:SizedBox(width:560,child:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${widget.account?['username']??widget.job?['id']??widget.record?['id']}'),const SizedBox(height:12),
      if(account)...[
        Text('${widget.account!['active_cases']} kasus aktif. Menonaktifkan login tidak menyelesaikan atau memindahkan tugas. Status master petugas tetap terpisah.'),
        CheckboxListTile(contentPadding:EdgeInsets.zero,value:active,onChanged:locked?null:(v)=>setState(()=>active=v!),title:const Text('Login aktif')),
        TextFormField(controller:password,enabled:!locked,obscureText:true,maxLength:128,decoration:const InputDecoration(labelText:'Password baru (opsional)'),validator:(v)=>(v??'').isNotEmpty&&v!.length<12?'Minimal12karakter':null),
      ]else...[
        const Text('Seluruh integrasi bersifat simulasi lokal. Tidak menggunakan nomor telepon, tujuan pesan, atau API eksternal.'),const SizedBox(height:12),
        if(!retry)DropdownButtonFormField<String>(initialValue:channel,isExpanded:true,decoration:const InputDecoration(labelText:'Kanal simulasi'),items:const[
          DropdownMenuItem(value:'telephony',child:Text('Telephony tiruan')),DropdownMenuItem(value:'omnichannel',child:Text('Omnichannel tiruan'))],onChanged:locked?null:(v)=>setState(()=>channel=v!)),
        if(widget.api.supervisor)...[const SizedBox(height:16),DropdownButtonFormField<String>(initialValue:scenario,isExpanded:true,decoration:const InputDecoration(labelText:'Skenario adapter'),items:const[
          DropdownMenuItem(value:'success',child:Text('Berhasil simulasi')),DropdownMenuItem(value:'fail_once',child:Text('Gagal sekali, lalu berhasil')),DropdownMenuItem(value:'fail_always',child:Text('Selalu gagal (uji dead letter)'))],onChanged:locked?null:(v)=>setState(()=>scenario=v!))],
      ],
      if(account||retry)...[const SizedBox(height:16),TextFormField(controller:reason,enabled:!locked,maxLength:500,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'Alasan operasi'),validator:(v)=>(v?.trim().length??0)<10?'Minimal10karakter':null)],
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.deepOrange)),
      if(stale)const Text('Versi berubah. Tutup dialog untuk memuat ulang dan meninjau kondisi terbaru.'),
      if(pending!=null&&!busy)const Text('Hasil belum pasti. Ulangi payload yang sama atau tutup dan periksa status dari server.'),
    ])))),
    actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:Text(stale?'Tutup & muat ulang':'Tutup')),
      FilledButton(onPressed:busy||stale?null:submit,child:Text(busy?'Memproses…':pending!=null?'Periksa / ulangi operasi':'Tinjau operasi'))]);
}
