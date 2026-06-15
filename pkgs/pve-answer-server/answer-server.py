#!/usr/bin/env python3
import argparse
import logging
import os
from aiohttp import web

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger("pve-answer-server")

def resolve_static_path(static_dir, filename):
    static_root = os.path.realpath(static_dir)

    # Reject absolute user input so joins cannot discard static_root.
    if os.path.isabs(filename):
        return None

    filepath = os.path.realpath(os.path.join(static_root, filename))

    try:
        if os.path.commonpath((static_root, filepath)) != static_root:
            return None
    except ValueError:
        return None

    return filepath

async def handle_static(request):
    filename = request.match_info.get("filename", "")
    static_dir = request.app["static_dir"]
    filepath = resolve_static_path(static_dir, filename)
    if filepath is None:
        logger.warning(f"Directory traversal attempt: {filename}")
        return web.Response(status=403, text="Forbidden")

    if not os.path.exists(filepath) or os.path.isdir(filepath):
        logger.warning(f"File not found: {filename}")
        return web.Response(status=404, text="File not found")

    logger.info(f"Serving static file: {filename}")
    return web.FileResponse(filepath)

async def handle_answer(request):
    answer_file = request.app["answer_file"]
    if not answer_file or not os.path.exists(answer_file):
        logger.error(f"Answer file not configured or missing: {answer_file}")
        return web.Response(status=500, text="Answer file not available")

    logger.info(f"Serving answer file ({request.method}) to {request.remote}")
    try:
        with open(answer_file, "r") as f:
            content = f.read()
        return web.Response(text=content, content_type="text/plain")
    except Exception as e:
        logger.error(f"Failed to read answer file: {e}")
        return web.Response(status=500, text=f"Error reading answer file: {e}")

def main():
    parser = argparse.ArgumentParser(description="Proxmox VE PXE Answer and Asset Server")
    parser.add_argument("--host", default="0.0.0.0", help="Listen host")
    parser.add_argument("--port", type=int, default=80, help="Listen port")
    parser.add_argument("--static-dir", required=True, help="Directory containing static PXE assets")
    parser.add_argument("--answer-file", required=True, help="Path to the materialized pve-answer.toml")
    args = parser.parse_args()

    # Validate directories
    if not os.path.isdir(args.static_dir):
        logger.error(f"Static directory does not exist: {args.static_dir}")
        exit(1)

    app = web.Application()
    app["static_dir"] = args.static_dir
    app["answer_file"] = args.answer_file

    # Define routes
    app.router.add_route("*", "/pve-answer.toml", handle_answer)
    app.router.add_route("*", "/pve-answer-test.toml", handle_answer)
    app.router.add_get("/{filename:.*}", handle_static)

    logger.info(f"Starting server on http://{args.host}:{args.port}")
    logger.info(f"Static directory: {args.static_dir}")
    logger.info(f"Answer file: {args.answer_file}")

    web.run_app(app, host=args.host, port=args.port, access_log=None)

if __name__ == "__main__":
    main()
