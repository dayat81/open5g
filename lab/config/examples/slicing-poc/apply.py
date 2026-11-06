# STAGED, NOT DEPLOYED — WIP v1 2026-11-06 20:21:58 +07 (Asia/Bangkok)
from pathlib import Path
import subprocess
p=Path('/home/lab/lab5g-dev')
s=p/'open5gs-src'
subprocess.run(['git','-C',str(s),'checkout','-b','dev-pcrf-rar'],check=True)
subprocess.run(['git','-C',str(s),'apply',str(p/'poc-staging/gx-admin.patch')],check=True)
for f in ['pcrf-admin-rar.c','pcrf-admin-rar.h']:
 (s/'src/pcrf'/f).write_bytes((p/'poc-staging'/f).read_bytes())
g=s/'src/pcrf/pcrf-gx-path.c'
g.write_text(g.read_text()+'\n'+(p/'poc-staging/gx-rar.c.add').read_text())
smf=p/'conf/smf.yaml'
lines=smf.read_text().splitlines()
insert=lines.index('  gtpc:')
lines[insert:insert]=['    client:','      upf:','      - address: 10.99.6.15','      - address: 10.99.6.16']
lines.extend(['      - subnet: 10.46.0.0/16','        gateway: 10.46.0.1','        dnn: slice-a','      - subnet: 10.47.0.0/16','        gateway: 10.47.0.1','        dnn: slice-b'])
smf.write_text('\n'.join(lines)+'\n')
for n in ['upf-a.yaml','upf-b.yaml']:
 (p/'conf'/n).write_bytes((p/'poc-staging'/n).read_bytes())
c=p/'docker-compose.yml'; y=c.read_text(); y+='\n'+(p/'poc-staging/core.compose.append').read_text(); c.write_text(y)
