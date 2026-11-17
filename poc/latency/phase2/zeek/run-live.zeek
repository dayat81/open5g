# poc-phase2: instance live terpisah. Hanya mglt.log + conn.log khusus flow marker (udp/9000) agar ringan di tmpfs.
@load ./run-local.zeek
hook Conn::log_policy(rec: Conn::Info, id: Log::ID, filter: Log::Filter)
    {
    if ( rec$id$resp_p !in MGLT::ports )
        break;
    }
event zeek_init() &priority=-10
    {
    # matikan semua stream lain (dns/socks/tunnel/weird...) - itu tugas netprobe-zeek-live
    local off: set[Log::ID] = set();
    for ( id in Log::active_streams )
        if ( id != MGLT::LOG && id != Conn::LOG )
            add off[id];
    for ( id in off )
        Log::disable_stream(id);
    }
