Identity = "pcrf.o5g.invalid";
Realm = "o5g.invalid";
No_SCTP;
No_TLS;
ConnectPeer = "smf.o5g.invalid" { ConnectTo = "@O5G_SMF_CORE@"; No_TLS; };
