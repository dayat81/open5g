# poc-phase2: dipakai instance Zeek terpisah (bare mode). Rotasi 300 s seperti zeek-live.
@load base/frameworks/logging
@load base/frameworks/tunnels
@load base/protocols/conn
@load policy/protocols/conn/vlan-logging
# pisahkan inner GTP (S1-U) dari salinan SGi yang 5-tuple-nya sama
@load frameworks/conn_key/vlan_fivetuple
@load ./mglt.zeek
redef LogAscii::use_json = T;
redef Log::default_rotation_interval = 300secs;
