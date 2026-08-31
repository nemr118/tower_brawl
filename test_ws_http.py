import asyncio
import websockets
import http
import mimetypes
import os

async def process_request(path, request_headers):
    if path == "/ws":
        return None  # Let websockets handle it
        
    if path == "/":
        path = "/index.html"
        
    filepath = os.path.join("build/web", path.lstrip("/"))
    
    if not os.path.exists(filepath) or not os.path.isfile(filepath):
        return (http.HTTPStatus.NOT_FOUND, [], b"404 Not Found")
        
    content_type, _ = mimetypes.guess_type(filepath)
    if not content_type:
        content_type = "application/octet-stream"
        
    with open(filepath, "rb") as f:
        body = f.body = f.read()
        
    headers = [
        ("Content-Type", content_type),
        ("Content-Length", str(len(body))),
        ("Cross-Origin-Opener-Policy", "same-origin"),
        ("Cross-Origin-Embedder-Policy", "require-corp")
    ]
    
    return (http.HTTPStatus.OK, headers, body)

async def handler(websocket):
    pass

async def main():
    async with websockets.serve(handler, "localhost", 8000, process_request=process_request):
        print("Server running on port 8000")
        await asyncio.Future()  # run forever
        
if __name__ == "__main__":
    # Test script just to ensure syntax is right
    pass
