#!/usr/bin/env bash
# The server laptop's screen. Runs on tty1 after the automatic login.
# Prints the help box, then opens the deck. Quitting the deck (q) leaves a
# normal shell; type tbdash to open the deck again, tbhelp to see this box.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
[ -z "$IP" ] && IP="<no network yet>"
cat <<BOX

  ==================================================================
    TOWER BRAWL SERVER          $(cat /etc/hostname 2>/dev/null)
    Phones:  https://$IP:8443/play      PC:  http://$IP:8000
  ------------------------------------------------------------------
    Bots    tbbot add            one more bot (add chaser, sniper, turtle, rusher, griefer)
            tbbot remove         the newest bot leaves
            tbbot clear          all bots leave
    Wifi    nmcli device wifi list
            sudo nmcli device wifi connect "NAME" password "PASS"
            nmcli device         wlp3s0 should say connected
    Deck    tbdash               the live deck (q quits, a bot menu, r/x bots, w wifi help, i about)
    Code    https://github.com/nemr118/tower_brawl      (public; press i in the deck)
    Game    sudo systemctl restart towerbrawl      tblog (server log)
  ==================================================================

BOX
