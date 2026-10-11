#!/bin/sh
# boot.sh — 9router di Render Free: restore dari backup store, jalan, lalu backup berkala.
# Store: GITHUB_REPO (repo privat) atau BACKUP_URL (HTTP generik).
# Env: GITHUB_REPO, GITHUB_TOKEN, BACKUP_URL, BACKUP_TOKEN, BACKUP_INTERVAL (def 1800)

D=/app/data/db/data.sqlite
S=/tmp/r9snap.db
IV="${BACKUP_INTERVAL:-1800}"
mkdir -p /app/data/db

cat > /tmp/store.js <<'JS'
const fs=require('fs'),crypto=require('crypto');
const {DatabaseSync}=require('node:sqlite');
const DB='/app/data/db/data.sqlite',SNAP='/tmp/r9snap.db',MODE=process.argv[2];
const REPO=process.env.GITHUB_REPO||'',GT=process.env.GITHUB_TOKEN||'';
const URL=process.env.BACKUP_URL||'',TOK=process.env.BACKUP_TOKEN||'';
const API='https://api.github.com',FILE='data.sqlite';
const log=m=>console.log('['+MODE+'] '+m);
const gh=!!REPO;
const H=()=>gh?{authorization:'Bearer '+GT}:TOK?{authorization:'Bearer '+TOK}:{};

function snap(){
  if(!fs.existsSync(DB))throw new Error('DB belum ada (lazy-create)');
  try{fs.unlinkSync(SNAP)}catch(e){}
  const d=new DatabaseSync(DB,{readOnly:true});
  d.exec("VACUUM INTO '"+SNAP.replace(/'/g,"''")+"'");
  d.close();
  return fs.readFileSync(SNAP);
}
function bsha(b){const h=crypto.createHash('sha1');h.update('blob '+b.length+'\0');h.update(b);return h.digest('hex');}

async function ghMeta(){
  const r=await fetch(API+'/repos/'+REPO+'/contents/'+FILE,{headers:{...H(),accept:'application/vnd.github+json'}});
  if(!r.ok)return null;
  const j=await r.json();
  return {sha:j.sha,size:j.size};
}

async function restore(){
  let b=null;
  try{
    if(gh){
      const r=await fetch(API+'/repos/'+REPO+'/contents/'+FILE,{headers:{...H(),accept:'application/vnd.github.raw'}});
      if(r.ok)b=Buffer.from(await r.arrayBuffer());
      else if(r.status!==404)throw new Error('HTTP '+r.status);
    }else if(URL){
      const r=await fetch(URL,{headers:H()});
      if(r.ok)b=Buffer.from(await r.arrayBuffer());
    }
  }catch(e){log('FRESH (gagal ambil: '+e.message+')');return;}
  if(!b||b.length<512){log('FRESH (belum ada backup)');return;}
  fs.writeFileSync(DB,b);
  log('RESTORED '+b.length+' bytes');
}

async function backup(){
  let b;
  try{b=snap();}catch(e){log('FAIL snapshot: '+e.message);return;}
  const local=bsha(b);
  try{
    if(gh){
      const m=await ghMeta();
      if(m&&m.sha===local){log('SKIP (tidak berubah '+b.length+'B)');return;}
      const r=await fetch(API+'/repos/'+REPO+'/contents/'+FILE,{method:'PUT',
        headers:{...H(),accept:'application/vnd.github+json','content-type':'application/json'},
        body:JSON.stringify({message:'backup '+new Date().toISOString(),content:b.toString('base64'),...(m?{sha:m.sha}:{})})});
      log((r.ok?'OK ':'FAIL ')+b.length+'B github HTTP '+r.status);
      return;
    }
    if(URL){
      const r=await fetch(URL,{method:'POST',headers:{...H(),'content-type':'application/octet-stream'},body:b});
      log((r.ok?'OK ':'FAIL ')+b.length+'B http HTTP '+r.status);
      return;
    }
    log('FAIL (GITHUB_REPO / BACKUP_URL kosong)');
  }catch(e){log('FAIL '+e.message);}
}

if (MODE === 'restore') { restore(); } else { backup(); }
JS

node /tmp/store.js restore

if [ -n "$GITHUB_REPO" ] || [ -n "$BACKUP_URL" ]; then
  ( while :; do sleep "$IV"; node /tmp/store.js backup; done ) &
fi

exec node custom-server.js
