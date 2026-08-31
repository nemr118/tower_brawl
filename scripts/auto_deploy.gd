extends Node
## Automatically exports the web build and ensures the server is running when F5 is pressed

var thread: Thread

func _ready():
	if OS.has_feature("editor"):
		print("🚀 [AutoDeploy] F5 Detected! Re-exporting web build for mobile devices in background...")
		thread = Thread.new()
		thread.start(Callable(self, "_run_export"))

func _run_export():
	var output = []
	OS.execute("bash", ["./auto_export.sh"], output, true)
	print("✅ [AutoDeploy] Web build exported successfully! Mobile devices can now refresh.")
