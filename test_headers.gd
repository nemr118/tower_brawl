extends SceneTree
func _init():
    var ws = WebSocketPeer.new()
    if "handshake_headers" in ws:
        print("YES_HEADERS")
    else:
        print("NO_HEADERS")
    quit()
