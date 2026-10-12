#!/usr/bin/env python3
"""Phase two acceptance through the shipped JSON CLI, using synthetic data only."""
import json
import subprocess
import tempfile
import time
import sys
from pathlib import Path

BINARY = Path(__file__).resolve().parents[1] / 'target/debug/card-weave'

def run(home, command, *args, ok=True):
    result = subprocess.run([str(BINARY), str(home), command, *map(str,args)], capture_output=True, text=True)
    if ok:
        assert result.returncode in (0,5), (command,result.stderr)
        return json.loads(result.stdout)['result']
    assert result.returncode not in (0,5), command

def write(path, data):
    path.write_text(json.dumps(data,ensure_ascii=False))
    return path

def exercise(root, backend_type="fs", endpoint=None):
    old, new, peer = [root / n for n in ('old','new','peer')]
    remote = root/'remote'; remote.mkdir()
    config={'type':'fs','root':str(remote)}
    if backend_type=='webdav': config={'type':'webdav','endpoint':endpoint,'username_env':'CW_PHASE2_USER','password_env':'CW_PHASE2_SECRET','allow_loopback_http':True}
    if backend_type=='s3': config={'type':'s3','endpoint':endpoint,'region':'us-east-1','bucket':'contacts-test','access_key_env':'CW_PHASE2_USER','secret_key_env':'CW_PHASE2_SECRET','allow_loopback_http':True}
    backend=write(root/'backend.json',config)
    original=run(old,'init-legacy')
    fixture=write(root/'contact.json', {'version':2,'display_name':'Migration fixture','nickname':'nickname','addresses':[{'label':'住宅','value':'Address'}],'relations':[{'label':'朋友','value':'Manual friend'}],'dates':[{'kind':'birthday','label':'','calendar':'chinese_lunar','year':None,'month':2,'day':29,'is_leap_month':True}]})
    created=run(old,'create',fixture)
    run(old,'migrate',new,ok=False)
    assert not new.exists(), 'unsynced migration must not create destination'
    run(old,'sync',backend)
    assert run(old,'status')['settled']
    identity=run(old,'migrate',new)
    assert identity['version']==2
    for key in ('dataset','device','incarnation'): assert original[key]!=identity[key]
    assert run(new,'get',created['id'])['contact']==created
    assert run(old,'get',created['id'])['contact']==created
    run(old,'migrate',new,ok=False)
    run(peer,'init',identity['dataset'])
    run(new,'sync',backend); run(peer,'sync',backend)
    assert run(peer,'get',created['id'])['contact']==created
    # An incomplete copy cannot be opened; retry leaves it untouched.
    interrupted=root/'interrupted'
    run(interrupted,'init')
    (interrupted/'migration.pending').write_text('')
    run(interrupted,'info',ok=False)
    run(old,'migrate',interrupted,ok=False)
    retry=root/'retry'
    run(old,'migrate',retry)
    assert run(retry,'get',created['id'])['contact']==created
    def groups(home,operation,ok=True,**args):
        return run(home,'groups',write(root/'request.json',{'operation':operation,**args}),ok=ok)
    def sync_all():
        for home in (new,peer,new,peer): run(home,'sync',backend)
    g=groups(new,'create',name='Family')
    groups(new,'create',name=' family ',ok=False)
    second=run(new,'create',write(root/'second.json',{'version':2,'display_name':'Second'}))
    sync_all()
    groups(new,'set_members',id=g['id'],changes=[{'contact_id':created['id'],'expected':None,'joined':True}])
    groups(peer,'set_members',id=g['id'],changes=[{'contact_id':second['id'],'expected':None,'joined':True}])
    sync_all()
    assert groups(new,'list')[0]['count']==2
    assert len(groups(new,'contacts',group=g['id'],search='',offset=0))==2
    # Atomic stale batch: an earlier valid edit must not be partially written.
    groups(new,'set_members',ok=False,id=g['id'],changes=[{'contact_id':created['id'],'expected':'joined','joined':False},{'contact_id':second['id'],'expected':None,'joined':False}])
    assert groups(new,'list')[0]['count']==2
    groups(new,'set_members',id=g['id'],changes=[{'contact_id':created['id'],'expected':'joined','joined':False}])
    # Peer first removes then rejoins without receiving the other removal.
    groups(peer,'set_members',id=g['id'],changes=[{'contact_id':created['id'],'expected':'joined','joined':False}])
    groups(peer,'set_members',id=g['id'],changes=[{'contact_id':created['id'],'expected':'left','joined':True}])
    sync_all()
    conflict=groups(new,'conflicts')[0]
    assert conflict['entity_type']=='membership'
    assert groups(new,'list')[0]['pending']==1
    assert groups(new,'contacts',group='',search='',offset=0)==[]
    groups(new,'resolve',table=3,id=conflict['id'],observed=[c['version'] for c in conflict['candidates']],value='joined')
    sync_all()
    assert groups(peer,'conflicts')==[]
    groups(new,'rename',id=g['id'],expected='Family',name='Friends')
    sync_all()
    assert groups(peer,'list')[0]['count']==2
    # Link name is derived; source row remains unchanged after target rename.
    data=created['data'].copy()
    data['relations']=[{'label':'朋友','value':'Second','target_contact_id':second['id']}]
    linked=run(new,'update',created['id'],write(root/'linked.json',data))
    target=second['data'].copy();target['display_name']='Renamed target'
    run(new,'update',second['id'],write(root/'target.json',target))
    assert run(new,'get',created['id'])['contact']==linked
    views=run(new,'relation-views',write(root/'views.json',data))
    assert views[0]['name']=='Renamed target'
    assert any(c['id']==created['id'] for c in run(new,'list','Renamed target')['contacts'])
    bad=data.copy();bad['relations']=[{'label':'朋友','value':'Self','target_contact_id':created['id']}]
    run(new,'update',created['id'],write(root/'bad.json',bad),ok=False)
    run(new,'delete',second['id'])
    assert run(new,'relation-views',write(root/'views.json',data))[0]['state']=='unavailable'
    # Unchanged missing target may be retained while editing another field.
    data['notes']='Retained link'
    run(new,'update',created['id'],write(root/'linked.json',data))
    sync_all()
    assert run(peer,'get',created['id'])['contact']['data']==run(new,'get',created['id'])['contact']['data']
    groups(new,'delete',id=g['id'],expected='Friends')
    sync_all()
    assert groups(peer,'list')==[]
    assert run(peer,'get',created['id'])['contact'] is not None
    # Concurrent rename/deletion stays a typed group conflict.
    clash=groups(new,'create',name='Clash');sync_all()
    groups(new,'rename',id=clash['id'],expected='Clash',name='Changed')
    groups(peer,'delete',id=clash['id'],expected='Clash');sync_all()
    conflict=groups(new,'conflicts')[0]
    assert conflict['entity_type']=='group'
    groups(new,'resolve',table=2,id=clash['id'],observed=[c['version'] for c in conflict['candidates']],value=None);sync_all()
    left=groups(new,'create',name='Offline same')
    right=groups(peer,'create',name='Offline same');sync_all()
    duplicates=groups(new,'list')
    assert len(duplicates)==2 and all(g['duplicate'] for g in duplicates)
    groups(new,'set_contact_groups',id=created['id'],changes=[{'group_id':left['id'],'expected':None,'joined':True},{'group_id':right['id'],'expected':None,'joined':True}])
    own=groups(new,'contact_groups',id=created['id'])
    assert all(g['state']=='joined' for g in own)
    groups(new,'set_contact_groups',ok=False,id=created['id'],changes=[{'group_id':left['id'],'expected':'joined','joined':False},{'group_id':right['id'],'expected':None,'joined':False}])
    assert all(g['state']=='joined' for g in groups(new,'contact_groups',id=created['id']))
    # Missing resolution value must never be interpreted as deletion.
    groups(new,'resolve',ok=False,table=2,id=left['id'],observed=[])
    # Legacy conflicts block migration instead of choosing a projection.
    old_peer=root/'old-peer';run(old_peer,'init-legacy',original['dataset']);run(old_peer,'sync',backend)
    run(old,'update',created['id'],write(root/'old-left.json',{'version':2,'display_name':'Left'}))
    run(old_peer,'update',created['id'],write(root/'old-right.json',{'version':2,'display_name':'Right'}))
    run(old,'sync',backend);run(old_peer,'sync',backend);run(old,'sync',backend)
    run(old,'migrate',root/'conflicted-copy',ok=False)
    assert not (root/'conflicted-copy').exists()
    print('PASS B1/B2: group CRUD, independent members, stale atomic batch, member conflict, rename, link projection/search, self-link rejection, missing target, delete without contact loss')
    print('PASS B0: pending guard, full readback, independent identity, duplicate destination, incomplete marker, retry, second device')

def large_migration(root):
    old=root/'large-old';remote=root/'large-remote';remote.mkdir()
    backend=write(root/'backend.json',{'type':'fs','root':str(remote)})
    run(old,'init-legacy')
    fixture=write(root/'large.json',{'version':2,'display_name':'Large fixture','notes':'x'*4096})
    for i in range(1001):run(old,'create',fixture)
    for i in range(50):
        run(old,'sync',backend)
        if run(old,'status')['settled']:break
    assert run(old,'status')['settled']
    destination=root/'killed'
    proc=subprocess.Popen([str(BINARY),str(old),'migrate',str(destination)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    killed=False
    for i in range(10000):
        if (destination/'migration.pending').exists():
            proc.kill();killed=True;break
        if proc.poll() is not None:break
        time.sleep(.001)
    proc.wait()
    assert killed,'migration interruption was not observed'
    run(destination,'info',ok=False)
    run(old,'info')
    complete=root/'large-complete'
    run(old,'migrate',complete)
    total=0
    while True:
        page=run(complete,'list','',500,total)['contacts'];total+=len(page)
        if len(page)<500:break
    assert total==1001
    print('PASS B0 large: 1001 contacts, real killed process, source reopen, chunked retry, exact count')

if __name__=='__main__':
    with tempfile.TemporaryDirectory(prefix='card-weave-phase2-') as tmp:
        if '--webdav' in sys.argv or '--s3' in sys.argv:
            import os
            from acceptance import service
            kind='webdav' if '--webdav' in sys.argv else 's3'
            os.environ['CW_PHASE2_USER']='fixture';os.environ['CW_PHASE2_SECRET']='fixture-secret'
            fixture_root=Path(tmp)/'service';fixture_root.mkdir()
            tool=BINARY.parents[2]/'.agents/tmp/tools/rclone'
            with service(tool,kind,fixture_root) as endpoint:exercise(Path(tmp),kind,endpoint)
        else:exercise(Path(tmp))
        if "--large" in sys.argv:large_migration(Path(tmp))
