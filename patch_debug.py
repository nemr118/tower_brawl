import re

with open("serve_game.py", "r") as f:
    code = f.read()

# Add exception printing to ws_client_thread
code = code.replace("    except Exception:\\n        pass\\n\\n    # Cleanup", "    except Exception as e:\\n        print('WS ERROR:', e)\\n\\n    # Cleanup")

with open("serve_game.py", "w") as f:
    f.write(code)
